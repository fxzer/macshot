import Cocoa

/// Handles the unified censor tool (pixelate, blur, solid).
/// Mode is read via `canvas.currentCensorMode`. Shift-constrains to square.
/// Captures composited image source for pixelate/blur baking.
final class PixelateToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .pixelate

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let mode = canvas.currentCensorMode
        let annotation = Annotation(
            tool: .pixelate,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .pixelate),
            strokeWidth: canvas.initialStrokeWidth(for: .pixelate)
        )
        annotation.censorMode = mode
        // All censor modes (including solid and erase) need sourceImage to sample background color
        annotation.sourceImage = canvas.compositedImage() ?? canvas.screenshotImage
        annotation.sourceImageBounds = canvas.captureDrawRect
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        var clampedPoint = point

        if shiftHeld {
            clampedPoint = snapSquare(point, from: annotation.startPoint)
            canvas.snapGuideX = nil
            canvas.snapGuideY = nil
        } else {
            clampedPoint = canvas.snapPoint(point, excluding: annotation)
        }

        annotation.endPoint = clampedPoint
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        let dx = abs(annotation.endPoint.x - annotation.startPoint.x)
        let dy = abs(annotation.endPoint.y - annotation.startPoint.y)
        guard dx > 2 || dy > 2 else {
            canvas.activeAnnotation = nil
            canvas.setNeedsDisplay()
            return
        }

        commitAnnotation(annotation, canvas: canvas)
    }
}
