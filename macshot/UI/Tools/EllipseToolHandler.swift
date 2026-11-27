import Cocoa

/// Handles ellipse tool interaction.
/// Shift-constrains to circle. Applies fill style and line style.
final class EllipseToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .ellipse

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let paint = canvas.nextPaint(for: .ellipse)
        let annotation = Annotation(
            tool: .ellipse,
            startPoint: point,
            endPoint: point,
            color: paint.color,
            strokeWidth: canvas.initialStrokeWidth(for: .ellipse)
        )
        annotation.strokeGradient = paint.gradient
        annotation.rectFillStyle = canvas.currentRectFillStyle
        annotation.lineStyle = canvas.currentLineStyle
        applyDefaultOutlineIfNeeded(to: annotation, canvas: canvas)
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
