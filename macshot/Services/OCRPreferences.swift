import Foundation

enum OCRPreferences {
    private static let defaults = UserDefaults.standard

    static var shouldShowWindow: Bool {
        defaults.object(forKey: "ocrShowWindow") as? Bool ?? true
    }

    static var shouldCopyToClipboard: Bool {
        defaults.object(forKey: "ocrCopyToClipboard") as? Bool ?? true
    }
}
