import AppKit
import ApplicationServices

enum SystemPermissionPrompter {
    static func requestAccessibilityPermission(message: String) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        showAlert(
            title: L("Accessibility Access Required"),
            message: message,
            settingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    private static func showAlert(title: String, message: String, settingsURLString: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Open Settings"))
        alert.addButton(withTitle: L("Cancel"))

        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: settingsURLString) {
            NSWorkspace.shared.open(url)
        }
    }
}
