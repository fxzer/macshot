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

    init(id: UUID = UUID(), width: Int, height: Int, isEnabled: Bool = true) {
        self.id = id
        self.width = width
        self.height = height
        self.isEnabled = isEnabled
    }
}

// MARK: - Default Aspect Ratios
extension CustomAspectRatio {
    private static let oneToOneID = UUID(uuidString: "F0B5C59D-4B76-4F85-8F05-96F2C16D8B01")!
    private static let threeToFourID = UUID(uuidString: "A6D83462-5D22-4F4C-8E0D-7436555B63F2")!
    private static let nineToSixteenID = UUID(uuidString: "D3A587A9-9F81-4B10-8F7F-2E9E2B8D0C63")!

    /// Simplified default ratios - only 3 base ratios, others can be obtained by pressing R to invert
    static let defaultRatios: [CustomAspectRatio] = [
        CustomAspectRatio(id: oneToOneID, width: 1, height: 1),        // 1:1 (square)
        CustomAspectRatio(id: threeToFourID, width: 3, height: 4),     // 3:4 (portrait, invert to 4:3)
        CustomAspectRatio(id: nineToSixteenID, width: 9, height: 16),  // 9:16 (portrait, invert to 16:9)
    ]

    /// Get the inverted ratio (swap width and height)
    var inverted: CustomAspectRatio {
        CustomAspectRatio(width: height, height: width)
    }

    var exactKey: String {
        "\(width):\(height)"
    }
}

// MARK: - Preferences Manager
enum AspectRatioPreferences {
    private static let defaults = UserDefaults.standard
    private static let customRatiosKey = "customAspectRatios"
    private static let shortcutsKey = "aspectRatioShortcuts"
    private static let migrationVersionKey = "aspectRatioMigrationVersion"
    private static let currentMigrationVersion = 2

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
                pruneShortcutMappings(validRatios: newValue.filter(\.isEnabled))
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
        if let error = validationError(width: width, height: height) {
            return (false, error)
        }

        let newRatio = CustomAspectRatio(width: width, height: height)
        var ratios = allStoredRatios
        ratios.append(newRatio)
        allStoredRatios = ratios
        return (true, nil)
    }

    /// Remove an aspect ratio (soft delete by setting isEnabled to false)
    static func removeRatio(id: UUID) -> (Bool, String?) {
        var ratios = allStoredRatios
        guard ratios.filter(\.isEnabled).count > 1 else {
            return (false, L("At least one aspect ratio must remain."))
        }

        if let index = ratios.firstIndex(where: { $0.id == id }) {
            ratios[index] = CustomAspectRatio(
                id: ratios[index].id,
                width: ratios[index].width,
                height: ratios[index].height,
                isEnabled: false
            )
            allStoredRatios = ratios
            return (true, nil)
        }

        return (false, nil)
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
        guard currentVersion < currentMigrationVersion else { return }

        if currentVersion < 1, defaults.object(forKey: customRatiosKey) == nil {
            allStoredRatios = CustomAspectRatio.defaultRatios
        }

        if currentVersion < 2 {
            migrateLegacyStoredRatios()
        }

        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    static func validationError(width: Int, height: Int) -> String? {
        let newRatio = CustomAspectRatio(width: width, height: height)
        guard newRatio.isValid else {
            return L("Invalid ratio. Width and height must be between 1 and 100.")
        }

        let (normalizedWidth, normalizedHeight) = normalizedDimensions(width: width, height: height)
        let enabledRatios = allStoredRatios.filter(\.isEnabled)

        if let existingRatio = enabledRatios.first(where: {
            let normalizedExisting = normalizedDimensions(width: $0.width, height: $0.height)
            return normalizedExisting.width == normalizedWidth && normalizedExisting.height == normalizedHeight
        }) {
            return String(format: L("Ratio %@ already exists."), existingRatio.displayName)
        }

        if let existingRatio = enabledRatios.first(where: {
            let normalizedExisting = normalizedDimensions(width: $0.width, height: $0.height)
            return normalizedExisting.width == normalizedHeight && normalizedExisting.height == normalizedWidth
        }) {
            return String(
                format: L("Ratio %@ already exists. Press R to invert it to %@."),
                existingRatio.displayName,
                "\(width):\(height)"
            )
        }

        return nil
    }

    private static func migrateLegacyStoredRatios() {
        let storedRatios = allStoredRatios
        let enabledRatios = storedRatios.filter(\.isEnabled)
        guard !enabledRatios.isEmpty else {
            allStoredRatios = CustomAspectRatio.defaultRatios
            return
        }

        let storedShortcuts = (defaults.dictionary(forKey: shortcutsKey) as? [String: String]) ?? [:]
        let migration = canonicalizeEnabledRatios(enabledRatios)

        if let data = try? JSONEncoder().encode(migration.ratios) {
            defaults.set(data, forKey: customRatiosKey)
        }

        remapShortcutMappings(storedShortcuts, using: migration.idMapping, validRatios: migration.ratios)
        NotificationCenter.default.post(name: .aspectRatiosDidChange, object: nil)
        NotificationCenter.default.post(name: .aspectRatioShortcutsDidChange, object: nil)
    }

    private static func pruneShortcutMappings(validRatios: [CustomAspectRatio]) {
        guard let storedMappings = defaults.dictionary(forKey: shortcutsKey) as? [String: String] else {
            return
        }

        let validIDs = Set(validRatios.map { $0.id.uuidString })
        let filteredMappings = storedMappings.filter { validIDs.contains($0.key) }

        guard filteredMappings.count != storedMappings.count else { return }

        defaults.set(filteredMappings, forKey: shortcutsKey)
        NotificationCenter.default.post(name: .aspectRatioShortcutsDidChange, object: nil)
    }

    private static func canonicalizeEnabledRatios(_ ratios: [CustomAspectRatio]) -> (ratios: [CustomAspectRatio], idMapping: [UUID: UUID]) {
        if ratios.count > CustomAspectRatio.defaultRatios.count
            && ratios.allSatisfy({ legacyPresetExactKeys.contains($0.exactKey) })
        {
            let keptRatios = CustomAspectRatio.defaultRatios
            let idMapping = Dictionary(uniqueKeysWithValues: ratios.compactMap { ratio in
                if let canonical = canonicalDefaultRatio(for: ratio) {
                    return (ratio.id, canonical.id)
                }
                return nil
            })
            return (keptRatios, idMapping)
        }

        var keptRatios: [CustomAspectRatio] = []
        var seenPairKeys: [String: UUID] = [:]
        var idMapping: [UUID: UUID] = [:]

        for ratio in ratios {
            let pairKey = normalizedPairKey(width: ratio.width, height: ratio.height)

            if let keptID = seenPairKeys[pairKey] {
                idMapping[ratio.id] = keptID
                continue
            }

            let keptRatio = canonicalDefaultRatio(for: ratio)
                ?? CustomAspectRatio(id: ratio.id, width: ratio.width, height: ratio.height)

            keptRatios.append(keptRatio)
            seenPairKeys[pairKey] = keptRatio.id
            idMapping[ratio.id] = keptRatio.id
        }

        return (keptRatios, idMapping)
    }

    private static func remapShortcutMappings(
        _ storedMappings: [String: String],
        using idMapping: [UUID: UUID],
        validRatios: [CustomAspectRatio]
    ) {
        let validIDs = Set(validRatios.map(\.id.uuidString))
        var remappedMappings: [String: String] = [:]

        for (storedID, key) in storedMappings {
            guard let ratioID = UUID(uuidString: storedID) else { continue }
            let destinationID = idMapping[ratioID] ?? ratioID
            let destinationKey = destinationID.uuidString
            guard validIDs.contains(destinationKey) else { continue }
            guard remappedMappings[destinationKey] == nil else { continue }
            remappedMappings[destinationKey] = key
        }

        defaults.set(remappedMappings, forKey: shortcutsKey)
    }

    private static func normalizedDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width != 0, height != 0 else { return (width, height) }
        let divisor = greatestCommonDivisor(abs(width), abs(height))
        guard divisor > 0 else { return (width, height) }
        return (width / divisor, height / divisor)
    }

    private static func normalizedPairKey(width: Int, height: Int) -> String {
        let normalized = normalizedDimensions(width: width, height: height)
        return "\(min(normalized.width, normalized.height)):\(max(normalized.width, normalized.height))"
    }

    private static func canonicalDefaultRatio(for ratio: CustomAspectRatio) -> CustomAspectRatio? {
        switch normalizedPairKey(width: ratio.width, height: ratio.height) {
        case normalizedPairKey(width: 1, height: 1):
            return CustomAspectRatio.defaultRatios[0]
        case normalizedPairKey(width: 3, height: 4):
            return CustomAspectRatio.defaultRatios[1]
        case normalizedPairKey(width: 9, height: 16):
            return CustomAspectRatio.defaultRatios[2]
        default:
            return nil
        }
    }

    private static let legacyPresetExactKeys: Set<String> = [
        "1:1",
        "2:3",
        "3:2",
        "3:4",
        "4:3",
        "4:5",
        "5:4",
        "5:7",
        "7:5",
        "9:16",
        "16:9",
    ]

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return a
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let aspectRatiosDidChange = Notification.Name("aspectRatiosDidChange")
    static let aspectRatioShortcutsDidChange = Notification.Name("aspectRatioShortcutsDidChange")
}
