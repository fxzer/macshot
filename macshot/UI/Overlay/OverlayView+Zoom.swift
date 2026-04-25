//
//  OverlayView+Zoom.swift
//  macshot
//
//  Zoom management for OverlayView:
//  coordinate transforms, zoom state, zoom label/input, loupe preview,
//  scroll wheel and trackpad pinch handling.
//

import AppKit

extension OverlayView {

    // MARK: - Coordinate Transforms

    /// Convert a canvas-space point to view-space (reverse of viewToCanvas).
    func canvasToView(_ p: NSPoint) -> NSPoint {
        if isInsideScrollView { return restorePointFromEditor(p) }
        var q = p
        if zoomLevel != 1.0 || zoomAnchorCanvas != .zero || zoomAnchorView != .zero {
            q = NSPoint(
                x: zoomAnchorView.x + (p.x - zoomAnchorCanvas.x) * zoomLevel,
                y: zoomAnchorView.y + (p.y - zoomAnchorCanvas.y) * zoomLevel
            )
        }
        return restorePointFromEditor(q)
    }

    /// Convert a point in view space to canvas (annotation) space by reversing the zoom transform.
    func viewToCanvas(_ p: NSPoint) -> NSPoint {
        if isInsideScrollView { return adjustPointForEditor(p) }
        let q = adjustPointForEditor(p)
        if zoomLevel == 1.0 && zoomAnchorCanvas == .zero && zoomAnchorView == .zero { return q }
        guard zoomAnchorCanvas != .zero || zoomAnchorView != .zero else { return q }
        return NSPoint(
            x: zoomAnchorCanvas.x + (q.x - zoomAnchorView.x) / zoomLevel,
            y: zoomAnchorCanvas.y + (q.y - zoomAnchorView.y) / zoomLevel
        )
    }

    func applyZoomTransform(to context: NSGraphicsContext) {
        if isInsideScrollView { return }
        if zoomLevel == 1.0 && zoomAnchorCanvas == .zero && zoomAnchorView == .zero { return }
        guard zoomAnchorCanvas != .zero || zoomAnchorView != .zero else { return }
        let cgCtx = context.cgContext
        // screen = anchorView + (canvas - anchorCanvas) * zoom
        cgCtx.translateBy(
            x: zoomAnchorView.x - zoomAnchorCanvas.x * zoomLevel,
            y: zoomAnchorView.y - zoomAnchorCanvas.y * zoomLevel)
        cgCtx.scaleBy(x: zoomLevel, y: zoomLevel)
    }

    /// Apply editor canvas offset + zoom transform. Use this for all canvas-space drawing.
    func applyCanvasTransform(to context: NSGraphicsContext) {
        applyEditorTransform(to: context)
        applyZoomTransform(to: context)
    }

    // MARK: - Zoom State

    /// Set zoom level, pinning the given view-space cursor point in place.
    func setZoom(_ level: CGFloat, cursorView: NSPoint) {
        let canvasUnderCursor = viewToCanvas(cursorView)
        zoomLevel = max(zoomMin, min(zoomMax, level))

        if abs(zoomLevel - 1.0) < 0.005 {
            zoomLevel = 1.0
            zoomAnchorCanvas = .zero
            zoomAnchorView = .zero
        } else {
            zoomAnchorCanvas = canvasUnderCursor
            zoomAnchorView = cursorView
            clampZoomAnchor()
        }
        showZoomLabel()
        needsDisplay = true
    }

    /// Reset zoom to 1× (no transform).
    func resetZoom() {
        zoomLevel = 1.0
        zoomAnchorCanvas = .zero
        zoomAnchorView = .zero
    }

    /// Clamp zoomAnchorView so the image doesn't scroll out of the visible area.
    ///
    /// zoom > 1×: keep all four image edges inside selectionRect (no empty border visible).
    /// zoom < 1×: allow free panning but keep image partially visible.
    func clampZoomAnchor() {
        if zoomLevel == 1.0 { return }
        let r = selectionRect
        let z = zoomLevel
        let ac = zoomAnchorCanvas
        var av = zoomAnchorView

        if z > 1.0 {
            let maxAVx = r.minX - (r.minX - ac.x) * z
            let minAVx = r.maxX - (r.maxX - ac.x) * z
            av.x = max(minAVx, min(maxAVx, av.x))

            let maxAVy = r.minY - (r.minY - ac.y) * z
            let minAVy = r.maxY - (r.maxY - ac.y) * z
            av.y = max(minAVy, min(maxAVy, av.y))
        }

        zoomAnchorView = av
    }

    // MARK: - Zoom Label & Fade

    func showZoomLabel() {
        zoomLabelOpacity = 1.0
        zoomFadeTimer?.invalidate()
        zoomFadeTimer = nil
        if zoomLevel == 1.0 {
            zoomFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) {
                [weak self] _ in
                self?.fadeOutZoomLabel()
            }
        }
    }

    func fadeOutZoomLabel() {
        guard zoomLevel == 1.0 else { return }
        zoomFadingOut = true
        let step: CGFloat = 0.08
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.zoomLevel != 1.0 {
                self.zoomLabelOpacity = 1.0
                self.zoomFadingOut = false
                t.invalidate()
                self.needsDisplay = true
                return
            }
            self.zoomLabelOpacity -= step
            if self.zoomLabelOpacity <= 0 {
                self.zoomLabelOpacity = 0
                self.zoomFadingOut = false
                t.invalidate()
            }
            self.needsDisplay = true
        }
    }

    // MARK: - Zoom Label Drawing

    func drawZoomLabel() {
        let sizeLabelRect = sharedSizeLabelRect
        guard sizeLabelRect != .zero else { return }
        let zoom = zoomLevel
        let text: String
        if abs(zoom - 1.0) < 0.005 {
            text = "1×"
        } else if zoom >= 10 {
            text = String(format: "%.0f×", zoom)
        } else {
            text = String(format: "%.1f×", zoom).replacingOccurrences(of: ".0×", with: "×")
        }

        let alpha = zoomLabelOpacity
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.sharedSizeLabelFont,
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(alpha),
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let labelW = textSize.width + padding * 2
        let labelH = sizeLabelRect.height
        let gap: CGFloat = 6
        let edge: CGFloat = 4
        let labelY = sizeLabelRect.minY

        var labelX = sizeLabelRect.maxX + gap
        if labelX + labelW > bounds.maxX - edge {
            let leftX = sizeLabelRect.minX - gap - labelW
            if leftX >= bounds.minX + edge {
                labelX = leftX
            }
        }
        labelX = min(max(labelX, bounds.minX + edge), bounds.maxX - edge - labelW)

        let rect = NSRect(x: labelX, y: labelY, width: labelW, height: labelH)
        zoomLabelRect = rect

        let bgColor = ToolbarLayout.bgColor.withAlphaComponent(alpha * 0.85)
        bgColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: NSPoint(x: labelX + padding, y: labelY + padding / 2), withAttributes: attrs)
    }

    // MARK: - Crop

    /// Crop the screenshot to `viewRect` (canvas-space, within selectionRect),
    /// translate all annotations accordingly, and reset zoom.
    func commitCrop(viewRect: NSRect) {
        guard let originalImage = screenshotImage,
            let cgOriginal = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let canvasRect = viewRect
        let pointsW = originalImage.size.width
        let pixScale = CGFloat(cgOriginal.width) / pointsW

        let normX = (canvasRect.minX - selectionRect.minX) / selectionRect.width
        let normY = (canvasRect.minY - selectionRect.minY) / selectionRect.height
        let normW = canvasRect.width / selectionRect.width
        let normH = canvasRect.height / selectionRect.height

        let cgW = CGFloat(cgOriginal.width)
        let cgH = CGFloat(cgOriginal.height)
        let cgPixelRect = CGRect(
            x: max(0, normX * cgW),
            y: max(0, (1.0 - normY - normH) * cgH),
            width: min(normW * cgW, cgW - max(0, normX * cgW)),
            height: min(normH * cgH, cgH - max(0, (1.0 - normY - normH) * cgH))
        )

        guard cgPixelRect.width > 0, cgPixelRect.height > 0,
            let croppedCG = cgOriginal.cropping(to: cgPixelRect)
        else { return }

        let prevImage = originalImage.copy() as! NSImage
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: []))
        redoStack.removeAll()

        let dx = selectionRect.minX - canvasRect.minX
        let dy = selectionRect.minY - canvasRect.minY
        for ann in annotations { ann.move(dx: dx, dy: dy) }

        let croppedPointSize = NSSize(
            width: CGFloat(croppedCG.width) / pixScale,
            height: CGFloat(croppedCG.height) / pixScale)
        replaceScreenshotImage(croppedCG, size: croppedPointSize)
        selectionRect = NSRect(origin: .zero, size: croppedPointSize)
        cachedCompositedImage = nil

        if isInsideScrollView {
            frame.size = croppedPointSize
            enclosingScrollView?.magnification = 1.0
            if let topBar = chromeParentView?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
                topBar.updateSizeLabel(width: croppedCG.width, height: croppedCG.height)
                topBar.updateZoom(1.0)
            }
        } else {
            resetZoom()
        }
        currentTool = .arrow
        rebuildToolbarLayout()
        needsDisplay = true
    }
}
