import Cocoa

extension OverlayView {
    func performRedaction(using action: @escaping OverlayRedactionAction, emptyHint: String) {
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
            guard let self else { return }
            if annotations.isEmpty {
                // Zero hits (or OCR/crop failure) — never stay silent on a privacy action.
                self.showOverlayHint(emptyHint)
            } else {
                self.appendAnnotations(annotations)
            }
        }
    }

    func performAutoRedact() {
        performRedaction(using: AutoRedactor.redactPII, emptyHint: L("No sensitive content detected"))
    }

    func performRedactAllText() {
        performRedaction(using: AutoRedactor.redactAllText, emptyHint: L("No text detected"))
    }

    func performRedactFaces() {
        performRedaction(using: AutoRedactor.redactFaces, emptyHint: L("No faces detected"))
    }

    func performRedactPeople() {
        performRedaction(using: AutoRedactor.redactPeople, emptyHint: L("No people detected"))
    }

}
