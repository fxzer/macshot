import Foundation

// MARK: - Aspect Ratio Model
struct CustomAspectRatio: Codable, Equatable, Identifiable {
    let id: UUID
    let width: Int
    let height: Int
    let isEnabled: Bool  // Soft delete flag

    var ratio: CGFloat {
        guard height > 0 else { return 0 }
        return CGFloat(width) / CGFloat(height)
    }

    var displayName: String {
        "\(width):\(height)"
    }

    var isValid: Bool {
        width > 0 && height > 0 && width <= 100 && height <= 100
    }

    init(width: Int, height: Int, isEnabled: Bool = true) {
        self.id = UUID()
        self.width = width
        self.height = height
        self.isEnabled = isEnabled
    }
}

// MARK: - Default Aspect Ratios
extension CustomAspectRatio {
    /// Simplified default ratios - only 3 base ratios, others can be obtained by pressing R to invert
    static let defaultRatios: [CustomAspectRatio] = [
        CustomAspectRatio(width: 1, height: 1),        // 1:1 (square)
        CustomAspectRatio(width: 3, height: 4),        // 3:4 (portrait, invert to 4:3)
        CustomAspectRatio(width: 9, height: 16),       // 9:16 (portrait, invert to 16:9)
    ]

    /// Get the inverted ratio (swap width and height)
    var inverted: CustomAspectRatio {
        CustomAspectRatio(width: height, height: width)
    }
}

// MARK: - Preferences Manager
enum AspectRatioPreferences {
    private static let defaults = UserDefaults.standard
    private static let customRatiosKey = "customAspectRatios"
    private static let migrationVersionKey = "aspectRatioMigrationVersion"

    /// Get all stored aspect ratios (including disabled ones)
    private static var allStoredRatios: [CustomAspectRatio] {
        get {
            guard let data = defaults.data(forKey: customRatiosKey),
                  let ratios = try? JSONDecoder().decode([CustomAspectRatio].self, from: data) else {
                return CustomAspectRatio.defaultRatios
            }
            return ratios
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: customRatiosKey)
                NotificationCenter.default.post(name: .aspectRatiosDidChange, object: nil)
            }
        }
    }

    /// Get all enabled aspect ratios
    static var allRatios: [CustomAspectRatio] {
        return allStoredRatios.filter { $0.isEnabled }
    }

    /// Add a new aspect ratio
    /// - Returns: (success: Bool, errorMessage: String?)
    static func addRatio(width: Int, height: Int) -> (Bool, String?) {
        let newRatio = CustomAspectRatio(width: width, height: height)
        guard newRatio.isValid else {
            return (false, L("Invalid ratio. Width and height must be between 1 and 100."))
        }

        var ratios = allStoredRatios

        // Check if exact ratio already exists
        if ratios.contains(where: { $0.width == width && $0.height == height && $0.isEnabled }) {
            return (false, L("This ratio already exists."))
        }

        // Check if inverted ratio already exists
        let invertedWidth = height
        let invertedHeight = width
        if let existingRatio = ratios.first(where: { $0.width == invertedWidth && $0.height == invertedHeight && $0.isEnabled }) {
            return (false, String(format: L("Ratio %@ already exists. Press R to invert it to %@."), existingRatio.displayName, "\(width):\(height)"))
        }

        ratios.append(newRatio)
        allStoredRatios = ratios
        return (true, nil)
    }

    /// Remove an aspect ratio (soft delete by setting isEnabled to false)
    static func removeRatio(id: UUID) {
        var ratios = allStoredRatios
        guard ratios.count > 1 else { return } // Keep at least one

        if let index = ratios.firstIndex(where: { $0.id == id }) {
            ratios[index] = CustomAspectRatio(width: ratios[index].width, height: ratios[index].height, isEnabled: false)
            allStoredRatios = ratios
        }
    }

    /// Reorder aspect ratios (only enabled ones)
    static func reorderRatios(_ ratios: [CustomAspectRatio]) {
        // Merge with disabled ones
        let disabledRatios = allStoredRatios.filter { !$0.isEnabled }
        let mergedRatios = ratios + disabledRatios
        allStoredRatios = mergedRatios
    }

    /// Reset to default ratios
    static func resetToDefaults() {
        allStoredRatios = CustomAspectRatio.defaultRatios
    }

    /// Migrate from old hardcoded system to new custom system
    static func migrateIfNeeded() {
        let currentVersion = defaults.integer(forKey: migrationVersionKey)
        guard currentVersion < 1 else { return }

        // First time: save default ratios
        if defaults.object(forKey: customRatiosKey) == nil {
            allStoredRatios = CustomAspectRatio.defaultRatios
        }

        defaults.set(1, forKey: migrationVersionKey)
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let aspectRatiosDidChange = Notification.Name("aspectRatiosDidChange")
    static let aspectRatioShortcutsDidChange = Notification.Name("aspectRatioShortcutsDidChange")
}
