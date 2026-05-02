import Cocoa
import Sparkle

private enum CaptureTriggerOrigin: String {
    case menuBar = "menu"
    case hotkey = "hotkey"
    case external = "external"
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {

    private let focusCoordinator = FocusCoordinator()
    private var settingsController: SettingsWindowController?
    private var ocrController: OCRResultController?
    private var historyOverlayController: HistoryOverlayController?
    private lazy var launchCoordinator = AppLaunchCoordinator(
        dependencies: .init(
            setMenuBarIconVisible: { [weak self] visible in self?.setMenuBarIconVisible(visible) },
            statusBarSetup: { [weak self] in self?.statusBarController.setup() },
            captureAreaFromHotkey: { [weak self] in
                self?.beginCapture(intent: .area, triggerOrigin: .hotkey)
            },
            captureFullScreenFromHotkey: { [weak self] in
                self?.beginCapture(intent: .fullScreen, triggerOrigin: .hotkey)
            },
            recordAreaFromHotkey: { [weak self] in
                self?.beginCapture(intent: .areaRecording, triggerOrigin: .hotkey)
            },
            recordScreenFromHotkey: { [weak self] in
                self?.beginCapture(
                    intent: .fullScreenRecording(
                        autoStartAfterDelay: UserDefaults.standard.integer(forKey: "captureDelaySeconds") > 0
                    ),
                    triggerOrigin: .hotkey
                )
            },
            showHistoryOverlay: { [weak self] in self?.showHistoryOverlay() },
            captureOCRFromHotkey: { [weak self] in
                self?.beginCapture(intent: .ocr, triggerOrigin: .hotkey)
            },
            quickCaptureFromHotkey: { [weak self] in
                self?.beginCapture(intent: .quickCapture, triggerOrigin: .hotkey)
            },
            scrollCaptureFromHotkey: { [weak self] in
                self?.beginCapture(intent: .scrollCapture, triggerOrigin: .hotkey)
            },
            openImageFromClipboard: { [weak self] in
                self?.routeHandler.openImageFromClipboard()
            },
            openSettings: { [weak self] in self?.openSettings() },
            hasActiveOverlaySession: { [weak self] in
                self?.captureFlowCoordinator.hasActiveOverlaySession ?? false
            },
            dismissOverlays: { [weak self] in self?.dismissOverlays() },
            pinHistoryImage: { [weak self] image in self?.showPin(image: image) },
            handleLanguageChange: { [weak self] in self?.handleLanguageChange() },
            defaultInteractionScreen: { [weak self] in self?.defaultInteractionScreen() }
        )
    )
    private lazy var historyMenuController = HistoryMenuController()
    private lazy var routeHandler = AppRouteHandler(
        actions: .init(
            captureArea: { [weak self] in self?.beginCapture(intent: .area, triggerOrigin: .external) },
            captureFullScreen: { [weak self] in self?.beginCapture(intent: .fullScreen, triggerOrigin: .external) },
            quickCapture: { [weak self] in self?.beginCapture(intent: .quickCapture, triggerOrigin: .external) },
            captureOCR: { [weak self] in self?.beginCapture(intent: .ocr, triggerOrigin: .external) },
            recordArea: { [weak self] in self?.beginCapture(intent: .areaRecording, triggerOrigin: .external) },
            recordFullScreen: { [weak self] in
                self?.beginCapture(
                    intent: .fullScreenRecording(
                        autoStartAfterDelay: UserDefaults.standard.integer(forKey: "captureDelaySeconds") > 0
                    ),
                    triggerOrigin: .external
                )
            },
            scrollCapture: { [weak self] in self?.beginCapture(intent: .scrollCapture, triggerOrigin: .external) },
            showHistory: { [weak self] in self?.showHistoryOverlay() },
            openSettings: { [weak self] in self?.openSettings() },
            stopRecording: { [weak self] in self?.stopRecording() }
        ),
        showError: { [weak self] message in
            self?.showStatusError(message: message)
        }
    )
    private lazy var statusBarController = StatusBarController(
        historyMenuController: historyMenuController,
        actions: .init(
            captureArea: { [weak self] in self?.beginCapture(intent: .area, triggerOrigin: .menuBar) },
            captureFullScreen: { [weak self] in self?.beginCapture(intent: .fullScreen, triggerOrigin: .menuBar) },
            captureOCR: { [weak self] in self?.beginCapture(intent: .ocr, triggerOrigin: .menuBar) },
            quickCapture: { [weak self] in self?.beginCapture(intent: .quickCapture, triggerOrigin: .menuBar) },
            scrollCapture: { [weak self] in self?.beginCapture(intent: .scrollCapture, triggerOrigin: .menuBar) },
            setDelaySeconds: { seconds in
                UserDefaults.standard.set(seconds, forKey: "captureDelaySeconds")
            },
            recordArea: { [weak self] in self?.beginCapture(intent: .areaRecording, triggerOrigin: .menuBar) },
            recordScreen: { [weak self] in
                self?.beginCapture(
                    intent: .fullScreenRecording(
                        autoStartAfterDelay: UserDefaults.standard.integer(forKey: "captureDelaySeconds") > 0
                    ),
                    triggerOrigin: .menuBar
                )
            },
            showHistoryOverlay: { [weak self] in self?.showHistoryOverlay() },
            openImage: { [weak self] in self?.routeHandler.openImageFromMenu() },
            openFromClipboard: { [weak self] in self?.routeHandler.openImageFromClipboard() },
            openSettings: { [weak self] in self?.openSettings() },
            checkForUpdates: { [weak self] in self?.checkForUpdates() },
            quit: { [weak self] in self?.quitApp() },
            stopRecording: { [weak self] in self?.stopRecording() },
            pauseRecording: { [weak self] in self?.pauseRecording() },
            resumeRecording: { [weak self] in self?.resumeRecording() }
        )
    )
    private lazy var captureFlowCoordinator = CaptureFlowCoordinator(
        dependencies: .init(
            overlayDelegateProvider: { [weak self] in self },
            isRecordingInProgress: { [weak self] in self?.isRecordingInProgress() ?? false },
            rememberPreviousApp: { [weak self] app in self?.focusCoordinator.rememberPreviousApp(app) },
            restoreFocusIfNeeded: { [weak self] in self?.returnFocusIfNeeded() },
            defaultInteractionScreen: { [weak self] in self?.defaultInteractionScreen() },
            statusBarInteractionScreen: { [weak self] in self?.statusBarController.interactionScreen },
            showOnboarding: { [weak self] screen in self?.showOnboarding(on: screen) },
            hideThumbnails: { [weak self] in self?.hideOutputThumbnails() },
            showThumbnails: { [weak self] in self?.showOutputThumbnails() },
            excludedWindowNumbers: { [weak self] in self?.currentCaptureExcludedWindowNumbers() ?? [] }
        )
    )
    private lazy var outputCoordinator = ScreenshotOutputCoordinator(
        dependencies: .init(
            resolveTargetScreen: { [weak self] in self?.preferredOutputScreen() }
        )
    )
    lazy var recordingFlowCoordinator = RecordingFlowCoordinator(
        dependencies: .init(
            dismissOverlays: { [weak self] refocus in self?.dismissOverlays(refocusPreviousApp: refocus) },
            clearPreviousApp: { [weak self] in self?.focusCoordinator.clearPreviousApp() },
            setMenuBarIconVisible: { [weak self] visible in self?.setMenuBarIconVisible(visible) },
            isMenuBarIconHiddenByPreference: { UserDefaults.standard.bool(forKey: "hideMenuBarIcon") },
            statusBarEnterRecordingMode: { [weak self] controlsMode in
                self?.statusBarController.enterRecordingMode(controlsMode: controlsMode)
            },
            statusBarExitRecordingMode: { [weak self] in
                self?.statusBarController.exitRecordingMode()
            },
            statusBarUpdateRecordingSeconds: { [weak self] seconds in
                self?.statusBarController.updateRecording(seconds: seconds)
            },
            statusBarSetRecordingPaused: { [weak self] paused in
                self?.statusBarController.setRecordingPaused(paused)
            },
            restartCapture: { [weak self] in
                // Restart capture flow to re-show overlays after countdown cancellation
                self?.beginCapture(intent: .area, triggerOrigin: .external)
            }
        )
    )
    lazy var overlaySessionCoordinator = OverlaySessionCoordinator(
        dependencies: .init(
            overlayControllers: { [weak self] in self?.overlayControllers ?? [] }
        )
    )
    lazy var scrollCaptureFlowCoordinator = ScrollCaptureFlowCoordinator(
        dependencies: .init(
            overlayControllers: { [weak self] in self?.overlayControllers ?? [] },
            dismissOverlays: { [weak self] in self?.dismissOverlays() },
            handleCompletedImage: { [weak self] image in self?.completeScrollCapture(with: image) }
        )
    )

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        migrateSoundSettings()
        guard launchCoordinator.applicationDidFinishLaunching(updaterDelegate: self) else { return }
    }

    /// Migrate old sound settings to new semantic keys.
    private func migrateSoundSettings() {
        let oldKey = "playCopySound"
        let newCaptureKey = SoundSettings.captureEnabled

        // Only migrate if new key doesn't exist but old key does
        if UserDefaults.standard.object(forKey: newCaptureKey) == nil,
           let oldValue = UserDefaults.standard.object(forKey: oldKey) as? Bool {
            UserDefaults.standard.set(oldValue, forKey: newCaptureKey)
        }
    }

    private func showOnboarding(on preferredScreen: NSScreen? = nil) {
        launchCoordinator.showOnboarding(on: preferredScreen)
    }

    private func defaultInteractionScreen() -> NSScreen? {
        if let interactionScreen = statusBarController.interactionScreen {
            return interactionScreen
        }
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchCoordinator.applicationShouldHandleReopen(hasVisibleWindows: flag)
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        statusBarController.setVisible(visible)
    }

    func updateDockIconVisibility() {
        let hasVisibleWindows = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        NSApp.setActivationPolicy(
            AppVisibilityPreferences.shouldShowDockIcon && hasVisibleWindows ? .regular : .accessory
        )
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        launchCoordinator.applicationWillTerminate()
    }

    deinit {
        MainActor.assumeIsolated {
            launchCoordinator.applicationWillTerminate()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// True when floating thumbnails or pin windows are visible.
    var hasVisibleFloatingPanels: Bool {
        outputCoordinator.hasVisibleFloatingPanels
    }

    private func preferredOutputScreen() -> NSScreen? {
        captureFlowCoordinator.currentCaptureTargetScreen()
    }

    private func currentCaptureExcludedWindowNumbers() -> [CGWindowID] {
        outputCoordinator.excludedWindowNumbers
    }

    private func hideOutputThumbnails() {
        outputCoordinator.hideThumbnails()
    }

    private func showOutputThumbnails() {
        outputCoordinator.showThumbnails()
    }

    private func showStatusError(message: String) {
        outputCoordinator.showStatusError(message: message)
    }

    private func isRecordingInProgress() -> Bool {
        recordingFlowCoordinator.isRecordingInProgress
    }

    /// Call when a macshot window closes. If no titled windows remain,
    /// switches to accessory activation policy and returns focus to
    /// the previous app (or the next regular app in line).
    func returnFocusIfNeeded() {
        focusCoordinator.returnFocusIfNeeded(
            isRecordingInProgress: { [weak self] in self?.isRecordingInProgress() ?? false },
            visibleWindows: { NSApp.windows }
        )
    }

    /// Activate another app using the modern cooperative activation API.
    static func activateApp(_ app: NSRunningApplication) {
        FocusCoordinator.activateApp(app)
    }

    // MARK: - Capture

    private func beginCapture(intent: CaptureIntent, triggerOrigin: CaptureTriggerOrigin) {
        captureFlowCoordinator.beginCapture(intent: intent, triggerOrigin: triggerOrigin.rawValue)
    }

    @objc private func showHistoryOverlay() {
        if let existing = historyOverlayController {
            existing.dismiss()
            historyOverlayController = nil
            return
        }
        let controller = HistoryOverlayController()
        controller.onDismiss = { [weak self] in
            self?.historyOverlayController = nil
        }
        controller.show()
        historyOverlayController = controller
    }

    private var overlayControllers: [OverlayWindowController] {
        captureFlowCoordinator.overlayControllers
    }

    func dismissOverlays(refocusPreviousApp: Bool = true) {
        scrollCaptureFlowCoordinator.handleOverlaysDismissed()
        captureFlowCoordinator.dismissOverlays(refocusPreviousApp: refocusPreviousApp)
    }

    func showFloatingThumbnail(image: NSImage, annotationData: CaptureAnnotationData? = nil, historyEntryID: String? = nil) {
        outputCoordinator.showFloatingThumbnail(
            image: image,
            annotationData: annotationData,
            historyEntryID: historyEntryID
        )
    }

    func refreshThumbnail(for entryID: String, image: NSImage) {
        outputCoordinator.refreshThumbnail(for: entryID, image: image)
    }

    func performScreenshotPostActions(
        image: NSImage,
        annotationData: CaptureAnnotationData?,
        historyEntryID: String?,
        windowTitle: String?,
        context: CaptureCompletionContext
    ) {
        outputCoordinator.performScreenshotPostActions(
            image: image,
            annotationData: annotationData,
            historyEntryID: historyEntryID,
            windowTitle: windowTitle,
            context: context
        )
    }

    func beginOCRSessionIfNeeded() {
        let shouldShowWindow = OCRPreferences.shouldShowWindow
        dismissOverlays(refocusPreviousApp: !shouldShowWindow)

        guard shouldShowWindow else { return }
        ocrController?.close()
        let ocr = OCRResultController.loading()
        ocrController = ocr
        ocr.show()
    }

    func finishOCRSession(text: String) {
        let shouldCopy = OCRPreferences.shouldCopyToClipboard
        let shouldShowWindow = OCRPreferences.shouldShowWindow

        if shouldCopy && !text.isEmpty {
            PasteboardWriter.writeString(text)
        }

        if shouldShowWindow {
            ocrController?.showRecognizedText(text)
        }
    }

    func performFloatingPanelOverlayAction(_ action: () -> Void) {
        let appToRefocus = focusCoordinator.peekPreviousApp()
        dismissOverlays(refocusPreviousApp: false)
        action()
        if let app = appToRefocus,
           !app.isTerminated,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            DispatchQueue.main.async { AppDelegate.activateApp(app) }
        }
    }

    private func completeScrollCapture(with image: NSImage) {
        ScreenshotHistory.shared.add(image: image)
        let entryID = ScreenshotHistory.shared.entries.first?.id
        performScreenshotPostActions(
            image: image,
            annotationData: nil,
            historyEntryID: entryID,
            windowTitle: nil,
            context: .standard
        )
    }

    func saveImageToPreferredDirectory(
        _ image: NSImage,
        kind: FilenameOutputKind = .screenshot,
        showInFinder: Bool = false,
        showFailureToast: Bool = true,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        outputCoordinator.saveImageToPreferredDirectory(
            image,
            kind: kind,
            showInFinder: showInFinder,
            showFailureToast: showFailureToast,
            completion: completion
        )
    }

    func showSaveResultToast(_ result: Result<URL, Error>, showFailureToast: Bool = true) {
        outputCoordinator.showSaveResultToast(result, showFailureToast: showFailureToast)
    }

    // MARK: - Upload

    func uploadImage(_ image: NSImage) {
        outputCoordinator.uploadImage(image)
    }

    @objc private func stopRecording() {
        recordingFlowCoordinator.stopRecording()
    }

    private func pauseRecording() {
        recordingFlowCoordinator.pauseRecording()
    }

    private func resumeRecording() {
        recordingFlowCoordinator.resumeRecording()
    }

    private func handleLanguageChange() {
        // Language changes can originate from an AppKit popup menu, so defer
        // rebuilding the status menu until that tracking loop has unwound.
        DispatchQueue.main.async { [weak self] in
            self?.statusBarController.rebuildMenu()
        }

        // Update OCR result window if open
        ocrController?.updateLocalization()

        // Update history overlay if open
        historyOverlayController?.updateLocalization()

        outputCoordinator.updateLocalization()
        recordingFlowCoordinator.updateLocalization()
        launchCoordinator.updateLocalization()
    }

    func showPin(image: NSImage) {
        outputCoordinator.showPin(image: image)
    }

    func showPin(image: NSImage, at origin: NSPoint) {
        outputCoordinator.showPin(image: image, at: origin)
    }

    // MARK: - Open Image

    /// Handle files opened via Finder "Open With", drag-to-dock, or command line.
    func application(_ application: NSApplication, open urls: [URL]) {
        routeHandler.handleOpen(urls: urls)
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(onHotkeyChanged: { [weak self] in
                self?.launchCoordinator.registerHotkey()
                self?.statusBarController.rebuildMenu()
            })
        }
        settingsController?.showWindow()
    }

    // MARK: - Quit

    @objc private func checkForUpdates() {
        launchCoordinator.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - SPUUpdaterDelegate

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: "betaUpdatesEnabled") ? ["beta"] : []
    }

    /// Show a confirmation dialog before clearing all history. Reused by history panel trash button.
    func confirmClearHistory() {
        historyMenuController.confirmClearHistory()
    }
}
