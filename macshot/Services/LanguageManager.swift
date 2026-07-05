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

    /// Process-wide cache of resolved localized strings keyed by source key.
    /// `Bundle.localizedString` does real work (hashing + table lookup + fallback)
    /// on every call; menu rebuilds and per-frame hint text call `L(...)` many
    /// times. The cache turns hot lookups into a dictionary hit. Invalidated
    /// on language change. Reads happen on the main thread; the lock is a
    /// safety net for any off-main caller.
    private var stringCache = [String: String]()
    private let cacheLock = NSLock()

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
        cacheLock.lock()
        if let cached = stringCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)

        cacheLock.lock()
        // Bundle returns the key itself when no translation exists; caching that
        // is fine (same value would come back every time).
        if stringCache[key] == nil {
            stringCache[key] = value
        }
        cacheLock.unlock()
        return value
    }

    private func reload() {
        let lang = resolvedLanguage
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
        // Language changed — every cached string is now stale.
        cacheLock.lock()
        stringCache.removeAll()
        cacheLock.unlock()
    }
}

/// Shorthand for localized string lookup.
func L(_ key: String) -> String {
    LanguageManager.shared.localizedString(key)
}
