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
    private var captureRequestID = 0
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
        CaptureDiagnostics.log("[macshot-perf] ========== beginCapture intent=\(intent.debugName) origin=\(triggerOrigin) ==========")
        CaptureDiagnostics.log(
            "[macshot-mem][capture] beginCapture intent=\(intent.debugName) origin=\(triggerOrigin) \(MemoryDiagnostics.currentSummary()) overlays=\(overlayControllersStorage.count)"
        )
        MemoryDiagnostics.snapshot(
            "CaptureFlow.beginCapture",
            metadata: "intent=\(intent.debugName) origin=\(triggerOrigin) overlays=\(overlayControllersStorage.count)"
        )
        startCapture(intent: intent, triggerOrigin: triggerOrigin)
    }

    func dismissOverlays(refocusPreviousApp: Bool = true) {
        MemoryDiagnostics.snapshot(
            "CaptureFlow.dismissOverlays.before",
            metadata: "overlayCount=\(overlayControllersStorage.count) refocus=\(refocusPreviousApp)"
        )
        stopOverlayMouseScreenTracking()
        removeOverlayEscMonitor()
        overlayScreenSwitchInFlight = false
        // Memory optimization: use autoreleasepool to ensure overlay resources
        // (screenshot images, capture assets) are released promptly
        autoreleasepool {
            for controller in overlayControllersStorage {
                controller.dismiss()
            }
            overlayControllersStorage.removeAll()
        }
        dismissStrayOverlayWindows(reason: "dismissOverlays")
        isCapturing = false
        activeCaptureIntent = nil
        ScreenCaptureManager.setCaptureInProgress(false)
        dependencies.showThumbnails()
        if refocusPreviousApp {
            dependencies.restoreFocusIfNeeded()
        }
        CaptureDiagnostics.log(
            "[macshot-mem][capture] dismissOverlays.after overlayCount=\(overlayControllersStorage.count) \(MemoryDiagnostics.currentSummary())"
        )
        MemoryDiagnostics.snapshot("CaptureFlow.dismissOverlays.after", metadata: "overlayCount=\(overlayControllersStorage.count)")
    }

    private func startCapture(intent: CaptureIntent, triggerOrigin: String) {
        guard !isCapturing else { return }
        guard !dependencies.isRecordingInProgress() else { return }
        isCapturing = true
        activeCaptureIntent = intent
        var perf = PerfMonitor(label: "capture")
        var memory = MemoryDiagnostics.makeScope(
            "CaptureFlow.startCapture",
            metadata: "intent=\(intent.debugName) origin=\(triggerOrigin)"
        )

        let delay = UserDefaults.standard.integer(forKey: DefaultsKey.captureDelaySeconds)
        let targetScreen = currentCaptureTargetScreen()

        if delay > 0 {
            ScreenCaptureManager.prewarm(screen: targetScreen, mode: .full)
            perf.step("prewarm")
            memory.step("prewarm", metadata: "mode=full delay=\(delay)")
        } else {
            CaptureDiagnostics.log("[macshot-perf][capture] prewarm skipped (immediate capture)")
            memory.step("prewarm skipped", metadata: "delay=0")
        }
        ScreenCaptureManager.setCaptureInProgress(true)

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
        perf.step("rememberPreviousApp")
        memory.step("rememberPreviousApp")

        if !overlayControllersStorage.isEmpty {
            dismissOverlays(refocusPreviousApp: false)
            perf.step("dismissOverlays")
            memory.step("dismissOverlays")
        }
        dismissStrayOverlayWindows(reason: "startCapture preflight")
        dependencies.hideThumbnails()
        perf.step("hideThumbnails")
        memory.step("hideThumbnails", metadata: "delay=\(delay)")

        if delay > 0 {
            memory.finish("waiting for countdown", metadata: "seconds=\(delay)")
            showPreCaptureCountdown(seconds: delay)
        } else {
            memory.finish("starting live capture")
            performCapture(t0: perf.start)
        }
    }

    private func currentMouseScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    private func nextCaptureRequestID(reason: String) -> Int {
        captureRequestID += 1
        let requestID = captureRequestID
        CaptureDiagnostics.log("[macshot-debug][overlay] requestID=\(requestID) reason=\(reason)")
        return requestID
    }

    private func trackedOverlayWindowNumbers() -> Set<CGWindowID> {
        Set(overlayControllersStorage.compactMap { controller in
            controller.overlayWindow.map { CGWindowID($0.windowNumber) }
        })
    }

    private func logOverlayWindowState(_ reason: String) {
        let trackedWindows = overlayControllersStorage.map { controller in
            let windowNumber = controller.overlayWindow.map { String($0.windowNumber) } ?? "nil"
            let visibility = controller.overlayWindow?.isVisible == true ? "visible" : "hidden"
            return "\(controller.screen.localizedName)#\(windowNumber):\(visibility)"
        }.joined(separator: ",")

        let appOverlayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }.map { window in
            "#\(window.windowNumber):\(window.isVisible ? "visible" : "hidden")"
        }.joined(separator: ",")

        CaptureDiagnostics.log(
            "[macshot-debug][overlay] \(reason) trackedCount=\(overlayControllersStorage.count) tracked=[\(trackedWindows)] appOverlayWindows=[\(appOverlayWindows)]"
        )
    }

    private func dismissStrayOverlayWindows(reason: String) {
        let trackedWindowNumbers = trackedOverlayWindowNumbers()
        let strayWindows = NSApp.windows.compactMap { $0 as? OverlayWindow }.filter { window in
            !trackedWindowNumbers.contains(CGWindowID(window.windowNumber))
        }

        guard !strayWindows.isEmpty else {
            logOverlayWindowState("\(reason) stray=0")
            return
        }

        let straySummary = strayWindows.map { window in
            "#\(window.windowNumber):\(window.isVisible ? "visible" : "hidden")"
        }.joined(separator: ",")
        CaptureDiagnostics.log(
            "[macshot-debug][overlay] \(reason) closing stray overlay windows [\(straySummary)]"
        )

        for window in strayWindows {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        logOverlayWindowState("\(reason) strayClosed=\(strayWindows.count)")
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
            Task { @MainActor [weak self] in
                self?.updateOverlayScreenForMouseIfNeeded()
            }
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
        // Memory optimization: use autoreleasepool to ensure overlay resources
        // are released promptly during screen switches
        autoreleasepool {
            for controller in overlayControllersStorage {
                controller.dismiss()
            }
            overlayControllersStorage.removeAll()
        }
        dismissStrayOverlayWindows(reason: "screen switch clear")
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
        let requestID = nextCaptureRequestID(reason: "screen switch to \(screen.localizedName)")

        clearOverlayControllersForScreenSwitch()
        dependencies.hideThumbnails()

        ScreenCaptureManager.captureScreen(screen, excludingWindowNumbers: excludeIDs) { [weak self] capture in
            guard let self else { return }
            guard requestID == self.captureRequestID, self.isCapturing else {
                CaptureDiagnostics.log(
                    "[macshot-debug][overlay] stale screen switch callback requestID=\(requestID) current=\(self.captureRequestID) isCapturing=\(self.isCapturing)"
                )
                self.dismissStrayOverlayWindows(reason: "screen switch stale callback")
                return
            }
            self.overlayScreenSwitchInFlight = false

            guard let capture else {
                self.isCapturing = false
                self.activeCaptureIntent = nil
                ScreenCaptureManager.setCaptureInProgress(false)
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
        ScreenCaptureManager.setCaptureInProgress(false)
        stopOverlayMouseScreenTracking()
    }

    private func performCapture(t0: CFAbsoluteTime = 0) {
        var perf = PerfMonitor(label: "capture")
        perf.step("performCapture BEGIN (t0=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms from trigger)")

        let excludeIDs = dependencies.excludedWindowNumbers()
        let targetScreen = currentCaptureTargetScreen()
        startLiveCapture(excludedWindowNumbers: excludeIDs, targetScreen: targetScreen, t0: t0)
    }

    private func startLiveCapture(
        excludedWindowNumbers excludeIDs: [CGWindowID],
        targetScreen: NSScreen?,
        t0: CFAbsoluteTime
    ) {
        var memory = MemoryDiagnostics.makeScope(
            "CaptureFlow.startLiveCapture",
            metadata: "targetScreen=\(targetScreen?.localizedName ?? "nil") excluded=\(excludeIDs.count)"
        )
        guard let targetScreen else {
            isCapturing = false
            activeCaptureIntent = nil
            ScreenCaptureManager.setCaptureInProgress(false)
            dependencies.showOnboarding(dependencies.defaultInteractionScreen())
            memory.finish("missing target screen")
            return
        }
        let requestID = nextCaptureRequestID(reason: "live capture on \(targetScreen.localizedName)")
        let placeholderController =
            (activeCaptureIntent?.prefersImmediateOverlayPresentation == true)
            ? showImmediateOverlay(on: targetScreen, t0: t0)
            : nil
        let placeholderExcludeIDs: [CGWindowID]
        if let placeholderController {
            let windowNumber = placeholderController.windowNumber
            placeholderExcludeIDs = windowNumber == CGWindowID.max ? [] : [windowNumber]
        } else {
            placeholderExcludeIDs = []
        }
        // The immediate placeholder overlay must be a required exclusion. If it is only
        // best-effort, a stale SCShareableContent cache can miss the just-created overlay
        // window and ScreenCaptureKit will occasionally capture the dimming mask itself.
        let effectiveExcludeIDs = Array(Set(excludeIDs + placeholderExcludeIDs))

        CaptureDiagnostics.log(
            "[macshot-perf][capture] captureScreen BEGIN screen=\(targetScreen.localizedName) excludes=\(effectiveExcludeIDs.count)"
        )
        memory.step(
            "captureScreen begin",
            metadata: "requiredExcluded=\(effectiveExcludeIDs.count) placeholderExcluded=\(placeholderExcludeIDs.count)"
        )
        ScreenCaptureManager.captureScreen(
            targetScreen,
            excludingWindowNumbers: effectiveExcludeIDs
        ) { [weak self, weak placeholderController] capture in
            guard let self else { return }
            guard requestID == self.captureRequestID, self.isCapturing else {
                CaptureDiagnostics.log(
                    "[macshot-debug][overlay] stale live capture callback requestID=\(requestID) current=\(self.captureRequestID) isCapturing=\(self.isCapturing)"
                )
                if let placeholderController,
                   !self.overlayControllersStorage.contains(where: { $0 === placeholderController }) {
                    placeholderController.dismiss()
                }
                self.dismissStrayOverlayWindows(reason: "live capture stale callback")
                return
            }
            CaptureDiagnostics.log(
                "[macshot-perf][capture] captureScreen DONE total=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms"
            )
            memory.step(
                "captureScreen done",
                images: [("captureImage", capture?.asset.displayImage)],
                metadata: "captureAvailable=\(capture != nil)"
            )
            ScreenCaptureManager.setCaptureInProgress(false)

            guard let capture else {
                if let placeholderController {
                    self.overlayControllersStorage.removeAll { $0 === placeholderController }
                    placeholderController.dismiss()
                }
                self.isCapturing = false
                self.activeCaptureIntent = nil
                self.dependencies.showOnboarding(targetScreen)
                memory.finish("capture missing")
                return
            }

            if let placeholderController,
               self.overlayControllersStorage.contains(where: { $0 === placeholderController }) {
                placeholderController.applyCapture(capture)
                CaptureDiagnostics.log(
                    "[macshot-perf][overlay] PLACEHOLDER CAPTURE APPLIED total=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms screen=\(capture.screen.localizedName)"
                )
                self.logOverlayWindowState("placeholder capture applied")
                self.makePrimaryOverlayKey()
                self.startOverlayMouseScreenTracking()
                memory.finish(
                    "placeholder applied capture",
                    images: [("captureImage", capture.asset.displayImage)],
                    metadata: "overlayCount=\(self.overlayControllersStorage.count)"
                )
                return
            }

            self.dismissStrayOverlayWindows(reason: "capture callback fallback")
            memory.finish(
                "show overlays",
                images: [("captureImage", capture.asset.displayImage)],
                metadata: "overlayCount=\(self.overlayControllersStorage.count)"
            )
            self.showOverlays(for: [capture], t0: t0)
        }
    }

    private func showImmediateOverlay(on screen: NSScreen, t0: CFAbsoluteTime) -> OverlayWindowController {
        var perf = PerfMonitor(label: "overlay-immediate")
        var memory = MemoryDiagnostics.makeScope("CaptureFlow.showImmediateOverlay", metadata: "screen=\(screen.localizedName)")
        let captureIntent = activeCaptureIntent

        stopOverlayMouseScreenTracking()
        dismissStrayOverlayWindows(reason: "showImmediateOverlay preflight")

        let controller = OverlayWindowController(screen: screen)
        controller.overlayView?.suppressBackdropUntilCapture = true
        configureController(controller, screenName: screen.localizedName, t0: t0)
        controller.showOverlay(activateAppIfNeeded: false)
        perf.step("controller screen=\(screen.localizedName)")
        memory.step("controller ready", metadata: "overlayCountBeforeAppend=\(overlayControllersStorage.count)")
        overlayControllersStorage.append(controller)
        perf.finish()
        memory.finish("controller appended", metadata: "overlayCount=\(overlayControllersStorage.count)")
        logOverlayWindowState("showImmediateOverlay appended")

        installOverlayEscMonitor()

        if captureIntent?.shouldRestoreLastSelection == true {
            restoreLastSelectionIfNeeded(controllers: [controller])
        }
        applyInitialOverlayStateIfNeeded(to: controller, captureScreen: screen, captureIntent: captureIntent)
        return controller
    }

    private func showOverlays(
        for captures: [ScreenCapture],
        t0: CFAbsoluteTime = 0,
        activateApp: Bool = true,
        restoreLastSelection: Bool = true
    ) {
        var perf = PerfMonitor(label: "overlay")
        var memory = MemoryDiagnostics.makeScope(
            "CaptureFlow.showOverlays",
            metadata: "captures=\(captures.count) activateApp=\(activateApp)"
        )
        let captureIntent = activeCaptureIntent

        stopOverlayMouseScreenTracking()
        dismissStrayOverlayWindows(reason: "showOverlays preflight")
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            perf.step("NSApp.activate")
            memory.step("activate app")
        }

        for (index, capture) in captures.enumerated() {
            let controller = OverlayWindowController(capture: capture)
            configureController(controller, screenName: capture.screen.localizedName, t0: t0)
            controller.showOverlay()
            perf.step("controller[\(index)] screen=\(capture.screen.localizedName)")
            memory.step(
                "controller[\(index)] showOverlay",
                images: [("captureImage", capture.asset.displayImage)],
                metadata: "screen=\(capture.screen.localizedName)"
            )
            applyInitialOverlayStateIfNeeded(
                to: controller,
                captureScreen: capture.screen,
                captureIntent: captureIntent
            )
            overlayControllersStorage.append(controller)
        }
        perf.finish()
        memory.finish("all overlays shown", metadata: "overlayCount=\(overlayControllersStorage.count)")
        logOverlayWindowState("showOverlays completed")

        installOverlayEscMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.makePrimaryOverlayKey()
        }

        if restoreLastSelection && (captureIntent?.shouldRestoreLastSelection ?? true) {
            restoreLastSelectionIfNeeded(controllers: overlayControllersStorage)
        }
        startOverlayMouseScreenTracking()
    }

    private func configureController(_ controller: OverlayWindowController, screenName: String, t0: CFAbsoluteTime) {
        controller.overlayDelegate = dependencies.overlayDelegateProvider()
        controller.onFirstFrameShown = {
            CaptureDiagnostics.log(
                "[macshot-perf][overlay] FIRST FRAME DRAWN total=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms screen=\(screenName)"
            )
            CaptureDiagnostics.log(
                "[macshot-mem][overlay] FIRST FRAME DRAWN screen=\(screenName) \(MemoryDiagnostics.currentSummary())"
            )
        }
        if activeCaptureIntent?.startsInOCRMode == true {
            controller.setAutoOCRMode()
        }
        if activeCaptureIntent?.startsInQuickSaveMode == true {
            controller.setAutoQuickSaveMode()
        }
        if activeCaptureIntent?.startsInScrollCaptureMode == true {
            controller.setAutoScrollCaptureMode()
        }
    }

    private func applyInitialOverlayStateIfNeeded(
        to controller: OverlayWindowController,
        captureScreen: NSScreen,
        captureIntent: CaptureIntent?
    ) {
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let isMouseScreen = (captureScreen == mouseScreen) || (mouseScreen == nil && captureScreen == NSScreen.main)
        if captureIntent?.appliesFullScreenSelection == true && isMouseScreen {
            controller.applyFullScreenSelection()
        }
    }

    private func restoreLastSelectionIfNeeded(controllers: [OverlayWindowController]) {
        guard UserDefaults.standard.bool(forKey: "rememberLastSelection") else { return }
        guard let rectStr = UserDefaults.standard.string(forKey: DefaultsKey.lastSelectionRect),
              let screenStr = UserDefaults.standard.string(forKey: DefaultsKey.lastSelectionScreenFrame) else { return }
        let savedRect = NSRectFromString(rectStr)
        let savedScreenFrame = NSRectFromString(screenStr)
        guard savedRect.width > 1, savedRect.height > 1 else { return }
        for controller in controllers where controller.screen.frame == savedScreenFrame {
            controller.applySelection(savedRect, restoredFromMemory: true)
            break
        }
    }
}
