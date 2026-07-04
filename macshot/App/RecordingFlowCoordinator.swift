import Cocoa
import AVFoundation

@MainActor
final class RecordingFlowCoordinator: StatusToastHost {

    struct Dependencies {
        let dismissOverlays: (Bool) -> Void
        let clearPreviousApp: () -> Void
        let setMenuBarIconVisible: (Bool) -> Void
        let isMenuBarIconHiddenByPreference: () -> Bool
        let statusBarEnterRecordingMode: (RecordingControlsMode) -> Void
        let statusBarExitRecordingMode: () -> Void
        let statusBarUpdateRecordingSeconds: (Int) -> Void
        let statusBarSetRecordingPaused: (Bool) -> Void
        let restartCapture: () -> Void
    }

    private let dependencies: Dependencies

    private var countdownWindow: NSWindow?
    private var countdownTimer: Timer?
    private var countdownEscMonitor: Any?
    private var recordingEngine: RecordingEngine?
    private var audioMergeController: AudioMergeController?
    private var recordingHUDPanel: RecordingHUDPanel?
    private var recordingScreenRect: NSRect = .zero
    private var recordingScreen: NSScreen?
    private var mouseHighlightOverlay: MouseHighlightOverlay?
    private var keystrokeOverlay: KeystrokeOverlay?
    private var webcamOverlay: WebcamOverlay?
    private var selectionBorderOverlay: SelectionBorderOverlay?
    private var menuBarIconWasHidden = false
    // `internal` to satisfy `StatusToastHost.uploadToastController`; access stays
    // within the coordinator layer.
    var uploadToastController: UploadToastController?
    private var recordingQuickActionsController: RecordingToastController?
    private var recordingSourceRetainCounts: [URL: Int] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var isRecordingInProgress: Bool {
        recordingEngine != nil
    }

    func updateLocalization() {
        uploadToastController?.updateLocalization()
        recordingQuickActionsController?.updateLocalization()
    }

    func startRecording(from controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        recordingScreenRect = rect
        recordingScreen = screen

        let fpsOverride = controller.sessionRecordingFPS
        let onStopOverride = controller.sessionRecordingOnStop
        let delayOverride = controller.sessionRecordingDelay
        let controlsMode =
            RecordingControlsMode.resolved(raw: controller.sessionRecordingControlsMode)
            ?? RecordingControlsMode.current
        let existingWebcam = controller.detachWebcamPreview()

        dependencies.dismissOverlays(true)
        dependencies.clearPreviousApp()

        let delay = delayOverride ?? UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if delay > 0 {
                existingWebcam?.stopPreview()
                existingWebcam?.close()
                self.startRecordingCountdown(
                    seconds: delay,
                    rect: rect,
                    screen: screen,
                    fpsOverride: fpsOverride,
                    onStopOverride: onStopOverride,
                    controlsMode: controlsMode
                )
            } else {
                self.beginRecording(
                    rect: rect,
                    screen: screen,
                    fpsOverride: fpsOverride,
                    onStopOverride: onStopOverride,
                    existingWebcam: existingWebcam,
                    controlsMode: controlsMode
                )
            }
        }
    }

    func handleStopRecordingRequest() {
        if let engine = recordingEngine {
            engine.stopRecording()
        } else {
            dependencies.dismissOverlays(true)
        }
    }

    func stopRecording() {
        recordingEngine?.stopRecording()
    }

    func pauseRecording() {
        recordingEngine?.pauseRecording()
    }

    func resumeRecording() {
        recordingEngine?.resumeRecording()
    }

    private func startRecordingCountdown(
        seconds: Int,
        rect: NSRect,
        screen: NSScreen,
        fpsOverride: Int?,
        onStopOverride: String?,
        controlsMode: RecordingControlsMode
    ) {
        resetRecordingCountdownState(removeSelectionBorder: true)

        let size = NSSize(width: 140, height: 140)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
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
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = CountdownView(frame: NSRect(origin: .zero, size: size))
        countdownView.remaining = seconds
        window.contentView = countdownView
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window

        let border = SelectionBorderOverlay(screen: screen)
        border.setSelectionRect(rect)
        border.orderFrontRegardless()
        selectionBorderOverlay = border

        countdownEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancelRecordingCountdown()
                return nil
            }
            return event
        }

        var remaining = seconds
        let recordingScreenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                Task { @MainActor [weak self] in
                    let resolvedScreen = recordingScreenID.flatMap { displayID in
                        NSScreen.screens.first {
                            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                        }
                    } ?? NSScreen.main ?? NSScreen.screens.first
                    guard let resolvedScreen else { return }
                    self?.resetRecordingCountdownState(removeSelectionBorder: false)
                    self?.beginRecording(
                        rect: rect,
                        screen: resolvedScreen,
                        fpsOverride: fpsOverride,
                        onStopOverride: onStopOverride,
                        controlsMode: controlsMode
                    )
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

    private func resetRecordingCountdownState(removeSelectionBorder: Bool) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
        removeCountdownEscMonitors()
        guard removeSelectionBorder else { return }
        selectionBorderOverlay?.close()
        selectionBorderOverlay = nil
    }

    private func cancelRecordingCountdown() {
        resetRecordingCountdownState(removeSelectionBorder: true)
        // Restart capture flow to re-show overlays after countdown cancellation
        dependencies.restartCapture()
    }

    private func beginRecording(
        rect: NSRect,
        screen: NSScreen,
        fpsOverride: Int?,
        onStopOverride: String?,
        existingWebcam: WebcamOverlay? = nil,
        controlsMode: RecordingControlsMode = .floatingHUD
    ) {
        let engine = RecordingEngine()
        engine.onProgress = { [weak self] seconds in
            self?.updateRecordingHUD(seconds: seconds)
        }
        let hadSystemAudio = UserDefaults.standard.bool(forKey: "recordSystemAudio")
        let hadMicAudio = UserDefaults.standard.bool(forKey: "recordMicAudio")

        engine.onCompletion = { [weak self] url, error in
            guard let self else { return }
            self.stopRecordingUI()

            if let url {
                let deliverRecording: (URL) -> Void = { [weak self] finalURL in
                    self?.performRecordingPostActions(url: finalURL)
                }

                if hadSystemAudio && hadMicAudio {
                    let merger = AudioMergeController()
                    self.audioMergeController = merger
                    merger.show(url: url) { [weak self] finalURL in
                        self?.audioMergeController = nil
                        deliverRecording(finalURL)
                    }
                } else {
                    deliverRecording(url)
                }
            } else if let error {
                // Stream error or capture failure — surface to the user instead of
                // silently producing nothing. DEBUG log retained for diagnostics.
                #if DEBUG
                print("Recording failed: \(error.localizedDescription)")
                #endif
                self.showRecordingFailureToast(error)
            }
        }
        recordingEngine = engine

        selectionBorderOverlay?.close()
        let border = SelectionBorderOverlay(screen: screen)
        border.setSelectionRect(rect)
        border.orderFrontRegardless()
        selectionBorderOverlay = border

        if controlsMode == .floatingHUD {
            let hud = RecordingHUDPanel()
            hud.update(elapsedSeconds: 0)
            hud.positionOnScreen(relativeTo: rect, screen: screen)
            hud.onStopRecording = { [weak self] in self?.stopRecording() }
            hud.onPauseRecording = { [weak self] in self?.pauseRecording() }
            hud.onResumeRecording = { [weak self] in self?.resumeRecording() }
            hud.orderFrontRegardless()
            recordingHUDPanel = hud
        }

        engine.onPauseChanged = { [weak self] paused in
            self?.recordingHUDPanel?.setPaused(paused)
            self?.dependencies.statusBarSetRecordingPaused(paused)
        }

        if UserDefaults.standard.bool(forKey: "recordMouseHighlight") && CGPreflightListenEventAccess() {
            let overlay = MouseHighlightOverlay(screen: screen)
            overlay.orderFrontRegardless()
            overlay.startMonitoring()
            mouseHighlightOverlay = overlay
        }

        if UserDefaults.standard.bool(forKey: "recordKeystroke") && KeystrokeOverlay.hasInputMonitoringPermission {
            let overlay = KeystrokeOverlay(screen: screen)
            overlay.setRecordingRect(rect)
            overlay.orderFrontRegardless()
            overlay.startMonitoring()
            keystrokeOverlay = overlay
        }

        if UserDefaults.standard.bool(forKey: "recordWebcam")
            && AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            if let existingWebcam {
                existingWebcam.setDraggable(false)
                existingWebcam.orderFrontRegardless()
                webcamOverlay = existingWebcam
            } else {
                let overlay = WebcamOverlay(screen: screen)
                let position = WebcamPosition(rawValue: UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight") ?? .bottomRight
                let size = WebcamSize(rawValue: UserDefaults.standard.string(forKey: "webcamSize") ?? "medium") ?? .medium
                let shape = WebcamShape(rawValue: UserDefaults.standard.string(forKey: "webcamShape") ?? "circle") ?? .circle
                overlay.configure(position: position, size: size, shape: shape, recordingRect: rect)
                overlay.startPreview(deviceUID: UserDefaults.standard.string(forKey: "selectedCameraDeviceUID"))
                overlay.setDraggable(false)
                overlay.orderFrontRegardless()
                webcamOverlay = overlay
            }
        } else {
            existingWebcam?.stopPreview()
            existingWebcam?.close()
        }

        enterRecordingMenuBarMode(controlsMode: controlsMode)

        var excludeIDs: [CGWindowID] = []
        if let border = selectionBorderOverlay { excludeIDs.append(CGWindowID(border.windowNumber)) }
        if let hud = recordingHUDPanel { excludeIDs.append(CGWindowID(hud.windowNumber)) }

        engine.startRecording(rect: rect, screen: screen, fpsOverride: fpsOverride, excludeWindowNumbers: excludeIDs)
    }

    private func updateRecordingHUD(seconds: Int) {
        recordingHUDPanel?.update(elapsedSeconds: seconds)
        dependencies.statusBarUpdateRecordingSeconds(seconds)
        if let screen = recordingScreen, !(recordingHUDPanel?.userHasDragged ?? false) {
            recordingHUDPanel?.positionOnScreen(relativeTo: recordingScreenRect, screen: screen)
        }
    }

    private func enterRecordingMenuBarMode(controlsMode: RecordingControlsMode) {
        menuBarIconWasHidden = dependencies.isMenuBarIconHiddenByPreference()
        if menuBarIconWasHidden {
            dependencies.setMenuBarIconVisible(true)
        }
        dependencies.statusBarEnterRecordingMode(controlsMode)
    }

    private func exitRecordingMenuBarMode() {
        dependencies.statusBarExitRecordingMode()
        if menuBarIconWasHidden {
            dependencies.setMenuBarIconVisible(false)
            menuBarIconWasHidden = false
        }
    }

    private func stopRecordingUI() {
        recordingHUDPanel?.close()
        recordingHUDPanel = nil
        selectionBorderOverlay?.close()
        selectionBorderOverlay = nil
        mouseHighlightOverlay?.stopMonitoring()
        mouseHighlightOverlay?.close()
        mouseHighlightOverlay = nil
        keystrokeOverlay?.stopMonitoring()
        keystrokeOverlay?.close()
        keystrokeOverlay = nil
        webcamOverlay?.stopPreview()
        webcamOverlay?.close()
        webcamOverlay = nil
        recordingEngine = nil
        recordingScreenRect = .zero
        recordingScreen = nil
        exitRecordingMenuBarMode()
    }

    private func performRecordingPostActions(url: URL) {
        let actions = PostCaptureActionPreferences.recordingActions
        var didRetainAsyncOrUIConsumer = false

        if actions.copyToClipboard {
            copyRecordingToClipboard(url: url)
        }
        if actions.saveToFile {
            retainRecordingSource(url)
            didRetainAsyncOrUIConsumer = true
            let showInFinder = UserDefaults.standard.bool(forKey: "recordingShowInFinder")
            saveRecordingToDefaultDirectory(url, showInFinder: showInFinder) { [weak self] in
                self?.releaseRecordingSource(url)
            }
        }
        if actions.uploadAndCopyLink {
            retainRecordingSource(url)
            didRetainAsyncOrUIConsumer = true
            uploadRecording(url: url) { [weak self] in
                self?.releaseRecordingSource(url)
            }
        }
        if actions.openVideoEditor {
            retainRecordingSource(url)
            didRetainAsyncOrUIConsumer = true
            openVideoEditor(for: url)
        }
        if actions.showQuickAccessOverlay {
            retainRecordingSource(url)
            didRetainAsyncOrUIConsumer = true
            showRecordingQuickActions(url: url)
        }
        if !didRetainAsyncOrUIConsumer {
            TemporaryFileManager.removeTemporaryFile(at: url)
        }
    }

    private func showRecordingQuickActions(url: URL) {
        recordingQuickActionsController?.dismiss()

        let controller = RecordingToastController(url: url)
        controller.onDismiss = { [weak self] in
            self?.recordingQuickActionsController = nil
            self?.releaseRecordingSource(url)
        }
        controller.onCopy = { [weak self] in
            self?.copyRecordingToClipboard(url: url)
        }
        controller.onSave = { [weak self] in
            self?.retainRecordingSource(url)
            self?.saveRecordingToDefaultDirectory(url) { [weak self] in
                self?.releaseRecordingSource(url)
            }
        }
        controller.onUpload = { [weak self] in
            self?.retainRecordingSource(url)
            self?.uploadRecording(url: url) { [weak self] in
                self?.releaseRecordingSource(url)
            }
        }
        controller.onOpen = { [weak self] in
            self?.retainRecordingSource(url)
            self?.openVideoEditor(for: url)
        }
        controller.show()
        recordingQuickActionsController = controller
    }

    private func saveRecordingToDefaultDirectory(
        _ sourceURL: URL,
        showInFinder: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let dirURL = SaveDirectoryAccess.resolveRecordingDirectory()
        let kind: FilenameOutputKind = sourceURL.pathExtension.lowercased() == "gif" ? .gif : .recording
        let destinationURL = FilenameTemplateEngine.uniqueDestinationURL(
            in: dirURL,
            baseName: FilenameTemplateEngine.makeBaseName(kind: kind),
            fileExtension: sourceURL.pathExtension
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { SaveDirectoryAccess.stopAccessing(url: dirURL) }
            let result: Result<URL, Error>
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                result = .success(destinationURL)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                if showInFinder, case .success(let fileURL) = result {
                    _ = FinderRevealService.reveal(fileURL)
                }
                if case .failure(let error) = result {
                    self?.makeStatusToast().showSaveError(
                        message: error.localizedDescription.isEmpty ? L("Save failed") : error.localizedDescription
                    )
                }
                completion?()
            }
        }
    }

    private func uploadRecording(url: URL, completion: (() -> Void)? = nil) {
        let toast = makeStatusToast()
        toast.show(status: L("Uploading..."))

        let provider = UploadProvider.current

        if let readinessError = provider.readinessErrorText {
            toast.showError(message: readinessError)
            completion?()
            return
        }
        guard provider.supportsVideo else {
            toast.showError(message: L("Video upload requires Google Drive, S3, or CloudFlare ImgBed"))
            completion?()
            return
        }

        let providerKey = provider.rawValue
        let completionHandler: (Result<String, Error>) -> Void = { result in
            switch result {
            case .success(let link):
                PasteboardWriter.writeString(link)
                UploadHistoryStore.append(link: link, provider: providerKey)
                toast.showSuccess(link: link, deleteURL: "")
            case .failure(let error):
                toast.showError(message: error.localizedDescription)
            }
            completion?()
        }

        switch provider {
        case .s3:
            S3Uploader.shared.uploadVideo(url: url, progress: nil, completion: completionHandler)
        case .cfimgbed:
            let progressHandler: (Double) -> Void = { fraction in
                toast.updateProgress(fraction)
            }
            CloudflareImgBedUploader.shared.uploadVideo(url: url, progress: progressHandler, completion: completionHandler)
        case .gdrive:
            let progressHandler: (Double) -> Void = { fraction in
                toast.updateProgress(fraction)
            }
            GoogleDriveUploader.shared.uploadVideo(url: url, progress: progressHandler, completion: completionHandler)
        case .imgbb:
            // Unreachable: supportsVideo is false for imgbb, guarded above.
            completion?()
        }
    }

    private func copyRecordingToClipboard(url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let ext = url.pathExtension.lowercased()
        if ext == "gif", let data = try? Data(contentsOf: url) {
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            item.setString(url.absoluteString, forType: .fileURL)
            pasteboard.writeObjects([item])
        } else {
            pasteboard.writeObjects([url as NSURL])
        }
    }

    private func openVideoEditor(for url: URL) {
        VideoEditorWindowController.open(url: url) { [weak self] in
            self?.releaseRecordingSource(url)
        }
    }

    private func retainRecordingSource(_ url: URL) {
        guard TemporaryFileManager.isManagedTemporaryFile(url) else { return }
        recordingSourceRetainCounts[url, default: 0] += 1
    }

    private func releaseRecordingSource(_ url: URL) {
        guard TemporaryFileManager.isManagedTemporaryFile(url) else { return }
        let nextCount = (recordingSourceRetainCounts[url] ?? 0) - 1
        if nextCount <= 0 {
            recordingSourceRetainCounts.removeValue(forKey: url)
            TemporaryFileManager.removeTemporaryFile(at: url)
        } else {
            recordingSourceRetainCounts[url] = nextCount
        }
    }

    /// Show a non-blocking toast when recording failed (e.g. SCStream stopped with an
    /// error mid-capture). Previously the error branch only logged in DEBUG and the
    /// user got zero feedback — appearing as if the recording simply vanished.
    private func showRecordingFailureToast(_ error: Error) {
        let toast = makeStatusToast()
        let message = error.localizedDescription.isEmpty
            ? L("Recording failed")
            : error.localizedDescription
        toast.showError(message: message)
    }
}
