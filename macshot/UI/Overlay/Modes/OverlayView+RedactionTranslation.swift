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

    func performTranslate(targetLang: String) {
        guard state == .selected, let screenshotImage else { return }
        annotations.removeAll { $0.tool == .translateOverlay }
        isTranslating = true
        needsDisplay = true

        TranslateOverlay.translate(
            screenshot: screenshotImage,
            selectionRect: selectionRect,
            captureDrawRect: captureDrawRect,
            targetLang: targetLang,
            onError: { [weak self] message in
                self?.isTranslating = false
                self?.showOverlayError(message)
                self?.needsDisplay = true
            },
            completion: { [weak self] annotations in
                self?.isTranslating = false
                self?.replaceAnnotations(of: .translateOverlay, with: annotations)
            }
        )
    }
}
