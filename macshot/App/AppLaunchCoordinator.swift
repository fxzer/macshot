import Cocoa
import Sparkle

@MainActor
final class AppLaunchCoordinator: NSObject {

    struct Dependencies {
        let setMenuBarIconVisible: (Bool) -> Void
        let statusBarSetup: () -> Void
        let captureAreaFromHotkey: () -> Void
        let captureFullScreenFromHotkey: () -> Void
        let recordAreaFromHotkey: () -> Void
        let recordScreenFromHotkey: () -> Void
        let showHistoryOverlay: () -> Void
        let captureOCRFromHotkey: () -> Void
        let quickCaptureFromHotkey: () -> Void
        let scrollCaptureFromHotkey: () -> Void
        let openImageFromClipboard: () -> Void
        let openSettings: () -> Void
        let hasActiveOverlaySession: () -> Bool
        let dismissOverlays: () -> Void
        let pinHistoryImage: (NSImage) -> Void
        let handleLanguageChange: () -> Void
        let defaultInteractionScreen: () -> NSScreen?
    }

    private let dependencies: Dependencies
    private var updaterController: SPUStandardUpdaterController?
    private var onboardingController: PermissionOnboardingController?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        super.init()
    }

    func applicationDidFinishLaunching(updaterDelegate: SPUUpdaterDelegate) -> Bool {
        ProcessInfo.processInfo.disableAutomaticTermination("macshot is a menu bar agent")

        let bundleID = Bundle.main.bundleIdentifier ?? "com.fxzer.macshot.macshot"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if runningApps.count > 1 {
            DistributedNotificationCenter.default().postNotificationName(
                .init("com.fxzer.macshot.showAndOpenPrefs"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            NSApp.terminate(nil)
            return false
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        PostCaptureActionPreferences.migrateIfNeeded()
        AspectRatioPreferences.migrateIfNeeded()

        setupMainMenu()
        dependencies.statusBarSetup()
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            dependencies.setMenuBarIconVisible(false)
        }
        registerHotkey()

        DispatchQueue.main.async {
            ToolbarButtonView.preloadCommonIcons()
        }

        if let sound = AppDelegate.captureSound {
            sound.volume = 0
            sound.play()
            sound.stop()
            sound.volume = 1
        }

        registerObservers()
        checkScreenRecordingPermission()
        return true
    }

    func applicationShouldHandleReopen(hasVisibleWindows: Bool) -> Bool {
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            dependencies.setMenuBarIconVisible(true)
        }
        if !hasVisibleWindows {
            dependencies.openSettings()
        }
        return false
    }

    func applicationWillTerminate() {
        HotkeyManager.shared.unregister()
        removeObservers()
    }

    func registerHotkey() {
        HotkeyManager.shared.registerAll(
            captureArea: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.captureAreaFromHotkey() }
            },
            captureFullScreen: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.captureFullScreenFromHotkey() }
            },
            recordArea: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.recordAreaFromHotkey() }
            },
            recordScreen: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.recordScreenFromHotkey() }
            },
            historyOverlay: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.showHistoryOverlay() }
            },
            captureOCR: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.captureOCRFromHotkey() }
            },
            quickCapture: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.quickCaptureFromHotkey() }
            },
            scrollCapture: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.scrollCaptureFromHotkey() }
            },
            openFromClipboard: { [weak self] in
                DispatchQueue.main.async { self?.dependencies.openImageFromClipboard() }
            }
        )
    }

    func showOnboarding(on preferredScreen: NSScreen? = nil) {
        if let existing = onboardingController {
            existing.show(on: preferredScreen)
            return
        }

        let controller = PermissionOnboardingController()
        controller.onPermissionGranted = { [weak self] in
            self?.onboardingController = nil
        }
        onboardingController = controller
        controller.show(on: preferredScreen)
    }

    func updateLocalization() {
        onboardingController?.updateLocalization()
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController?.checkForUpdates(nil)
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L("About MacShot"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: L("Quit MacShot"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    private func registerObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowAndOpenPrefs),
            name: .init("com.fxzer.macshot.showAndOpenPrefs"),
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pinFromHistory(_:)),
            name: .init("macshot.pinFromHistory"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: LanguageManager.changedNotification,
            object: nil
        )
    }

    private func removeObservers() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func checkScreenRecordingPermission() {
        PermissionOnboardingController.checkPermissionSync { [weak self] granted in
            guard let self, !granted else { return }
            self.showOnboarding(on: self.dependencies.defaultInteractionScreen())
        }
    }

    @objc private func handleShowAndOpenPrefs() {
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            dependencies.setMenuBarIconVisible(true)
        }
        dependencies.openSettings()
    }

    @objc private func handleSpaceDidChange() {
        guard dependencies.hasActiveOverlaySession() else { return }
        dependencies.dismissOverlays()
    }

    @objc private func pinFromHistory(_ notification: Notification) {
        guard let image = notification.object as? NSImage else { return }
        dependencies.pinHistoryImage(image)
    }

    @objc private func languageDidChange(_ notification: Notification) {
        dependencies.handleLanguageChange()
    }
}
