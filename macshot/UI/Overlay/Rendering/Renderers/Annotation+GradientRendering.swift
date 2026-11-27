import Cocoa

// MARK: - Gradient Rendering Support

extension Annotation {

    /// Tight geometric bounds covering all points/waypoints of the annotation (unpadded).
    var effectiveShapeBounds: NSRect {
        if (tool == .pencil || tool == .marker), let pts = points, !pts.isEmpty {
            var minX = pts[0].x, minY = pts[0].y
            var maxX = pts[0].x, maxY = pts[0].y
            for p in pts {
                if p.x < minX { minX = p.x }
                if p.x > maxX { maxX = p.x }
                if p.y < minY { minY = p.y }
                if p.y > maxY { maxY = p.y }
            }
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return boundingRect
    }

    /// Renders `drawMask` into a bounded transparency layer and fills it with `gradient` via `.sourceIn`.
    /// Passing a tight `layerRect` avoids full-screen offscreen allocations while keeping caps/wings unclipped.
    func drawWithGradientMask(
        _ gradient: AnnotationGradient,
        shapeBounds: NSRect? = nil,
        layerPadding: CGFloat? = nil,
        startPoint explicitStart: NSPoint? = nil,
        endPoint explicitEnd: NSPoint? = nil,
        alpha: CGFloat = 1.0,
        drawMask: () -> Void
    ) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            drawMask()
            return
        }

        let baseBounds = shapeBounds ?? effectiveShapeBounds
        let strokePad = max(strokeWidth / 2, 1)
        let visualBounds = NSRect(
            x: baseBounds.minX - strokePad,
            y: baseBounds.minY - strokePad,
            width: max(baseBounds.width + strokePad * 2, 2),
            height: max(baseBounds.height + strokePad * 2, 2)
        )
        let pad = layerPadding ?? max(strokeWidth * 2 + 12, 20)
        let layerRect = NSRect(
            x: baseBounds.minX - pad,
            y: baseBounds.minY - pad,
            width: max(baseBounds.width + pad * 2, 4),
            height: max(baseBounds.height + pad * 2, 4)
        )

        ctx.saveGState()
        if alpha < 0.999 {
            ctx.setAlpha(alpha)
        }
        ctx.beginTransparencyLayer(in: layerRect, auxiliaryInfo: nil)

        let maskColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        maskColor.setFill()
        maskColor.setStroke()
        drawMask()

        ctx.setBlendMode(.sourceIn)
        if let cgGradient = gradient.makeCGGradient() {
            let (p0, p1): (NSPoint, NSPoint)
            if let s = explicitStart, let e = explicitEnd, hypot(e.x - s.x, e.y - s.y) >= 1 {
                (p0, p1) = (s, e)
            } else {
                (p0, p1) = gradient.startEndPoints(in: visualBounds)
            }
            ctx.drawLinearGradient(
                cgGradient,
                start: p0,
                end: p1,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Convenience helper for UI swatches and cursor previews: clips to `path` and draws `gradient`.
    static func drawGradientFill(
        _ gradient: AnnotationGradient,
        in path: NSBezierPath,
        alpha: CGFloat = 1.0
    ) {
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let cgGradient = gradient.makeCGGradient()
        else { return }
        let rect = path.bounds
        guard rect.width > 0, rect.height > 0 else { return }

        ctx.saveGState()
        if alpha < 0.999 {
            ctx.setAlpha(alpha)
        }
        path.addClip()
        let (p0, p1) = gradient.startEndPoints(in: rect)
        ctx.drawLinearGradient(
            cgGradient,
            start: p0,
            end: p1,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }
}
