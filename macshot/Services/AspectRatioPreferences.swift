import Foundation

// MARK: - Aspect Ratio Model
struct CustomAspectRatio: Codable, Equatable, Identifiable {
    let id: UUID
    let width: Double
    let height: Double
    let isEnabled: Bool  // Soft delete flag

    var ratio: CGFloat {
        guard height > 0 else { return 0 }
        return CGFloat(width) / CGFloat(height)
    }

    var displayName: String {
        "\(Self.formatComponent(width)):\(Self.formatComponent(height))"
    }

    var isValid: Bool {
        Self.isSupportedComponent(width) && Self.isSupportedComponent(height)
    }

    var isSquare: Bool {
        guard let normalizedPairKey else { return false }
        return normalizedPairKey == Self.normalizedPairKey(width: 1, height: 1)
    }

    var normalizedExactKey: String? {
        Self.normalizedExactKey(width: width, height: height)
    }

    var normalizedPairKey: String? {
        Self.normalizedPairKey(width: width, height: height)
    }

    func isExactlyEquivalent(toWidth width: Double, height: Double) -> Bool {
        normalizedExactKey == Self.normalizedExactKey(width: width, height: height)
    }

    init(id: UUID = UUID(), width: Double, height: Double, isEnabled: Bool = true) {
        self.id = id
        self.width = width
        self.height = height
        self.isEnabled = isEnabled
    }
}

// MARK: - Default Aspect Ratios
extension CustomAspectRatio {
    static let maxComponentValue: Double = 100
    static let maxFractionDigits = 2

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
        displayName
    }

    static func formatComponent(_ value: Double) -> String {
        displayFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func normalizedPairKey(width: Double, height: Double) -> String? {
        guard let normalized = normalizedComponents(width: width, height: height) else {
            return nil
        }
        return "\(min(normalized.width, normalized.height)):\(max(normalized.width, normalized.height))"
    }

    static func normalizedExactKey(width: Double, height: Double) -> String? {
        guard let normalized = normalizedComponents(width: width, height: height) else {
            return nil
        }
        return "\(normalized.width):\(normalized.height)"
    }

    private static func normalizedComponents(width: Double, height: Double) -> (width: Int, height: Int)? {
        guard let scaledWidth = scaledComponent(width),
              let scaledHeight = scaledComponent(height),
              scaledWidth > 0,
              scaledHeight > 0 else {
            return nil
        }

        let divisor = greatestCommonDivisor(abs(scaledWidth), abs(scaledHeight))
        let normalizedWidth = divisor > 0 ? scaledWidth / divisor : scaledWidth
        let normalizedHeight = divisor > 0 ? scaledHeight / divisor : scaledHeight
        return (normalizedWidth, normalizedHeight)
    }

    private static func isSupportedComponent(_ value: Double) -> Bool {
        guard value > 0, value <= maxComponentValue else { return false }
        let scaled = value * pow(10, Double(maxFractionDigits))
        return abs(scaled - scaled.rounded()) < 0.000_001
    }

    private static func scaledComponent(_ value: Double) -> Int? {
        guard isSupportedComponent(value) else { return nil }
        let scale = pow(10, Double(maxFractionDigits))
        return Int((value * scale).rounded())
    }

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

    private static let displayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumIntegerDigits = 1
        formatter.generatesDecimalNumbers = false
        return formatter
    }()
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
    static func addRatio(width: Double, height: Double) -> (Bool, String?) {
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

    static func validationError(width: Double, height: Double) -> String? {
        let newRatio = CustomAspectRatio(width: width, height: height)
        guard newRatio.isValid else {
            return L("Invalid ratio. Width and height must be between 0.01 and 100, with up to 2 decimal places.")
        }

        let enabledRatios = allStoredRatios.filter(\.isEnabled)
        let normalizedExactKey = newRatio.normalizedExactKey

        if let existingRatio = enabledRatios.first(where: {
            $0.normalizedExactKey == normalizedExactKey
        }) {
            return String(format: L("Ratio %@ already exists."), existingRatio.displayName)
        }

        if let existingRatio = enabledRatios.first(where: {
            $0.normalizedExactKey == CustomAspectRatio.normalizedExactKey(width: height, height: width)
        }) {
            let invertedDisplayName = CustomAspectRatio(width: width, height: height).displayName
            return String(
                format: L("Ratio %@ already exists. Press R to invert it to %@."),
                existingRatio.displayName,
                invertedDisplayName
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
            guard let pairKey = ratio.normalizedPairKey else { continue }

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

    private static func canonicalDefaultRatio(for ratio: CustomAspectRatio) -> CustomAspectRatio? {
        switch ratio.normalizedPairKey {
        case CustomAspectRatio.normalizedPairKey(width: 1, height: 1):
            return CustomAspectRatio.defaultRatios[0]
        case CustomAspectRatio.normalizedPairKey(width: 3, height: 4):
            return CustomAspectRatio.defaultRatios[1]
        case CustomAspectRatio.normalizedPairKey(width: 9, height: 16):
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

}

// MARK: - Notifications
extension Notification.Name {
    static let aspectRatiosDidChange = Notification.Name("aspectRatiosDidChange")
    static let aspectRatioShortcutsDidChange = Notification.Name("aspectRatioShortcutsDidChange")
}
