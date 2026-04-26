//
//  OverlayView+SelectionResize.swift
//  macshot
//
//  Selection resize helpers for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Selection Resizing

    var activeAspectRatio: CGFloat? {
        guard aspectRatioLock != .none else { return nil }
        return aspectRatioLock.ratio
    }

    private func snapAxis(for handle: ResizeHandle) -> AspectRatioSnapAxis {
        switch handle {
        case .top, .bottom:
            return .height
        default:
            return .width
        }
    }

    func resizedSelectionRect(
        from rect: NSRect,
        handle: ResizeHandle,
        to point: NSPoint,
        minSize: CGFloat,
        aspectRatio: CGFloat?
    ) -> NSRect {
        let r = rect

        if let targetRatio = aspectRatio, targetRatio > 0 {
            let axis = snapAxis(for: handle)

            switch handle {
            case .bottomRight:
                let rawWidth = max(minSize, point.x - r.minX)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.minX, y: r.maxY - snapped.height, width: snapped.width,
                    height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .bottomLeft:
                let rawWidth = max(minSize, r.maxX - point.x)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.maxX - snapped.width,
                    y: r.maxY - snapped.height,
                    width: snapped.width,
                    height: snapped.height
                )
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .topRight:
                let rawWidth = max(minSize, point.x - r.minX)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(x: r.minX, y: r.minY, width: snapped.width, height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .topLeft:
                let rawWidth = max(minSize, r.maxX - point.x)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.maxX - snapped.width, y: r.minY, width: snapped.width,
                    height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .right:
                let rawWidth = max(minSize, point.x - r.minX)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.minX, y: r.maxY - snapped.height, width: snapped.width,
                    height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .left:
                let rawWidth = max(minSize, r.maxX - point.x)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.maxX - snapped.width,
                    y: r.maxY - snapped.height,
                    width: snapped.width,
                    height: snapped.height
                )
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .bottom:
                let rawHeight = max(minSize, r.maxY - point.y)
                let snapped = snappedLockedSelectionSize(
                    width: rawHeight * targetRatio,
                    height: rawHeight,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.minX, y: r.maxY - snapped.height, width: snapped.width,
                    height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            case .top:
                let rawHeight = max(minSize, point.y - r.minY)
                let snapped = snappedLockedSelectionSize(
                    width: rawHeight * targetRatio,
                    height: rawHeight,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let rect = NSRect(x: r.minX, y: r.minY, width: snapped.width, height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect

            default:
                clearSelectionSizeSnapState()
                return r
            }
        }

        if allowsFreeformSizeSnap {
            switch handle {
            case .topLeft:
                let rawWidth = r.maxX - min(point.x, r.maxX - minSize)
                let rawHeight = max(point.y, r.minY + minSize) - r.minY
                let snapped = snappedFreeformSelectionSize(
                    width: rawWidth,
                    height: rawHeight,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.maxX - snapped.width, y: r.minY, width: snapped.width,
                    height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .topRight:
                let rawWidth = max(point.x, r.minX + minSize) - r.minX
                let rawHeight = max(point.y, r.minY + minSize) - r.minY
                let snapped = snappedFreeformSelectionSize(
                    width: rawWidth,
                    height: rawHeight,
                    minSize: minSize
                )
                let rect = NSRect(x: r.minX, y: r.minY, width: snapped.width, height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .bottomLeft:
                let rawWidth = r.maxX - min(point.x, r.maxX - minSize)
                let rawHeight = r.maxY - min(point.y, r.maxY - minSize)
                let snapped = snappedFreeformSelectionSize(
                    width: rawWidth,
                    height: rawHeight,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.maxX - snapped.width,
                    y: r.maxY - snapped.height,
                    width: snapped.width,
                    height: snapped.height
                )
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .bottomRight:
                let rawWidth = max(point.x, r.minX + minSize) - r.minX
                let rawHeight = r.maxY - min(point.y, r.maxY - minSize)
                let snapped = snappedFreeformSelectionSize(
                    width: rawWidth,
                    height: rawHeight,
                    minSize: minSize
                )
                let rect = NSRect(
                    x: r.minX, y: r.maxY - snapped.height, width: snapped.width,
                    height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .top:
                let rawHeight = max(point.y, r.minY + minSize) - r.minY
                let snapped = snappedFreeformSelectionSize(
                    width: r.width,
                    height: rawHeight,
                    minSize: minSize,
                    snapWidth: false,
                    snapHeight: true
                )
                let rect = NSRect(x: r.minX, y: r.minY, width: r.width, height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .bottom:
                let rawHeight = r.maxY - min(point.y, r.maxY - minSize)
                let snapped = snappedFreeformSelectionSize(
                    width: r.width,
                    height: rawHeight,
                    minSize: minSize,
                    snapWidth: false,
                    snapHeight: true
                )
                let rect = NSRect(
                    x: r.minX, y: r.maxY - snapped.height, width: r.width, height: snapped.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .left:
                let rawWidth = r.maxX - min(point.x, r.maxX - minSize)
                let snapped = snappedFreeformSelectionSize(
                    width: rawWidth,
                    height: r.height,
                    minSize: minSize,
                    snapWidth: true,
                    snapHeight: false
                )
                let rect = NSRect(
                    x: r.maxX - snapped.width, y: r.minY, width: snapped.width, height: r.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            case .right:
                let rawWidth = max(point.x, r.minX + minSize) - r.minX
                let snapped = snappedFreeformSelectionSize(
                    width: rawWidth,
                    height: r.height,
                    minSize: minSize,
                    snapWidth: true,
                    snapHeight: false
                )
                let rect = NSRect(x: r.minX, y: r.minY, width: snapped.width, height: r.height)
                updateSelectionSizeSnapGuides(for: rect, handle: handle)
                return rect
            default:
                break
            }
        }

        clearSelectionSizeSnapState()

        switch handle {
        case .topLeft:
            let newX = min(point.x, r.maxX - minSize)
            let newMaxY = max(point.y, r.minY + minSize)
            return NSRect(x: newX, y: r.minY, width: r.maxX - newX, height: newMaxY - r.minY)
        case .topRight:
            let newMaxX = max(point.x, r.minX + minSize)
            let newMaxY = max(point.y, r.minY + minSize)
            return NSRect(
                x: r.minX, y: r.minY, width: newMaxX - r.minX, height: newMaxY - r.minY)
        case .bottomLeft:
            let newX = min(point.x, r.maxX - minSize)
            let newY = min(point.y, r.maxY - minSize)
            return NSRect(x: newX, y: newY, width: r.maxX - newX, height: r.maxY - newY)
        case .bottomRight:
            let newMaxX = max(point.x, r.minX + minSize)
            let newY = min(point.y, r.maxY - minSize)
            return NSRect(x: r.minX, y: newY, width: newMaxX - r.minX, height: r.maxY - newY)
        case .top:
            let newMaxY = max(point.y, r.minY + minSize)
            return NSRect(x: r.minX, y: r.minY, width: r.width, height: newMaxY - r.minY)
        case .bottom:
            let newY = min(point.y, r.maxY - minSize)
            return NSRect(x: r.minX, y: newY, width: r.width, height: r.maxY - newY)
        case .left:
            let newX = min(point.x, r.maxX - minSize)
            return NSRect(x: newX, y: r.minY, width: r.maxX - newX, height: r.height)
        case .right:
            let newMaxX = max(point.x, r.minX + minSize)
            return NSRect(x: r.minX, y: r.minY, width: newMaxX - r.minX, height: r.height)
        default:
            return r
        }
    }

    func resizeSelection(to point: NSPoint) {
        let minSize: CGFloat = 10
        if activeAspectRatio == nil {
            clearSelectionSizeSnapState()
        }
        selectionRect = resizedSelectionRect(
            from: selectionRect,
            handle: resizeHandle,
            to: point,
            minSize: minSize,
            aspectRatio: activeAspectRatio
        )
    }
}
