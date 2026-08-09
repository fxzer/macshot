import Cocoa

@MainActor
final class AppLaunchCoordinator: NSObject {

    private static let initialCapturePrewarmDelay: TimeInterval = 1.0
    private static let initialCapturePrewarmRetryDelay: TimeInterval = 1.0
    private static let initialCapturePrewarmMaxAttempts = 3

    struct Dependencies {
        let setMenuBarIconVisible: (Bool) -> Void
        let statusBarSetup: () -> Void
        let captureAreaFromHotkey: () -> Void
        let captureFullScreenFromHotkey: () -> Void
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
        let primeAudio: () -> Void
        let handleOpenURLs: ([URL]) -> Void
    }

    private let dependencies: Dependencies
    private var onboardingController: PermissionOnboardingController?
    private var initialCapturePrewarmWorkItem: DispatchWorkItem?
    private var pendingOpenURLs: [URL] = []
    private var isFinishLaunchingComplete = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        super.init()
    }

    func handleOpen(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if isFinishLaunchingComplete {
            dependencies.handleOpenURLs(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    func applicationDidFinishLaunching() -> Bool {
        ProcessInfo.processInfo.disableAutomaticTermination("macshot is a menu bar agent")

        let bundleID = Bundle.main.bundleIdentifier ?? "com.fxzer.macshot.macshot"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if runningApps.count > 1 {
            // Defer secondary process check slightly so any application(_:open:) AppleEvents are fully delivered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                if !self.pendingOpenURLs.isEmpty {
                    let urlStrings = self.pendingOpenURLs.map { $0.absoluteString }
                    DistributedNotificationCenter.default().postNotificationName(
                        .init("com.fxzer.macshot.openURLs"),
                        object: nil,
                        userInfo: ["urls": urlStrings],
                        deliverImmediately: true
                    )
                } else {
                    DistributedNotificationCenter.default().postNotificationName(
                        .init("com.fxzer.macshot.showAndOpenPrefs"),
                        object: nil,
                        userInfo: nil,
                        deliverImmediately: true
                    )
                }
                NSApp.terminate(nil)
            }
            return false
        }

        TemporaryFileManager.cleanupOnLaunch()
        PostCaptureActionPreferences.migrateIfNeeded()
        AspectRatioPreferences.migrateIfNeeded()

        setupMainMenu()
        dependencies.statusBarSetup()
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            dependencies.setMenuBarIconVisible(false)
        }
        registerHotkey()

        // Prime the audio system to avoid delay on first use — deferred so it
        // doesn't block launch (NSSound init + CoreAudio graph spin-up can take
        // 30-80ms). 1.5s leaves plenty of time before the first capture trigger.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dependencies.primeAudio()
        }

        registerObservers()
        checkScreenRecordingPermission()
        scheduleInitialCapturePrewarm()

        isFinishLaunchingComplete = true
        if !pendingOpenURLs.isEmpty {
            let urlsToOpen = pendingOpenURLs
            pendingOpenURLs.removeAll()
            dependencies.handleOpenURLs(urlsToOpen)
        }

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
        initialCapturePrewarmWorkItem?.cancel()
        initialCapturePrewarmWorkItem = nil
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

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenURLsNotification(_:)),
            name: .init("com.fxzer.macshot.openURLs"),
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

    private func scheduleInitialCapturePrewarm(attempt: Int = 0) {
        initialCapturePrewarmWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.dependencies.hasActiveOverlaySession() else {
                guard attempt + 1 < Self.initialCapturePrewarmMaxAttempts else { return }
                self.scheduleInitialCapturePrewarm(attempt: attempt + 1)
                return
            }

            let targetScreen = self.dependencies.defaultInteractionScreen()
            CaptureDiagnostics.log(
                "[macshot-perf][prewarm] launch scheduled attempt=\(attempt + 1) screen=\(targetScreen?.localizedName ?? "nil")"
            )
            ScreenCaptureManager.prewarm(screen: targetScreen, mode: .full)
        }

        initialCapturePrewarmWorkItem = workItem
        let delay = attempt == 0 ? Self.initialCapturePrewarmDelay : Self.initialCapturePrewarmRetryDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    @objc private func handleShowAndOpenPrefs() {
        if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
            UserDefaults.standard.set(false, forKey: "hideMenuBarIcon")
            dependencies.setMenuBarIconVisible(true)
        }
        dependencies.openSettings()
    }

    @objc private func handleOpenURLsNotification(_ notification: Notification) {
        guard let urlStrings = notification.userInfo?["urls"] as? [String] else { return }
        let urls = urlStrings.compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return }
        dependencies.handleOpenURLs(urls)
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
