import Foundation

/// Manages the active language for the app.
/// Loads from UserDefaults ("appLanguage"), falls back to system language, then English.
/// Supports runtime switching without app restart by swapping the active bundle.
final class LanguageManager {
    static let shared = LanguageManager()

    static let changedNotification = Notification.Name("LanguageManagerDidChange")

    /// Shipped UI localizations (Settings picker + bundle resolution).
    static let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
    ]

    private static var supportedLanguageCodes: Set<String> {
        Set(availableLanguages.map(\.code))
    }

    private var bundle: Bundle = .main

    private init() {
        reload()
    }

    /// The active language code. "system" means follow macOS preference.
    var currentLanguage: String {
        get { UserDefaults.standard.string(forKey: "appLanguage") ?? "system" }
        set {
            UserDefaults.standard.set(newValue, forKey: "appLanguage")
            reload()
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
    }

    /// Resolves the bundle language code (always `en` or `zh-Hans`).
    var resolvedLanguage: String {
        let lang = currentLanguage
        if lang == "system" {
            return Self.resolvedLanguageMatchingSystemLocale()
        }
        if Self.supportedLanguageCodes.contains(lang) {
            return lang
        }
        return "en"
    }

    private static func resolvedLanguageMatchingSystemLocale() -> String {
        for preferred in Locale.preferredLanguages {
            let normalized = preferred.replacingOccurrences(of: "_", with: "-")
            if supportedLanguageCodes.contains(normalized) { return normalized }
            let parts = normalized.split(separator: "-")
            if parts.count >= 2 {
                let withScript = "\(parts[0])-\(parts[1])"
                if supportedLanguageCodes.contains(withScript) { return withScript }
            }
            let base = String(parts[0])
            if base == "zh" { return "zh-Hans" }
            if base == "en" { return "en" }
        }
        return "en"
    }

    func localizedString(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func reload() {
        let lang = resolvedLanguage
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
    }
}

/// Shorthand for localized string lookup.
func L(_ key: String) -> String {
    LanguageManager.shared.localizedString(key)
}
