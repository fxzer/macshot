//
//  OverlayView+TextEditing.swift
//  macshot
//
//  Text editing helpers and NSTextViewDelegate conformance.
//

import AppKit

extension OverlayView {

    // MARK: - Text Field

    func showTextField(
        at point: NSPoint, existingText: NSAttributedString? = nil, existingFrame: NSRect = .zero
    ) {
        resetLiveTextInteraction()
        textEditor.onToolShortcut = { [weak self] event in
            self?.handleLiveTextToolShortcut(with: event) ?? false
        }
        textEditor.show(
            in: self, at: point, color: currentColor,
            existingText: existingText, existingFrame: existingFrame,
            canvas: self)
        textEditor.textView?.delegate = self
        requestToolbarRebuild(reason: "textEditing")
        needsDisplay = true
    }

    func cancelTextEditing() {
        resetLiveTextInteraction()
        textEditor.cancel(canvas: self)
        window?.makeFirstResponder(self)
        requestToolbarRebuild(reason: "textEditing")
        needsDisplay = true
    }

    func commitTextFieldIfNeeded() {
        guard textEditor.isEditing else { return }
        resetLiveTextInteraction()
        textEditor.commit(canvas: self)
        window?.makeFirstResponder(self)
        requestToolbarRebuild(reason: "textEditing")
        needsDisplay = true
    }
}

extension OverlayView: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            textEditor.lockWidth()
            textView.insertNewlineIgnoringFieldEditor(self)
            textDidChange(Notification(name: NSText.didChangeNotification))
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTextEditing()
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        textEditor.resizeToFit()
        needsDisplay = true
    }
}
