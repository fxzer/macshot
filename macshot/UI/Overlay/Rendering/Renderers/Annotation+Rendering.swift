import Cocoa

extension Annotation {
    func draw(in context: NSGraphicsContext) {
        NSGraphicsContext.current = context

        // Apply rotation around annotation center
        if rotation != 0 && supportsRotation {
            let center = NSPoint(x: boundingRect.midX, y: boundingRect.midY)
            let xform = NSAffineTransform()
            xform.translateX(by: center.x, yBy: center.y)
            xform.rotate(byRadians: rotation)
            xform.translateX(by: -center.x, yBy: -center.y)
            context.cgContext.saveGState()
            xform.concat()
        }

        switch tool {
        case .pencil:
            drawFreeform(alpha: color.alphaComponent, width: strokeWidth)
        case .line:
            drawStraightLine()
        case .arrow:
            drawArrow()
        case .rectangle:
            drawRectangle()
        case .filledRectangle:
            drawRectangle(forceFilled: true)
        case .ellipse:
            drawEllipse()
        case .marker:
            drawFreeform(alpha: 0.35, width: strokeWidth)
        case .text:
            drawText()
        case .number:
            drawNumber()
        case .pixelate:
            drawCensor(in: context)
        case .blur:
            // Legacy: existing blur annotations from before the merge
            censorMode = .blur
            drawCensor(in: context)
        case .measure:
            drawMeasure()
        case .loupe:
            drawLoupe(in: context)
        case .select:
            break  // not a drawable tool
        case .crop:
            break  // handled separately in OverlayView
        case .translateOverlay:
            drawTranslateOverlay()
        case .colorSampler:
            break  // preview-only tool, no annotation drawn
        case .stamp:
            drawStamp()
        }

        if rotation != 0 && supportsRotation {
            context.cgContext.restoreGState()
        }
    }
}
