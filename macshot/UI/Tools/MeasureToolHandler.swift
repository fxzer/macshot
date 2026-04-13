import Cocoa

/// Handles measure (pixel ruler) tool interaction.
/// Draws a measurement line with shift-constrain to 45° angles and snap guides.
final class MeasureToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .measure

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let annotation = Annotation(
            tool: .measure,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .measure),
            strokeWidth: canvas.initialStrokeWidth(for: .measure)
        )
        annotation.measureInPoints = canvas.currentMeasureInPoints
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        var clampedPoint = point

        if shiftHeld {
            clampedPoint = snap45(point, from: annotation.startPoint)
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
