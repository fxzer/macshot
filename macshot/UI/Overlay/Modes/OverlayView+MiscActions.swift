import AppKit

extension OverlayView {
    override func otherMouseDown(with event: NSEvent) {
    }

    func applyColorToTextIfEditing() {
        if textEditor.isEditing {
            textEditor.applyColorToLiveText(color: annotationColor)
        }
    }
}
