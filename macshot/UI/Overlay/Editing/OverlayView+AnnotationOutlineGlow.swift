import AppKit
import CoreImage

extension OverlayView {
    /// Shared CIContext — uses the canonical context from BeautifyRenderer to avoid
    /// redundant GPU resource allocation (~10MB per context).
    /// Using GPU acceleration with working color space for better performance.
    static var sharedCIContext: CIContext { BeautifyRenderer.sharedCIContext }

    /// Draw a generic outline glow around any annotation by rendering it offscreen,
    /// dilating the alpha mask, then compositing the outline back. Cached on the annotation.
    func drawAnnotationOutlineGlow(_ annotation: Annotation) {
        // Skip expensive glow during resize — bounding box changes every frame,
        // invalidating the CIFilter cache. A simple stroke rect is drawn instead.
        if isResizingAnnotation && isSelected(annotation) {
            let rect = annotation.boundingRect.insetBy(dx: -2, dy: -2)
            ToolbarLayout.accentColor.withAlphaComponent(0.5).setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.lineWidth = 2
            path.stroke()
            return
        }
        let outlineWidth: CGFloat = 3
        // Generous padding — accounts for stroke width, line caps, Chaikin smoothing overshoot,
        // arrowheads, and the dilation radius. Bitmap is cached so size doesn't matter per-frame.
        let effectiveStroke = annotation.strokeWidth
        let padding = effectiveStroke + outlineWidth + 20

        // Compute actual bounding box — for pencil/marker, use the points array
        // since boundingRect only considers startPoint/endPoint.
        let baseBBox: NSRect
        if let pts = annotation.points, !pts.isEmpty,
           (annotation.tool == .pencil || annotation.tool == .marker) {
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for p in pts {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            baseBBox = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        } else {
            baseBBox = annotation.boundingRect
        }

        // For the glow cache, always use the unrotated bbox. We'll apply rotation at draw time.
        // This avoids regenerating the expensive CIFilter pipeline on every rotation change.
        let unrotatedBBox = baseBBox.insetBy(dx: -padding, dy: -padding)
        guard unrotatedBBox.width > 0, unrotatedBBox.height > 0 else { return }

        // Expand to rotated bounding box for the draw rect so the image covers the full rotated shape
        let drawBBox: NSRect
        if annotation.rotation != 0 && annotation.supportsRotation {
            let cx = unrotatedBBox.midX, cy = unrotatedBBox.midY
            let cos_r = abs(cos(annotation.rotation)), sin_r = abs(sin(annotation.rotation))
            let w = unrotatedBBox.width, h = unrotatedBBox.height
            let rotW = w * cos_r + h * sin_r
            let rotH = w * sin_r + h * cos_r
            drawBBox = NSRect(x: cx - rotW / 2, y: cy - rotH / 2, width: rotW, height: rotH)
        } else {
            drawBBox = unrotatedBBox
        }

        // Use cached glow if available and unrotated position hasn't changed.
        // Rotation is handled at draw time via transform, not by regenerating the glow.
        if let cached = annotation.outlineGlowImage, annotation.outlineGlowRect == unrotatedBBox {
            guard let context = NSGraphicsContext.current else { return }
            context.cgContext.saveGState()
            context.cgContext.setAlpha(0.55)
            if annotation.rotation != 0 && annotation.supportsRotation {
                let cx = unrotatedBBox.midX, cy = unrotatedBBox.midY
                context.cgContext.translateBy(x: cx, y: cy)
                context.cgContext.rotate(by: annotation.rotation)
                context.cgContext.translateBy(x: -cx, y: -cy)
            }
            cached.draw(in: unrotatedBBox, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.cgContext.restoreGState()
            return
        }

        let scale: CGFloat = window?.backingScaleFactor ?? 2.0
        let pxW = Int(ceil(unrotatedBBox.width * scale))
        let pxH = Int(ceil(unrotatedBBox.height * scale))
        guard pxW > 0, pxH > 0, pxW < 8000, pxH < 8000 else { return }

        // Render the annotation at rotation=0 into an offscreen bitmap.
        // We temporarily zero out rotation so the glow is cached unrotated.
        let savedRotation = annotation.rotation
        annotation.rotation = 0
        let offscreen = NSImage(size: NSSize(width: unrotatedBBox.width * scale, height: unrotatedBBox.height * scale))
        offscreen.lockFocus()
        guard let offNSCtx = NSGraphicsContext.current else {
            annotation.rotation = savedRotation
            offscreen.unlockFocus()
            return
        }
        offNSCtx.cgContext.scaleBy(x: scale, y: scale)
        offNSCtx.cgContext.translateBy(x: -unrotatedBBox.origin.x, y: -unrotatedBBox.origin.y)
        annotation.draw(in: offNSCtx)
        offscreen.unlockFocus()
        annotation.rotation = savedRotation

        guard let cgOrig = offscreen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let ciOrig = CIImage(cgImage: cgOrig)
        guard let dilateFilter = CIFilter(name: "CIMorphologyMaximum") else { return }
        dilateFilter.setValue(ciOrig, forKey: kCIInputImageKey)
        dilateFilter.setValue(outlineWidth * scale, forKey: kCIInputRadiusKey)
        guard let dilated = dilateFilter.outputImage else { return }

        guard let colorFilter = CIFilter(name: "CIFalseColor") else { return }
        let accentCI = CIColor(color: ToolbarLayout.accentColor) ?? CIColor.blue
        colorFilter.setValue(dilated, forKey: kCIInputImageKey)
        colorFilter.setValue(accentCI, forKey: "inputColor0")
        colorFilter.setValue(accentCI, forKey: "inputColor1")
        guard let colored = colorFilter.outputImage else { return }

        guard let subtractFilter = CIFilter(name: "CISourceOutCompositing") else { return }
        subtractFilter.setValue(colored, forKey: kCIInputImageKey)
        subtractFilter.setValue(ciOrig, forKey: kCIInputBackgroundImageKey)
        guard let outline = subtractFilter.outputImage else { return }

        guard let outlineCG = Self.sharedCIContext.createCGImage(outline, from: ciOrig.extent) else { return }

        let outlineImage = NSImage(cgImage: outlineCG, size: unrotatedBBox.size)
        annotation.outlineGlowImage = outlineImage
        annotation.outlineGlowRect = unrotatedBBox

        guard let context = NSGraphicsContext.current else { return }
        context.cgContext.saveGState()
        context.cgContext.setAlpha(0.55)
        if annotation.rotation != 0 && annotation.supportsRotation {
            let cx = unrotatedBBox.midX, cy = unrotatedBBox.midY
            context.cgContext.translateBy(x: cx, y: cy)
            context.cgContext.rotate(by: annotation.rotation)
            context.cgContext.translateBy(x: -cx, y: -cy)
        }
        outlineImage.draw(in: unrotatedBBox, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.cgContext.restoreGState()
    }
}
