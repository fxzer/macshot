//
//  OverlayView+SelectionDrag.swift
//  macshot
//
//  Selection drag helpers and arrow key movement.
//

import AppKit

extension OverlayView {

    // MARK: - Arrow Key Movement

    func handleArrowKeys(with event: NSEvent) -> Bool {
        let dx: CGFloat
        let dy: CGFloat

        switch event.keyCode {
        case 123: dx = -1; dy = 0
        case 124: dx = 1; dy = 0
        case 125: dx = 0; dy = -1
        case 126: dx = 0; dy = 1
        default:
            return false
        }

        if isColorSamplerMagnifierVisible || state == .selecting || currentTool == .colorSampler {
            return moveColorSamplerPointBy(dx: dx, dy: dy)
        }

        if !selectedAnnotations.isEmpty {
            moveSelectedAnnotations(dx: dx, dy: dy)
            return true
        }

        if state == .selected && canDragSelection() {
            moveSelectionRect(dx: dx, dy: dy)
            return true
        }

        return false
    }

    func updateSelectionRectForCurrentSelectionDrag(to point: NSPoint, shiftHeld: Bool) {
        if spaceRepositioning {
            let dx = point.x - spaceRepositionLast.x
            let dy = point.y - spaceRepositionLast.y
            selectionStart.x += dx
            selectionStart.y += dy
            spaceRepositionLast = point
        }

        let rawW = abs(point.x - selectionStart.x)
        let rawH = abs(point.y - selectionStart.y)

        var w: CGFloat
        var h: CGFloat

        if aspectRatioLock != .none {
            let targetRatio = aspectRatioLock.ratio
            let minSelectionSize: CGFloat = 1
            if rawH > 0 {
                let proposedW = rawH * targetRatio
                if proposedW <= rawW {
                    let snapped = snappedLockedSelectionSize(
                        width: max(1, proposedW),
                        height: max(1, rawH),
                        ratio: targetRatio,
                        snapAxis: .height,
                        minSize: minSelectionSize
                    )
                    w = snapped.width
                    h = snapped.height
                } else {
                    let snapped = snappedLockedSelectionSize(
                        width: max(1, rawW),
                        height: max(1, rawW / targetRatio),
                        ratio: targetRatio,
                        snapAxis: .width,
                        minSize: minSelectionSize
                    )
                    w = snapped.width
                    h = snapped.height
                }
            } else {
                let snapped = snappedLockedSelectionSize(
                    width: max(1, rawW),
                    height: max(1, rawW / targetRatio),
                    ratio: targetRatio,
                    snapAxis: .width,
                    minSize: minSelectionSize
                )
                w = snapped.width
                h = snapped.height
            }
        } else if shiftHeld {
            let squareSize = max(1, min(rawW, rawH))
            let snapped = snappedFreeformSelectionSize(
                width: squareSize,
                height: squareSize,
                minSize: 1
            )
            w = snapped.width
            h = snapped.height
        } else {
            let snapped = snappedFreeformSelectionSize(
                width: max(1, rawW),
                height: max(1, rawH),
                minSize: 1
            )
            w = snapped.width
            h = snapped.height
        }

        let x = selectionStart.x < point.x ? selectionStart.x : selectionStart.x - w
        let y = selectionStart.y < point.y ? selectionStart.y : selectionStart.y - h
        let oldRect = selectionRect
        selectionRect = NSRect(x: x, y: y, width: w, height: h)
        if selectionSizeSnapActive {
            updateSelectionSizeSnapGuidesForSelectionDrag(
                rect: selectionRect,
                growsTowardRight: selectionStart.x < point.x,
                growsTowardTop: selectionStart.y < point.y
            )
        }
        overlayDelegate?.overlayViewSelectionDidChange(selectionRect)
        // Dirty-rect redraw: only the changed selection area + size label region,
        // not the full screen. Selection lives in canvas space here.
        invalidateCanvasRects([oldRect, selectionRect], pad: 16)

        updateMagnifierIfNeeded()
    }

    func moveSelectedAnnotations(dx: CGFloat, dy: CGFloat) {
        for annotation in selectedAnnotations {
            annotation.move(dx: dx, dy: dy)
        }
        cachedCompositedImage = nil
        needsDisplay = true
    }

    func moveSelectionRect(dx: CGFloat, dy: CGFloat) {
        selectionRect.origin.x += dx
        selectionRect.origin.y += dy
        needsDisplay = true
    }

    func canDragSelection() -> Bool {
        return !isRecording
            && !isScrollCapturing
            && !isDraggingAnnotation
            && !selectionRect.isEmpty
            && currentTool != .crop
    }
}
