import Cocoa

extension OverlayView {
    func performRedaction(using action: @escaping OverlayRedactionAction) {
        guard let context = currentRedactionContext else { return }
        action(
            context.screenshot,
            context.selectionRect,
            context.captureDrawRect,
            context.redactTool,
            context.color,
            context.sourceImage,
            context.captureDrawRect
        ) { [weak self] annotations in
            self?.appendAnnotations(annotations)
        }
    }

    func performAutoRedact() {
        performRedaction(using: AutoRedactor.redactPII)
    }

    func performRedactAllText() {
        performRedaction(using: AutoRedactor.redactAllText)
    }

    func performRedactFaces() {
        performRedaction(using: AutoRedactor.redactFaces)
    }

    func performRedactPeople() {
        performRedaction(using: AutoRedactor.redactPeople)
    }

}
