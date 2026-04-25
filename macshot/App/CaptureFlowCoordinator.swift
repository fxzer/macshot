import Cocoa

@MainActor
final class CaptureFlowCoordinator {

    struct Dependencies {
        let overlayDelegateProvider: () -> OverlayWindowControllerDelegate?
        let isRecordingInProgress: () -> Bool
        let rememberPreviousApp: (NSRunningApplication?) -> Void
        let restoreFocusIfNeeded: () -> Void
        let defaultInteractionScreen: () -> NSScreen?
        let statusBarInteractionScreen: () -> NSScreen?
        let showOnboarding: (NSScreen?) -> Void
        let hideThumbnails: () -> Void
        let showThumbnails: () -> Void
        let excludedWindowNumbers: () -> [CGWindowID]
    }

    private let dependencies: Dependencies

    private var overlayControllersStorage: [OverlayWindowController] = []
    private var isCapturing = false
    private var activeCaptureIntent: CaptureIntent?
    private var overlayScreenSwitchInFlight = false
    private var overlayMouseScreenTimer: Timer?
    private var overlayEscMonitor: Any?
    private var countdownWindow: NSWindow?
    private var countdownTimer: Timer?
    private var countdownEscMonitor: Any?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var overlayControllers: [OverlayWindowController] {
        overlayControllersStorage
    }

    var hasActiveOverlaySession: Bool {
        !overlayControllersStorage.isEmpty
    }

    func currentCaptureTargetScreen() -> NSScreen? {
        currentMouseScreen() ?? dependencies.statusBarInteractionScreen() ?? dependencies.defaultInteractionScreen()
    }

    func beginCapture(intent: CaptureIntent, triggerOrigin: String) {
        let t0 = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        NSLog("[PERF] ========== beginCapture START intent=\(intent.debugName) origin=\(triggerOrigin) ==========")
        #endif
        startCapture(intent: intent, triggerOrigin: triggerOrigin)
        #if DEBUG
        NSLog("[PERF] ========== beginCapture END elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms ==========")
        #endif
    }

    func dismissOverlays(refocusPreviousApp: Bool = true) {
        stopOverlayMouseScreenTracking()
        removeOverlayEscMonitor()
        overlayScreenSwitchInFlight = false
        autoreleasepool {
            for controller in overlayControllersStorage {
                controller.dismiss()
            }
            overlayControllersStorage.removeAll()
        }
        isCapturing = false
        activeCaptureIntent = nil
        dependencies.showThumbnails()
        if refocusPreviousApp {
            dependencies.restoreFocusIfNeeded()
        }
    }

    private func startCapture(intent: CaptureIntent, triggerOrigin: String) {
        guard !isCapturing else { return }
        guard !dependencies.isRecordingInProgress() else { return }
        isCapturing = true
        activeCaptureIntent = intent
        let t0 = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        NSLog("[PERF] startCapture BEGIN intent=\(intent.debugName) origin=\(triggerOrigin) t=\(t0)")
        #endif

        ScreenCaptureManager.prewarm()
        let delay = UserDefaults.standard.integer(forKey: "captureDelaySeconds")

        let rememberTool = UserDefaults.standard.object(forKey: "rememberLastTool") as? Bool ?? true
        if !rememberTool {
            UserDefaults.standard.removeObject(forKey: "effectsPreset")
            UserDefaults.standard.removeObject(forKey: "effectsBrightness")
            UserDefaults.standard.removeObject(forKey: "effectsContrast")
            UserDefaults.standard.removeObject(forKey: "effectsSaturation")
            UserDefaults.standard.removeObject(forKey: "effectsSharpness")
            UserDefaults.standard.set(false, forKey: "beautifyEnabled")
        }

        dependencies.rememberPreviousApp(NSWorkspace.shared.frontmostApplication)

        #if DEBUG
        NSLog("[PERF] startCapture: prewarm + dismissOverlays + hideThumbnails BEGIN")
        #endif
        if !overlayControllersStorage.isEmpty {
            dismissOverlays(refocusPreviousApp: false)
        }
        dependencies.hideThumbnails()
        #if DEBUG
        NSLog("[PERF] startCapture: dismissOverlays + hideThumbnails DONE elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        #endif

        if delay > 0 {
            showPreCaptureCountdown(seconds: delay)
        } else {
            performCapture(t0: t0)
        }
    }

    private func currentMouseScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    private func screenDisplayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func shouldFollowMouseAcrossScreens(for controller: OverlayWindowController) -> Bool {
        controller.selectionRect.width < 1 && controller.selectionRect.height < 1
    }

    private func startOverlayMouseScreenTracking() {
        stopOverlayMouseScreenTracking()
        guard isCapturing, overlayControllersStorage.count == 1 else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateOverlayScreenForMouseIfNeeded()
        }
        overlayMouseScreenTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopOverlayMouseScreenTracking() {
        overlayMouseScreenTimer?.invalidate()
        overlayMouseScreenTimer = nil
    }

    private func installOverlayEscMonitor() {
        guard overlayEscMonitor == nil else { return }
        overlayEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.hasActiveOverlaySession else { return event }
            guard self.shouldRouteEscapeToOverlay(for: event.window),
                  let controller = self.controllerHandlingEscape(for: event.window),
                  controller.overlayView?.shouldHandleEscapeFromMonitor() == true,
                  controller.overlayView?.handleEscapeKey() == true
            else {
                return event
            }
            return nil
        }
    }

    private func removeOverlayEscMonitor() {
        if let monitor = overlayEscMonitor {
            NSEvent.removeMonitor(monitor)
            overlayEscMonitor = nil
        }
    }

    private func shouldRouteEscapeToOverlay(for eventWindow: NSWindow?) -> Bool {
        guard let eventWindow else { return false }
        if overlayControllersStorage.contains(where: { $0.overlayWindow === eventWindow }) {
            return true
        }
        if let popoverWindow = PopoverHelper.window, popoverWindow === eventWindow {
            return true
        }
        return false
    }

    private func controllerHandlingEscape(for eventWindow: NSWindow?) -> OverlayWindowController? {
        if let eventWindow,
           let directController = overlayControllersStorage.first(where: { $0.overlayWindow === eventWindow })
        {
            return directController
        }
        if let keyController = overlayControllersStorage.first(where: { $0.overlayWindow?.isKeyWindow == true }) {
            return keyController
        }
        if let mouseScreen = currentMouseScreen(),
           let screenController = overlayControllersStorage.first(where: { $0.screen == mouseScreen }) {
            return screenController
        }
        return overlayControllersStorage.first
    }

    private func makePrimaryOverlayKey() {
        controllerHandlingEscape(for: nil)?.makeKey()
    }

    private func clearOverlayControllersForScreenSwitch() {
        autoreleasepool {
            for controller in overlayControllersStorage {
                controller.dismiss()
            }
            overlayControllersStorage.removeAll()
        }
    }

    private func updateOverlayScreenForMouseIfNeeded() {
        guard isCapturing, !overlayScreenSwitchInFlight, overlayControllersStorage.count == 1 else { return }
        guard let controller = overlayControllersStorage.first,
              shouldFollowMouseAcrossScreens(for: controller),
              let mouseScreen = currentMouseScreen()
        else { return }
        guard screenDisplayID(for: controller.screen) != screenDisplayID(for: mouseScreen) else { return }
        switchActiveOverlay(to: mouseScreen)
    }

    private func switchActiveOverlay(to screen: NSScreen) {
        guard !overlayControllersStorage.isEmpty else { return }
        overlayScreenSwitchInFlight = true
        let t0 = CFAbsoluteTimeGetCurrent()
        let excludeIDs = dependencies.excludedWindowNumbers()

        clearOverlayControllersForScreenSwitch()
        dependencies.hideThumbnails()

        ScreenCaptureManager.captureScreen(screen, excludingWindowNumbers: excludeIDs) { [weak self] capture in
            guard let self else { return }
            self.overlayScreenSwitchInFlight = false

            guard let capture else {
                self.isCapturing = false
                self.activeCaptureIntent = nil
                self.dependencies.showOnboarding(screen)
                return
            }

            self.showOverlays(
                for: [capture],
                t0: t0,
                activateApp: false,
                restoreLastSelection: false
            )
        }
    }

    private func showPreCaptureCountdown(seconds: Int) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window

        countdownEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelPreCaptureCountdown()
                return nil
            }
            return event
        }

        var remaining = seconds
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                Task { @MainActor [weak self] in
                    self?.countdownTimer = nil
                    self?.countdownWindow?.orderOut(nil)
                    self?.countdownWindow = nil
                    self?.removeCountdownEscMonitors()
                    self?.performCapture()
                }
            } else {
                countdownView.remaining = remaining
                countdownView.needsDisplay = true
            }
        }
    }

    private func removeCountdownEscMonitors() {
        if let monitor = countdownEscMonitor {
            NSEvent.removeMonitor(monitor)
            countdownEscMonitor = nil
        }
    }

    private func cancelPreCaptureCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
        removeCountdownEscMonitors()
        isCapturing = false
        activeCaptureIntent = nil
        stopOverlayMouseScreenTracking()
    }

    private func performCapture(t0: CFAbsoluteTime = 0) {
        #if DEBUG
        NSLog("[PERF] performCapture BEGIN elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        #endif

        let excludeIDs = dependencies.excludedWindowNumbers()
        let targetScreen = currentCaptureTargetScreen()
        startLiveCapture(excludedWindowNumbers: excludeIDs, targetScreen: targetScreen, t0: t0)
    }

    private func startLiveCapture(
        excludedWindowNumbers excludeIDs: [CGWindowID],
        targetScreen: NSScreen?,
        t0: CFAbsoluteTime
    ) {
        #if DEBUG
        NSLog("[PERF] performCapture: no prepared result, calling captureScreen...")
        #endif
        guard let targetScreen else {
            isCapturing = false
            activeCaptureIntent = nil
            dependencies.showOnboarding(dependencies.defaultInteractionScreen())
            return
        }
        let captureT0 = CFAbsoluteTimeGetCurrent()
        ScreenCaptureManager.captureScreen(targetScreen, excludingWindowNumbers: excludeIDs) { [weak self] capture in
            guard let self else { return }
            #if DEBUG
            NSLog("[PERF] captureScreen callback: elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms (capture itself=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - captureT0) * 1000))ms)")
            #endif

            guard let capture else {
                self.isCapturing = false
                self.activeCaptureIntent = nil
                self.dependencies.showOnboarding(targetScreen)
                return
            }

            self.showOverlays(for: [capture], t0: t0)
        }
    }

    private func showOverlays(
        for captures: [ScreenCapture],
        t0: CFAbsoluteTime = 0,
        activateApp: Bool = true,
        restoreLastSelection: Bool = true
    ) {
        #if DEBUG
        NSLog("[PERF] showOverlays BEGIN: \(captures.count) screens")
        #endif
        let createT0 = CFAbsoluteTimeGetCurrent()
        let captureIntent = activeCaptureIntent

        stopOverlayMouseScreenTracking()
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }

        for (index, capture) in captures.enumerated() {
            let controllerT0 = CFAbsoluteTimeGetCurrent()
            #if DEBUG
            NSLog("[PERF] showOverlays: creating controller \(index) for screen=\(capture.screen.localizedName)")
            #endif
            let controller = OverlayWindowController(capture: capture)
            controller.overlayDelegate = dependencies.overlayDelegateProvider()
            controller.onFirstFrameShown = {
                #if DEBUG
                NSLog("[PERF] first overlay frame drawn elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms screen=\(capture.screen.localizedName)")
                #endif
            }
            if captureIntent?.startsInRecordingMode == true {
                controller.setAutoRecordMode()
            }
            if captureIntent?.startsInOCRMode == true {
                controller.setAutoOCRMode()
            }
            if captureIntent?.startsInQuickSaveMode == true {
                controller.setAutoQuickSaveMode()
            }
            if captureIntent?.startsInScrollCaptureMode == true {
                controller.setAutoScrollCaptureMode()
            }
            let showT0 = CFAbsoluteTimeGetCurrent()
            controller.showOverlay()
            #if DEBUG
            NSLog("[PERF] showOverlays: controller \(index) showOverlay DONE elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - controllerT0) * 1000))ms (showOverlay call=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - showT0) * 1000))ms)")
            #endif
            let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            let isMouseScreen = (capture.screen == mouseScreen) || (mouseScreen == nil && capture.screen == NSScreen.main)
            if captureIntent?.appliesFullScreenSelection == true && isMouseScreen {
                controller.applyFullScreenSelection()
            }
            if captureIntent?.startsInRecordingMode == true
                && captureIntent?.appliesFullScreenSelection == true
                && isMouseScreen {
                controller.enterRecordingMode()
                if captureIntent?.autoStartsFullScreenRecording == true {
                    controller.autoStartRecording()
                }
            }
            overlayControllersStorage.append(controller)
        }
        #if DEBUG
        NSLog("[PERF] OverlayWindowControllers created+shown elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - createT0) * 1000))ms")
        NSLog("[PERF] TOTAL startCapture→overlay visible: \(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        #endif

        installOverlayEscMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.makePrimaryOverlayKey()
        }

        if restoreLastSelection && (captureIntent?.shouldRestoreLastSelection ?? true) {
            restoreLastSelectionIfNeeded(controllers: overlayControllersStorage)
        }
        startOverlayMouseScreenTracking()
    }

    private func restoreLastSelectionIfNeeded(controllers: [OverlayWindowController]) {
        guard UserDefaults.standard.bool(forKey: "rememberLastSelection") else { return }
        guard let rectStr = UserDefaults.standard.string(forKey: "lastSelectionRect"),
              let screenStr = UserDefaults.standard.string(forKey: "lastSelectionScreenFrame") else { return }
        let savedRect = NSRectFromString(rectStr)
        let savedScreenFrame = NSRectFromString(screenStr)
        guard savedRect.width > 1, savedRect.height > 1 else { return }
        for controller in controllers where controller.screen.frame == savedScreenFrame {
            controller.applySelection(savedRect, restoredFromMemory: true)
            break
        }
    }
}
