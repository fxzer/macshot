import AppKit

enum PasteboardWriter {
    static func writeString(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    /// Simulates Cmd+V keystroke to paste clipboard content into the frontmost application.
    /// Requires Accessibility permission.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 55 // kVK_Command
        let vKey: CGKeyCode = 9    // kVK_ANSI_V

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false) else {
            return
        }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
    }
}
