import AppKit

extension OverlayView {
    /// Collect all snap target X and Y values from the selection rect and existing annotations.
    func collectSnapTargets(excluding: Annotation? = nil) -> (xs: [CGFloat], ys: [CGFloat]) {
        var xs: [CGFloat] = []
        var ys: [CGFloat] = []

        // Selection rect edges and center
        xs += [selectionRect.minX, selectionRect.midX, selectionRect.maxX]
        ys += [selectionRect.minY, selectionRect.midY, selectionRect.maxY]

        // Existing annotation bounding rects
        for ann in annotations where ann !== excluding {
            let r = ann.boundingRect
            guard r.width > 0 || r.height > 0 else { continue }
            xs += [r.minX, r.midX, r.maxX]
            ys += [r.minY, r.midY, r.maxY]
        }

        return (xs, ys)
    }

    /// Snap a point's X and Y to the nearest target within threshold. Returns snapped point and sets guide lines.
    func snapPoint(_ point: NSPoint, excluding: Annotation? = nil) -> NSPoint {
        guard snapGuidesEnabled else {
            snapGuideX = nil
            snapGuideY = nil
            return point
        }

        let (xs, ys) = collectSnapTargets(excluding: excluding)
        var result = point
        snapGuideX = nil
        snapGuideY = nil

        // Snap X
        var bestDx: CGFloat = snapThreshold + 1
        for tx in xs {
            let d = abs(point.x - tx)
            if d < bestDx {
                bestDx = d
                result.x = tx
                snapGuideX = tx
            }
        }
        if bestDx > snapThreshold {
            snapGuideX = nil
            result.x = point.x
        }

        // Snap Y
        var bestDy: CGFloat = snapThreshold + 1
        for ty in ys {
            let d = abs(point.y - ty)
            if d < bestDy {
                bestDy = d
                result.y = ty
                snapGuideY = ty
            }
        }
        if bestDy > snapThreshold {
            snapGuideY = nil
            result.y = point.y
        }

        return result
    }

    /// Snap a rect (for move operations) — checks all edges and center against targets.
    /// Returns the delta adjustment needed.
    func snapRectDelta(rect: NSRect, excluding: Annotation? = nil) -> (dx: CGFloat, dy: CGFloat) {
        guard snapGuidesEnabled else {
            snapGuideX = nil
            snapGuideY = nil
            return (0, 0)
        }

        let (xs, ys) = collectSnapTargets(excluding: excluding)
        let edgesX = [rect.minX, rect.midX, rect.maxX]
        let edgesY = [rect.minY, rect.midY, rect.maxY]

        snapGuideX = nil
        snapGuideY = nil
        var bestDx: CGFloat = snapThreshold + 1
        var snapDx: CGFloat = 0
        var bestDy: CGFloat = snapThreshold + 1
        var snapDy: CGFloat = 0

        for ex in edgesX {
            for tx in xs {
                let d = abs(ex - tx)
                if d < bestDx {
                    bestDx = d
                    snapDx = tx - ex
                    snapGuideX = tx
                }
            }
        }
        if bestDx > snapThreshold {
            snapGuideX = nil
            snapDx = 0
        }

        for ey in edgesY {
            for ty in ys {
                let d = abs(ey - ty)
                if d < bestDy {
                    bestDy = d
                    snapDy = ty - ey
                    snapGuideY = ty
                }
            }
        }
        if bestDy > snapThreshold {
            snapGuideY = nil
            snapDy = 0
        }

        return (snapDx, snapDy)
    }

    /// Draw snap guide lines (called from draw after annotations, before toolbars).
    func drawSnapGuides() {
        guard snapGuidesEnabled else { return }

        let guideColor = NSColor.controlAccentColor.withAlphaComponent(0.8)
        guideColor.setStroke()

        if let gx = snapGuideX {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: gx, y: selectionRect.minY))
            line.line(to: NSPoint(x: gx, y: selectionRect.maxY))
            line.lineWidth = 0.5
            let pattern: [CGFloat] = [4, 3]
            line.setLineDash(pattern, count: 2, phase: 0)
            line.stroke()
        }

        if let gy = snapGuideY {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: selectionRect.minX, y: gy))
            line.line(to: NSPoint(x: selectionRect.maxX, y: gy))
            line.lineWidth = 0.5
            let pattern: [CGFloat] = [4, 3]
            line.setLineDash(pattern, count: 2, phase: 0)
            line.stroke()
        }
    }

    func drawSelectionSizeSnapGuides() {
        guard selectionSizeSnapActive, snapGuidesEnabled else { return }

        let guideColor = NSColor.controlAccentColor.withAlphaComponent(0.82)
        let extensionLength: CGFloat = 28
        let pattern: [CGFloat] = [6, 4]
        guideColor.setStroke()

        if let gx = selectionSizeSnapGuideX {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: gx, y: selectionRect.minY - extensionLength))
            line.line(to: NSPoint(x: gx, y: selectionRect.maxY + extensionLength))
            line.lineWidth = 1
            line.setLineDash(pattern, count: pattern.count, phase: 0)
            line.stroke()
        }

        if let gy = selectionSizeSnapGuideY {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: selectionRect.minX - extensionLength, y: gy))
            line.line(to: NSPoint(x: selectionRect.maxX + extensionLength, y: gy))
            line.lineWidth = 1
            line.setLineDash(pattern, count: pattern.count, phase: 0)
            line.stroke()
        }
    }

    func clearSelectionSizeSnapState() {
        selectionSizeSnapActive = false
        selectionSizeSnapWidthActive = false
        selectionSizeSnapHeightActive = false
        selectionSizeSnapGuideX = nil
        selectionSizeSnapGuideY = nil
    }

    func applySelectionSizeSnapFeedback(widthActive: Bool, heightActive: Bool) {
        selectionSizeSnapWidthActive = widthActive
        selectionSizeSnapHeightActive = heightActive
        selectionSizeSnapActive = widthActive || heightActive

        if !selectionSizeSnapActive {
            selectionSizeSnapGuideX = nil
            selectionSizeSnapGuideY = nil
        }
    }

    func updateSelectionSizeSnapGuides(for rect: NSRect, handle: ResizeHandle) {
        guard selectionSizeSnapActive else {
            selectionSizeSnapGuideX = nil
            selectionSizeSnapGuideY = nil
            return
        }

        let verticalGuideX: CGFloat
        let horizontalGuideY: CGFloat

        switch handle {
        case .topLeft:
            verticalGuideX = rect.minX
            horizontalGuideY = rect.maxY
        case .topRight:
            verticalGuideX = rect.maxX
            horizontalGuideY = rect.maxY
        case .bottomLeft:
            verticalGuideX = rect.minX
            horizontalGuideY = rect.minY
        case .bottomRight:
            verticalGuideX = rect.maxX
            horizontalGuideY = rect.minY
        case .top:
            verticalGuideX = rect.maxX
            horizontalGuideY = rect.maxY
        case .bottom:
            verticalGuideX = rect.maxX
            horizontalGuideY = rect.minY
        case .left:
            verticalGuideX = rect.minX
            horizontalGuideY = rect.minY
        case .right:
            verticalGuideX = rect.maxX
            horizontalGuideY = rect.minY
        default:
            selectionSizeSnapGuideX = nil
            selectionSizeSnapGuideY = nil
            return
        }

        selectionSizeSnapGuideX = selectionSizeSnapWidthActive ? verticalGuideX : nil
        selectionSizeSnapGuideY = selectionSizeSnapHeightActive ? horizontalGuideY : nil
    }

    func updateSelectionSizeSnapFeedbackFlags(for pixelSize: CGSize) {
        guard selectionSizeSnapActive else {
            selectionSizeSnapWidthActive = false
            selectionSizeSnapHeightActive = false
            return
        }

        applySelectionSizeSnapFeedback(
            widthActive: isAspectRatioSnapTarget(pixelSize.width, for: pixelSize),
            heightActive: isAspectRatioSnapTarget(pixelSize.height, for: pixelSize)
        )
    }

    func updateSelectionSizeSnapGuidesForSelectionDrag(
        rect: NSRect,
        growsTowardRight: Bool,
        growsTowardTop: Bool
    ) {
        guard selectionSizeSnapActive else {
            selectionSizeSnapGuideX = nil
            selectionSizeSnapGuideY = nil
            return
        }

        selectionSizeSnapGuideX =
            selectionSizeSnapWidthActive ? (growsTowardRight ? rect.maxX : rect.minX) : nil
        selectionSizeSnapGuideY =
            selectionSizeSnapHeightActive ? (growsTowardTop ? rect.maxY : rect.minY) : nil
    }

    func snappedLockedSelectionSize(
        width: CGFloat,
        height: CGFloat,
        ratio: CGFloat,
        snapAxis: AspectRatioSnapAxis,
        minSize: CGFloat
    ) -> CGSize {
        guard allowsLockedAspectRatioSizeSnap else {
            clearSelectionSizeSnapState()
            return CGSize(width: width, height: height)
        }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSize = CGSize(width: width * scale, height: height * scale)
        let drivingDimension = (snapAxis == .width ? width : height) * scale
        let result = snapAspectRatioSize(
            drivingDimension: drivingDimension,
            threshold: selectionSizeSnapThresholdPx,
            ratio: ratio,
            minSize: minSize * scale,
            snapAxis: snapAxis,
            currentSize: pixelSize
        )

        selectionSizeSnapActive = result.isSnapped
        updateSelectionSizeSnapFeedbackFlags(for: result.size)
        if !result.isSnapped {
            selectionSizeSnapGuideX = nil
            selectionSizeSnapGuideY = nil
        }

        return CGSize(width: result.size.width / scale, height: result.size.height / scale)
    }

    func snappedFreeformSelectionSize(
        width: CGFloat,
        height: CGFloat,
        minSize: CGFloat,
        snapWidth: Bool = true,
        snapHeight: Bool = true
    ) -> CGSize {
        guard allowsFreeformSizeSnap else {
            clearSelectionSizeSnapState()
            return CGSize(width: width, height: height)
        }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSize = CGSize(width: width * scale, height: height * scale)
        let result = snapFreeformSize(
            size: pixelSize,
            threshold: selectionSizeSnapThresholdPx,
            minSize: minSize * scale,
            snapWidth: snapWidth,
            snapHeight: snapHeight
        )

        applySelectionSizeSnapFeedback(
            widthActive: result.widthSnapped,
            heightActive: result.heightSnapped
        )

        return CGSize(width: result.size.width / scale, height: result.size.height / scale)
    }

    func drawCropPreview() {
        let dimColor = NSColor.black.withAlphaComponent(0.4)
        dimColor.setFill()
        NSBezierPath(
            rect: NSRect(
                x: selectionRect.minX, y: cropDragRect.maxY,
                width: selectionRect.width, height: selectionRect.maxY - cropDragRect.maxY)
        ).fill()
        NSBezierPath(
            rect: NSRect(
                x: selectionRect.minX, y: selectionRect.minY,
                width: selectionRect.width, height: cropDragRect.minY - selectionRect.minY)
        ).fill()
        NSBezierPath(
            rect: NSRect(
                x: selectionRect.minX, y: cropDragRect.minY,
                width: cropDragRect.minX - selectionRect.minX, height: cropDragRect.height)
        ).fill()
        NSBezierPath(
            rect: NSRect(
                x: cropDragRect.maxX, y: cropDragRect.minY,
                width: selectionRect.maxX - cropDragRect.maxX, height: cropDragRect.height)
        ).fill()
    }
}
