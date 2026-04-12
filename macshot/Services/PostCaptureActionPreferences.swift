import Foundation

struct ScreenshotPostActions {
    var showQuickAccessOverlay: Bool
    var copyToClipboard: Bool
    var saveToFile: Bool
    var uploadAndCopyLink: Bool
    var openEditor: Bool
    var pinToScreen: Bool
}

struct RecordingPostActions {
    var showQuickAccessOverlay: Bool
    var copyToClipboard: Bool
    var saveToFile: Bool
    var uploadAndCopyLink: Bool
    var openVideoEditor: Bool
}

enum PostCaptureActionPreferences {
    private static let defaults = UserDefaults.standard
    private static let migrationVersionKey = "postCaptureActionsMigrationVersion"
    private static let migrationVersion = 1

    enum Keys {
        static let screenshotShowQuickAccessOverlay = "showFloatingThumbnail"
        static let screenshotCopyToClipboard = "postActionScreenshotCopyToClipboard"
        static let screenshotSaveToFile = "postActionScreenshotSaveToFile"
        static let screenshotUploadAndCopyLink = "postActionScreenshotUploadAndCopyLink"
        static let screenshotOpenEditor = "postActionScreenshotOpenEditor"
        static let screenshotPinToScreen = "postActionScreenshotPinToScreen"

        static let recordingShowQuickAccessOverlay = "postActionRecordingShowQuickAccessOverlay"
        static let recordingCopyToClipboard = "postActionRecordingCopyToClipboard"
        static let recordingSaveToFile = "postActionRecordingSaveToFile"
        static let recordingUploadAndCopyLink = "postActionRecordingUploadAndCopyLink"
        static let recordingOpenVideoEditor = "postActionRecordingOpenVideoEditor"
    }

    static func migrateIfNeeded() {
        let appliedVersion = defaults.integer(forKey: migrationVersionKey)
        guard appliedVersion < migrationVersion else { return }

        let quickCaptureMode = defaults.object(forKey: "quickCaptureMode") as? Int ?? 1
        let quickCaptureOpenEditor = defaults.bool(forKey: "quickCaptureOpenEditor")
        let recordingOnStop = defaults.string(forKey: "recordingOnStop") ?? "editor"

        setDefaultIfMissing(Keys.screenshotCopyToClipboard, value: quickCaptureMode == 1 || quickCaptureMode == 2)
        setDefaultIfMissing(Keys.screenshotSaveToFile, value: quickCaptureMode == 0 || quickCaptureMode == 2)
        setDefaultIfMissing(Keys.screenshotUploadAndCopyLink, value: false)
        setDefaultIfMissing(Keys.screenshotOpenEditor, value: quickCaptureOpenEditor)
        setDefaultIfMissing(Keys.screenshotPinToScreen, value: false)

        setDefaultIfMissing(Keys.recordingShowQuickAccessOverlay, value: false)
        setDefaultIfMissing(Keys.recordingCopyToClipboard, value: recordingOnStop == "clipboard")
        setDefaultIfMissing(Keys.recordingSaveToFile, value: recordingOnStop == "finder")
        setDefaultIfMissing(Keys.recordingUploadAndCopyLink, value: false)
        setDefaultIfMissing(Keys.recordingOpenVideoEditor, value: recordingOnStop == "editor")

        defaults.set(migrationVersion, forKey: migrationVersionKey)
    }

    static var screenshotActions: ScreenshotPostActions {
        migrateIfNeeded()
        return ScreenshotPostActions(
            showQuickAccessOverlay: bool(forKey: Keys.screenshotShowQuickAccessOverlay, default: true),
            copyToClipboard: bool(forKey: Keys.screenshotCopyToClipboard, default: true),
            saveToFile: bool(forKey: Keys.screenshotSaveToFile, default: false),
            uploadAndCopyLink: bool(forKey: Keys.screenshotUploadAndCopyLink, default: false),
            openEditor: bool(forKey: Keys.screenshotOpenEditor, default: false),
            pinToScreen: bool(forKey: Keys.screenshotPinToScreen, default: false)
        )
    }

    static var recordingActions: RecordingPostActions {
        migrateIfNeeded()
        return RecordingPostActions(
            showQuickAccessOverlay: bool(forKey: Keys.recordingShowQuickAccessOverlay, default: false),
            copyToClipboard: bool(forKey: Keys.recordingCopyToClipboard, default: false),
            saveToFile: bool(forKey: Keys.recordingSaveToFile, default: false),
            uploadAndCopyLink: bool(forKey: Keys.recordingUploadAndCopyLink, default: false),
            openVideoEditor: bool(forKey: Keys.recordingOpenVideoEditor, default: true)
        )
    }

    private static func setDefaultIfMissing(_ key: String, value: Bool) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(value, forKey: key)
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
