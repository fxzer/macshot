import Foundation

enum AppVisibilityPreferences {
    static let showDockIconKey = "showDockIcon"
    static let defaultShowDockIcon = true

    private static let defaults = UserDefaults.standard

    static var shouldShowDockIcon: Bool {
        defaults.object(forKey: showDockIconKey) as? Bool ?? defaultShowDockIcon
    }
}
