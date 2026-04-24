import Cocoa
import SwiftUI
import Combine
import Carbon

// MARK: - Conflict Alert Helper

private enum ShortcutConflictAlert {
    static func confirmReplacement(title: String, shortcut: String, existingAction: String, newAction: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = String.localizedStringWithFormat(
            L("Shortcut conflict message"),
            shortcut,
            existingAction,
            newAction
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Replace"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }
}

/// Manages aspect ratio lock shortcuts (similar to ToolShortcutManager)
enum AspectRatioShortcutManager {
    private static let defaultsKey = "aspectRatioShortcuts"
    private static let defaultKeys = ["1", "3", "9"]
    private static let cancelKey = "0"
    private static let invertKey = "r"

    /// Get the shortcut key for a specific ratio ID. Empty string = disabled.
    static func key(for ratioID: UUID) -> String {
        let idString = ratioID.uuidString
        if let key = sanitizedMappings()[idString] {
            return key
        }

        // Try to return default shortcut
        let ratios = AspectRatioPreferences.allRatios
        if let index = ratios.firstIndex(where: { $0.id == ratioID }),
           index < defaultKeys.count {
            return defaultKeys[index]
        }
        return ""
    }

    /// Set the shortcut key for a ratio ID. Pass empty string to disable.
    static func setKey(_ key: String, for ratioID: UUID) {
        var dict = sanitizedMappings()
        dict[ratioID.uuidString] = key.lowercased()
        UserDefaults.standard.set(dict, forKey: defaultsKey)
        NotificationCenter.default.post(name: .aspectRatioShortcutsDidChange, object: nil)
    }

    /// Find another ratio already using the same key, excluding the provided ratio.
    static func conflictingRatio(for key: String, excluding excludedID: UUID?) -> CustomAspectRatio? {
        let normalizedKey = key.lowercased()
        guard !normalizedKey.isEmpty else { return nil }

        for ratio in AspectRatioPreferences.allRatios {
            if ratio.id != excludedID && self.key(for: ratio.id).lowercased() == normalizedKey {
                return ratio
            }
        }
        return nil
    }

    /// Look up a ratio by shortcut key. Returns nil for cancel/invert keys or not found.
    static func lookupRatio(for key: String) -> CustomAspectRatio? {
        let normalizedKey = key.lowercased()

        // Check special shortcuts
        if normalizedKey == cancelKey || normalizedKey == invertKey {
            return nil
        }

        // Find ratio
        for ratio in AspectRatioPreferences.allRatios {
            if self.key(for: ratio.id).lowercased() == normalizedKey {
                return ratio
            }
        }
        return nil
    }

    /// Display string for UI
    static func displayString(for ratioID: UUID) -> String {
        let k = key(for: ratioID)
        return k.isEmpty ? L("None") : k.uppercased()
    }

    /// Get default shortcut key for a ratio
    static func defaultKey(for ratioID: UUID) -> String {
        let ratios = AspectRatioPreferences.allRatios
        if let index = ratios.firstIndex(where: { $0.id == ratioID }),
           index < defaultKeys.count {
            return defaultKeys[index]
        }
        return ""
    }

    /// Check if a key is a special system key (cancel or invert)
    static func isSpecialKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased()
        return normalizedKey == cancelKey || normalizedKey == invertKey
    }

    /// User-facing message for reserved keys used by the aspect ratio system.
    static func reservedKeyMessage(for key: String) -> String? {
        let normalizedKey = key.lowercased()
        switch normalizedKey {
        case cancelKey:
            return String(format: L("Shortcut %@ is reserved for clearing the aspect ratio lock."), normalizedKey.uppercased())
        case invertKey:
            return String(format: L("Shortcut %@ is reserved for inverting the aspect ratio."), normalizedKey.uppercased())
        default:
            return nil
        }
    }

    /// Get the cancel key
    static var cancelKeyValue: String { cancelKey }

    /// Get the invert key
    static var invertKeyValue: String { invertKey }

    private static func sanitizedMappings() -> [String: String] {
        let storedMappings = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        let filteredMappings = storedMappings.filter { _, key in
            !isSpecialKey(key)
        }

        if filteredMappings.count != storedMappings.count {
            UserDefaults.standard.set(filteredMappings, forKey: defaultsKey)
            NotificationCenter.default.post(name: .aspectRatioShortcutsDidChange, object: nil)
        }

        return filteredMappings
    }
}

// MARK: - Recording Model for UI

/// Observable model for recording aspect ratio shortcuts in UI
class AspectRatioShortcutRecordingModel: ObservableObject {
    @Published var recordingRatioID: UUID?
    @Published var displayStrings: [UUID: String] = [:]

    private var localMonitor: Any?
    private var mouseMonitor: Any?
    private var mouseDownPosition: NSPoint?

    init() {
        refreshAll()
    }

    func refreshAll() {
        displayStrings = Dictionary(
            uniqueKeysWithValues: AspectRatioPreferences.allRatios.map { ratio in
                (ratio.id, AspectRatioShortcutManager.displayString(for: ratio.id))
            }
        )
    }

    func startRecording(ratioID: UUID) {
        stopRecording()
        recordingRatioID = ratioID

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if event.keyCode == 53 { // Escape
                self.stopRecording()
                return nil
            }

            if event.keyCode == 51 || event.keyCode == 117 { // Delete/Backspace
                self.clearShortcut(ratioID: ratioID)
                return nil
            }

            guard !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control),
                  let char = event.charactersIgnoringModifiers?.lowercased(),
                  char.count == 1 else { return nil }

            self.assignShortcut(ratioID: ratioID, key: char)
            return nil
        }

        // Track mouse down position to detect drags vs clicks
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .leftMouseDown {
                // Record mouse down position
                self.mouseDownPosition = event.locationInWindow
                return event
            }

            if event.type == .leftMouseUp {
                // Check if this was a click (not a drag) and if click is outside recording fields
                guard let downPos = self.mouseDownPosition,
                      let window = event.window,
                      let contentView = window.contentView else {
                    self.mouseDownPosition = nil
                    return event
                }

                let upPos = event.locationInWindow
                let distance = sqrt(pow(downPos.x - upPos.x, 2) + pow(downPos.y - upPos.y, 2))

                // Only treat as click if mouse didn't move much (not a drag)
                if distance < 5 {
                    if let hitView = contentView.hitTest(upPos) {
                        // Walk up the view hierarchy to check if this click is on a button
                        var view: NSView? = hitView
                        var isInteractiveControl = false

                        while view != nil && view != contentView {
                            let viewName = String(describing: type(of: view))

                            // Check for various SwiftUI/AppKit control types
                            if viewName.contains("Button") ||
                               viewName.contains("NSButton") ||
                               viewName.contains("PopUpButton") ||
                               viewName.contains("Slider") ||
                               viewName.contains("TextField") ||
                               viewName.contains("Segment") ||
                               viewName.contains("Control") {
                                isInteractiveControl = true
                                break
                            }

                            view = view?.superview
                        }

                        // Only cancel if clicking on non-interactive areas
                        if !isInteractiveControl {
                            self.stopRecording()
                        }
                    }
                }

                self.mouseDownPosition = nil
                return event
            }

            return event
        }
    }

    func clearShortcut(ratioID: UUID) {
        stopRecording()
        AspectRatioShortcutManager.setKey("", for: ratioID)
        displayStrings[ratioID] = L("None")
    }

    func resetShortcut(ratioID: UUID) {
        stopRecording()
        let defaultKey = AspectRatioShortcutManager.defaultKey(for: ratioID)
        assignShortcut(ratioID: ratioID, key: defaultKey)
    }

    func stopRecording() {
        recordingRatioID = nil
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
    }

    private func assignShortcut(ratioID: UUID, key: String) {
        stopRecording()

        if let reservedMessage = AspectRatioShortcutManager.reservedKeyMessage(for: key) {
            ShortcutConflictAlert.showMessage(
                title: L("Shortcut Unavailable"),
                message: reservedMessage
            )
            return
        }

        if let conflictRatio = AspectRatioShortcutManager.conflictingRatio(for: key, excluding: ratioID) {
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: key.uppercased(),
                existingAction: conflictRatio.displayName,
                newAction: AspectRatioPreferences.allRatios.first(where: { $0.id == ratioID })?.displayName ?? ""
            )
            guard shouldReplace else { return }
            AspectRatioShortcutManager.setKey("", for: conflictRatio.id)
        }

        if let conflictAction = ToolShortcutManager.conflictingAction(for: key) {
            let shouldReplace = ShortcutConflictAlert.confirmReplacement(
                title: L("Shortcut Conflict"),
                shortcut: key.uppercased(),
                existingAction: conflictAction.label,
                newAction: AspectRatioPreferences.allRatios.first(where: { $0.id == ratioID })?.displayName ?? ""
            )
            guard shouldReplace else { return }
            ToolShortcutManager.setKey("", for: conflictAction)
        }

        AspectRatioShortcutManager.setKey(key, for: ratioID)
        refreshAll()
    }
}
