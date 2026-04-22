import Cocoa
import CoreImage
import UniformTypeIdentifiers
import Vision

/// Editable annotation data bundled with a confirmed capture.
struct CaptureAnnotationData {
    let rawImage: NSImage       // screenshot without annotations
    let annotations: [Annotation]
}

enum CaptureCompletionContext {
    case standard
    case manualSave
}

@MainActor
protocol OverlayWindowControllerDelegate: AnyObject {
    func overlayDidCancel(_ controller: OverlayWindowController)
    func overlayDidConfirm(
        _ controller: OverlayWindowController,
        capturedImage: NSImage?,
        annotationData: CaptureAnnotationData?,
        context: CaptureCompletionContext,
        windowTitle: String?,
        pinOrigin: NSPoint?
    )
    func overlayDidRequestPin(_ controller: OverlayWindowController, image: NSImage, at globalOrigin: NSPoint)
    func overlayDidStartOCR(_ controller: OverlayWindowController)
    func overlayDidFinishOCR(_ controller: OverlayWindowController, text: String)
    func overlayDidRequestUpload(_ controller: OverlayWindowController, image: NSImage)
    func overlayDidRequestStartRecording(
        _ controller: OverlayWindowController, rect: NSRect, screen: NSScreen)
    func overlayDidRequestStopRecording(_ controller: OverlayWindowController)
    func overlayDidRequestScrollCapture(
        _ controller: OverlayWindowController, rect: NSRect, screen: NSScreen)
    func overlayDidRequestStopScrollCapture(_ controller: OverlayWindowController)
    func overlayDidRequestToggleAutoScroll(_ controller: OverlayWindowController)
    func overlayDidRequestAccessibilityPermission(_ controller: OverlayWindowController)
    func overlayDidRequestInputMonitoringPermission(_ controller: OverlayWindowController)
    func overlayDidBeginSelection(_ controller: OverlayWindowController)
    func overlayDidChangeSelection(_ controller: OverlayWindowController, globalRect: NSRect)
    func overlayDidRemoteResizeSelection(_ controller: OverlayWindowController, globalRect: NSRect)
    func overlayDidFinishRemoteResize(_ controller: OverlayWindowController, globalRect: NSRect)
    func overlayCrossScreenImage(_ controller: OverlayWindowController) -> NSImage?
    func overlayDidChangeWindowSnapState(_ controller: OverlayWindowController)
    func overlayDidChangeAspectRatioLock(_ controller: OverlayWindowController)
    func overlayDidChangeMouseLocation(_ controller: OverlayWindowController)
    func overlayViewDidShowHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    )
    func overlayViewDidShowError(message: String)
}

/// Manages one fullscreen overlay per screen.
/// Does NOT subclass NSWindowController to avoid AppKit retain-cycle issues.
@MainActor
class OverlayWindowController {

    weak var overlayDelegate: OverlayWindowControllerDelegate?
    var capturedWindowTitle: String?

    private var overlayView: OverlayView?
    private var overlayWindow: OverlayWindow?
    private var shareDelegate: SharePickerDelegate?
    var onFirstFrameShown: (() -> Void)?
    private var captureAsset: CaptureImageAsset?
    private var shareDismissTime: Date = .distantPast
    var windowNumber: CGWindowID {
        overlayWindow.map { CGWindowID($0.windowNumber) } ?? CGWindowID.max
    }
    private(set) var screen: NSScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    var screenshotImage: NSImage? { overlayView?.screenshotImage }
    var selectionRect: NSRect { overlayView?.selectionRect ?? .zero }
    var remoteSelectionRect: NSRect { overlayView?.remoteSelectionRect ?? .zero }

    // Session recording overrides (from toolbar popover, nil = use UserDefaults default)
    var sessionRecordingFPS: Int? { overlayView?.sessionRecordingFPS }
    var sessionRecordingOnStop: String? { overlayView?.sessionRecordingOnStop }
    var sessionRecordingDelay: Int? { overlayView?.sessionRecordingDelay }
    var sessionRecordingControlsMode: String? { overlayView?.sessionRecordingControlsMode }

    init(capture: ScreenCapture) {
        let t0 = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        NSLog("[PERF] OverlayWindowController.init BEGIN for screen=\(capture.screen.localizedName)")
        #endif
        let screen = capture.screen
        self.screen = screen

        let windowT0 = CFAbsoluteTimeGetCurrent()
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(257)  // above modal panels, alerts, and security popups
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        #if DEBUG
        NSLog("[PERF] OverlayWindowController.init: window created elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - windowT0) * 1000))ms")
        #endif

        let viewT0 = CFAbsoluteTimeGetCurrent()
        let view = OverlayView()
        #if DEBUG
        NSLog("[PERF] OverlayWindowController.init: OverlayView created elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - viewT0) * 1000))ms")
        #endif
        let nsImage = capture.asset.displayImage
        view.screenshotImage = nsImage
        view.setDisplayCGImage(capture.asset.displayCGImage)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        view.overlayDelegate = self

        window.contentView = view
        self.overlayWindow = window
        self.overlayView = view
        self.captureAsset = capture.asset
        view.onFirstFrameDrawn = { [weak self] in
            #if DEBUG
            NSLog("[PERF] OverlayWindowController: onFirstFrameDrawn callback for screen=\(self?.screen.localizedName ?? "unknown")")
            #endif
            self?.onFirstFrameShown?()
            self?.onFirstFrameShown = nil
        }
        #if DEBUG
        NSLog("[PERF] OverlayWindowController.init DONE total=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        #endif
    }

    func showOverlay() {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let window = overlayWindow else { return }
        #if DEBUG
        NSLog("[PERF] showOverlay: BEGIN for screen=\(screen.localizedName)")
        #endif
        // Show immediately; do not call displayIfNeeded() here — it blocks the main thread
        // until the full frame is rendered and makes the hotkey→drag path feel sluggish.
        overlayView?.needsDisplay = true

        // Prepare color sampling image BEFORE showing the window to avoid blocking first frame
        prepareCaptureImageInBackground()

        let makeKeyT0 = CFAbsoluteTimeGetCurrent()
        window.makeKeyAndOrderFront(nil)
        #if DEBUG
        NSLog("[PERF] showOverlay: makeKeyAndOrderFront DONE elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms (makeKeyAndOrderFront=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - makeKeyT0) * 1000))ms)")
        #endif
        if let view = overlayView {
            window.makeFirstResponder(view)
        }
        // Color sampling image is now prepared in background before window show
    }

    func makeKey() {
        overlayWindow?.makeKeyAndOrderFront(nil)
        if let view = overlayView {
            overlayWindow?.makeFirstResponder(view)
        }
    }

    private func prepareCaptureImageInBackground() {
        guard let captureAsset else { return }
        guard CaptureImageAsset.needsStandardizedColorImage(
            bitsPerComponent: captureAsset.displayCGImage.bitsPerComponent
        ) else {
            overlayView?.setColorSamplingCGImage(captureAsset.displayCGImage)
            return
        }
        // Start conversion immediately in background without waiting
        captureAsset.preloadColorSamplingImage { [weak self] converted in
            self?.overlayView?.setColorSamplingCGImage(converted)
        }
    }

    func applySelection(_ rect: NSRect, restoredFromMemory: Bool = false) {
        overlayView?.applySelection(rect, restoredFromMemory: restoredFromMemory)
    }

    func clearSelection() {
        overlayView?.clearSelection()
    }

    func triggerRedraw() {
        overlayView?.needsDisplay = true
    }

    func syncAspectRatioHintFrom(_ source: OverlayWindowController) {
        source.overlayView?.getAspectRatioHintState { opacity, isCancelling, lock in
            overlayView?.syncAspectRatioHint(opacity: opacity, isCancelling: isCancelling, lock: lock)
        }
    }

    func syncOverlayHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {
        overlayView?.syncOverlayHint(
            message: message,
            opacity: opacity,
            colorString: colorString,
            attributedString: attributedString
        )
    }

    func syncOverlayError(message: String) {
        overlayView?.syncOverlayError(message: message)
    }

    func setRemoteSelection(_ rect: NSRect, fullRect: NSRect = .zero) {
        overlayView?.remoteSelectionRect = rect
        overlayView?.remoteSelectionFullRect = fullRect.width >= 1 ? fullRect : rect
        if rect.width >= 1 && rect.height >= 1 {
            overlayView?.hoveredWindowRect = nil
        }
        overlayView?.needsDisplay = true
    }

    /// Auto-select the full screen (as if user clicked without dragging).
    func applyFullScreenSelection() {
        overlayView?.applyFullScreenSelection()
    }

    /// Set flag so overlay enters recording mode after user makes a selection.
    func setAutoRecordMode() {
        overlayView?.autoEnterRecordingMode = true
    }

    /// Set flag so overlay triggers OCR immediately after user makes a selection.
    func setAutoOCRMode() {
        overlayView?.autoOCRMode = true
    }

    /// Set flag so overlay quick-saves immediately after user makes a selection.
    func setAutoQuickSaveMode() {
        overlayView?.autoQuickSaveMode = true
    }

    /// Set flag so overlay triggers scroll capture immediately after user makes a selection.
    func setAutoScrollCaptureMode() {
        overlayView?.autoScrollCaptureMode = true
    }

    /// Set flag so overlay auto-confirms immediately after selection (no toolbars, no save).
    func setAutoConfirmMode() {
        overlayView?.autoConfirmMode = true
    }

    /// Enter recording mode — shows recording toolbar buttons in the normal toolbar.
    func enterRecordingMode() {
        overlayView?.isRecording = true
        overlayView?.rebuildToolbarLayout()
        overlayView?.needsDisplay = true
    }

    /// Auto-start recording immediately (used when timer + fullscreen record).
    func autoStartRecording() {
        overlayView?.overlayDelegate?.overlayViewDidRequestStartRecording(
            rect: overlayView?.selectionRect ?? .zero)
    }

    func setScrollCaptureState(isActive: Bool, stripCount: Int = 0, pixelSize: CGSize = .zero,
                               maxHeight: Int = 0) {
        overlayView?.scrollCaptureMaxHeight = maxHeight
        if isActive {
            overlayView?.startScrollCaptureMode()
        } else {
            overlayView?.stopScrollCaptureMode()
        }
        overlayView?.scrollCaptureStripCount = stripCount
        overlayView?.scrollCapturePixelSize = pixelSize
        overlayView?.needsDisplay = true
    }

    func updateScrollCaptureProgress(stripCount: Int, pixelSize: CGSize,
                                     autoScrolling: Bool = false) {
        overlayView?.scrollCaptureStripCount = stripCount
        overlayView?.scrollCapturePixelSize = pixelSize
        overlayView?.scrollCaptureAutoScrolling = autoScrolling
        overlayView?.updateScrollCaptureHUD()
        overlayView?.needsDisplay = true
    }

    func dismiss() {
        saveSelectionIfNeeded()
        overlayView?.reset()
        overlayView?.screenshotImage = nil
        overlayView?.overlayDelegate = nil
        overlayWindow?.contentView = nil
        overlayView = nil
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
        NSCursor.arrow.set()
    }

    private func saveSelectionIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "rememberLastSelection"),
            let view = overlayView, view.state == .selected,
            view.selectionRect.width > 1, view.selectionRect.height > 1
        else { return }
        UserDefaults.standard.set(NSStringFromRect(view.selectionRect), forKey: "lastSelectionRect")
        UserDefaults.standard.set(
            NSStringFromRect(screen.frame), forKey: "lastSelectionScreenFrame")
    }

    private func playCopySound() {
        let soundEnabled = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        guard soundEnabled else { return }
        AppDelegate.captureSound?.stop()
        AppDelegate.captureSound?.play()
    }

    private func captureRegion() -> NSImage? {
        return overlayDelegate?.overlayCrossScreenImage(self)
            ?? overlayView?.captureSelectedRegion()
    }

    /// Snapshot annotations for editable history, using a pre-captured raw image.
    /// Returns nil if there are no movable annotations.
    private func snapshotAnnotationData(rawImage: NSImage) -> CaptureAnnotationData? {
        guard let view = overlayView else { return nil }
        let annotations = view.annotations.filter { $0.isMovable }
        guard !annotations.isEmpty else { return nil }

        let sel = view.selectionRect
        let shifted = annotations.map { ann -> Annotation in
            let c = ann.clone()
            c.move(dx: -sel.origin.x, dy: -sel.origin.y)
            return c
        }
        return CaptureAnnotationData(rawImage: rawImage, annotations: shifted)
    }

    /// Composite annotations onto the snapped window image (preserving transparency).
    private func compositeAnnotationsOnSnappedWindow(_ windowImage: NSImage, annotations: [Annotation], selectionRect: NSRect) -> NSImage {
        guard !annotations.isEmpty else { return windowImage }
        let sel = selectionRect
        let size = windowImage.size
        let result = NSImage(size: size, flipped: false) { _ in
            windowImage.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
            guard let ctx = NSGraphicsContext.current else { return true }
            // Translate so annotation coords (relative to selectionRect) map to image coords
            ctx.cgContext.translateBy(x: -sel.origin.x, y: -sel.origin.y)
            for annotation in annotations {
                annotation.draw(in: ctx)
            }
            return true
        }
        return result
    }

    private func applyBeautifyIfNeeded(_ image: NSImage?) -> NSImage? {
        guard let image = image, let view = overlayView else { return image }
        var result = image
        // Apply image effects first (non-destructive CIFilter adjustments)
        if view.effectsActive {
            result = ImageEffects.apply(to: result, config: view.effectsConfig)
        }
        // Apply beautify second (gradient background wrapping)
        if view.beautifyEnabled {
            result = BeautifyRenderer.render(image: result, config: view.beautifyConfig)
        }
        return result
    }

    private func copyImageToClipboard(_ image: NSImage) {
        ImageEncoder.copyToClipboard(image)
    }

    func selectionPinOrigin() -> NSPoint? {
        guard let win = overlayWindow else { return nil }
        let selRect = overlayView?.selectionRect ?? .zero
        guard selRect.width > 0, selRect.height > 0 else { return nil }
        return win.convertToScreen(selRect).origin
    }

    static func formattedTimestamp() -> String {
        return FilenameTemplateEngine.makeBaseName(kind: .screenshot)
    }
}

// MARK: - OverlayViewDelegate

extension OverlayWindowController: OverlayViewDelegate {
    func overlayViewDidFinishSelection(_ rect: NSRect) {
    }

    func overlayViewSelectionDidChange(_ rect: NSRect) {
        let screenOrigin = screen.frame.origin
        let globalRect = NSRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width, height: rect.height)
        overlayDelegate?.overlayDidChangeSelection(self, globalRect: globalRect)
    }

    func overlayViewDidCancel() {
        dismiss()
        overlayDelegate?.overlayDidCancel(self)
    }

    func overlayViewDidConfirm() {
        // Snapshot post-processing config before dismissing (view will be torn down)
        let hasEffects = overlayView?.effectsActive ?? false
        let effectsCfg = overlayView?.effectsConfig ?? ImageEffectsConfig()
        let hasBeautify = overlayView?.beautifyEnabled ?? false
        let beautifyCfg = overlayView?.beautifyConfig ?? BeautifyConfig()
        let snapWindowImg = overlayView?.snappedWindowImage

        // Capture the composited image (screenshot + annotations baked in).
        // This is a single render — no double capture.
        guard let compositedImage = captureRegion() else {
            dismiss()
            overlayDelegate?.overlayDidCancel(self)
            return
        }

        // Snapshot annotations + selection rect before dismiss (view will be torn down)
        let snapshotAnnotations = overlayView?.annotations ?? []
        let snapshotSelRect = overlayView?.selectionRect ?? .zero

        // Snapshot annotation data using the raw screenshot (without annotations).
        // For window snaps, use the independently captured window image (transparent corners)
        // so the editor shows clean corners when re-editing.
        let hasAnnotations = overlayView?.annotations.contains(where: { $0.isMovable }) ?? false
        let annotationData: CaptureAnnotationData?
        if hasAnnotations {
            let rawImage: NSImage? = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? snapWindowImg : overlayView?.captureSelectedRegionRaw()
            if let raw = rawImage {
                annotationData = snapshotAnnotationData(rawImage: raw)
            } else {
                annotationData = nil
            }
        } else {
            annotationData = nil
        }

        let pinOrigin = selectionPinOrigin()

        // Dismiss immediately — user is free to continue working
        dismiss()

        // Apply post-processing if needed
        var finalImage = compositedImage
        if hasEffects {
            finalImage = ImageEffects.apply(to: finalImage, config: effectsCfg)
        }
        if hasBeautify {
            // For snapped windows, use the independently captured window image (transparent corners)
            // with annotations composited on top (using pre-dismiss snapshot)
            let beautifyInput = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? compositeAnnotationsOnSnappedWindow(snapWindowImg!, annotations: snapshotAnnotations, selectionRect: snapshotSelRect)
                : finalImage
            finalImage = BeautifyRenderer.render(image: beautifyInput, config: beautifyCfg)
        }

        // Don't save annotation data if effects/beautify were applied — the raw image
        // wouldn't match what the user sees, making annotation re-editing confusing.
        overlayDelegate?.overlayDidConfirm(
            self,
            capturedImage: finalImage,
            annotationData: annotationData,
            context: .standard,
            windowTitle: capturedWindowTitle,
            pinOrigin: pinOrigin
        )
    }

    func overlayViewDidRequestPin() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image
        playCopySound()

        let globalOrigin = selectionPinOrigin() ?? .zero

        dismiss()
        overlayDelegate?.overlayDidRequestPin(self, image: image, at: globalOrigin)
    }

    func overlayViewDidRequestOCR() {
        guard let image = captureRegion() else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        playCopySound()
        overlayDelegate?.overlayDidStartOCR(self)

        let request = VisionOCR.makeTextRecognitionRequest { [self] request, error in
            var lines: [String] = []
            if let observations = request.results as? [VNRecognizedTextObservation] {
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        lines.append(candidate.string)
                    }
                }
            }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async {
                self.overlayDelegate?.overlayDidFinishOCR(self, text: text)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    func overlayViewDidRequestUpload() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image
        playCopySound()
        dismiss()
        overlayDelegate?.overlayDidRequestUpload(self, image: image)
    }

    func overlayViewDidRequestShare(anchorView: NSView?) {
        // Prevent re-entry: if a share session is active or was just dismissed, ignore
        if shareDelegate != nil { return }
        if Date().timeIntervalSince(shareDismissTime) < 0.5 {
            return
        }

        // 如果有其他popover打开，先关闭它
        if PopoverHelper.isVisible {
            PopoverHelper.dismiss()
            // 延迟打开共享面板，让旧的先完全关闭
            DispatchQueue.main.async { [weak self] in
                self?.overlayViewDidRequestShare(anchorView: anchorView)
            }
            return
        }

        // Performance diagnostics
        let startTime = Date()

        guard var image = captureRegion() else { return }
        let captureTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] captureRegion: \(String(format: "%.0f", captureTime * 1000))ms")
        #endif

        image = applyBeautifyIfNeeded(image) ?? image
        let beautifyTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] applyBeautifyIfNeeded: \(String(format: "%.0f", beautifyTime * 1000))ms (delta: \(String(format: "%.0f", (beautifyTime - captureTime) * 1000))ms)")
        #endif

        // Use PNG for sharing (fast encoding, WebP picture preset is too slow: 8+ seconds)
        // PNG encoding takes ~50-100ms vs WebP's 8+ seconds with picture preset
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        let encodeTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] PNG encode: \(String(format: "%.0f", encodeTime * 1000))ms (delta: \(String(format: "%.0f", (encodeTime - beautifyTime) * 1000))ms)")
        #endif

        let tempURL = FilenameTemplateEngine.uniqueDestinationURL(
            in: URL(fileURLWithPath: NSTemporaryDirectory()),
            baseName: FilenameTemplateEngine.makeBaseName(kind: .screenshot),
            fileExtension: "png"
        )
        try? pngData.write(to: tempURL)
        let writeTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] write to temp file: \(String(format: "%.0f", writeTime * 1000))ms (delta: \(String(format: "%.0f", (writeTime - encodeTime) * 1000))ms)")
        #endif
        #if DEBUG
        NSLog("[Share] Total preparation time: \(String(format: "%.0f", writeTime * 1000))ms")
        #endif

        // Get the screen position of the share button
        let screenRect: NSRect
        if let anchor = anchorView, let win = anchor.window {
            let viewRect = anchor.convert(anchor.bounds, to: nil)
            screenRect = win.convertToScreen(viewRect)
        } else {
            let mid = NSScreen.main?.frame ?? NSRect(x: 400, y: 400, width: 100, height: 100)
            screenRect = NSRect(x: mid.midX - 20, y: mid.midY - 20, width: 40, height: 40)
        }

        // Temporarily lower the overlay so the system share picker popover appears on top.
        // NSSharingServicePicker creates its own window at a standard level that we can't control.
        let savedLevel = overlayWindow?.level ?? NSWindow.Level(257)
        overlayWindow?.level = .floating

        let picker = NSSharingServicePicker(items: [tempURL])
        let delegate = SharePickerDelegate(
            onPick: { [weak self] in
                guard let self = self else { return }
                self.overlayWindow?.level = savedLevel
                self.shareDelegate = nil
                let img = image
                let pinOrigin = self.selectionPinOrigin()
                self.dismiss()
                self.overlayDelegate?.overlayDidConfirm(
                    self,
                    capturedImage: img,
                    annotationData: nil,
                    context: .standard,
                    windowTitle: self.capturedWindowTitle,
                    pinOrigin: pinOrigin
                )
            },
            onDismiss: { [weak self] in
                self?.overlayWindow?.level = savedLevel
                self?.shareDelegate = nil
                self?.shareDismissTime = Date()
            }
        )
        shareDelegate = delegate
        picker.delegate = delegate

        // Show anchored to the button in the overlay view
        // 使用侧边弹出方向，与包装和调色工具保持一致
        if let anchor = anchorView {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX)
        } else if let view = overlayView {
            let center = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: center, of: view, preferredEdge: .minX)
        }
    }

    func overlayViewDidRequestEnterRecordingMode() {
        enterRecordingMode()
    }

    func overlayViewDidRequestStartRecording(rect: NSRect) {
        // Convert overlay-local rect to screen coordinates
        let screenRect = NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        overlayDelegate?.overlayDidRequestStartRecording(self, rect: screenRect, screen: screen)
    }

    /// Detach the webcam setup preview so it can be reused during recording.
    func detachWebcamPreview() -> WebcamOverlay? {
        overlayView?.detachWebcamSetupPreview()
    }

    func overlayViewDidRequestStopRecording() {
        overlayDelegate?.overlayDidRequestStopRecording(self)
    }

    func overlayViewDidRequestScrollCapture(rect: NSRect) {
        let screenRect = NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        overlayDelegate?.overlayDidRequestScrollCapture(self, rect: screenRect, screen: screen)
    }

    func overlayViewDidRequestStopScrollCapture() {
        overlayDelegate?.overlayDidRequestStopScrollCapture(self)
    }

    func overlayViewDidRequestToggleAutoScroll() {
        overlayDelegate?.overlayDidRequestToggleAutoScroll(self)
    }

    func overlayViewDidRequestAccessibilityPermission() {
        overlayDelegate?.overlayDidRequestAccessibilityPermission(self)
    }

    func overlayViewDidRequestInputMonitoringPermission() {
        overlayDelegate?.overlayDidRequestInputMonitoringPermission(self)
    }

    func overlayViewDidBeginSelection() {
        overlayDelegate?.overlayDidBeginSelection(self)
    }

    func overlayViewDidChangeWindowSnapState() {
        overlayDelegate?.overlayDidChangeWindowSnapState(self)
    }

    func overlayViewDidChangeAspectRatioLock() {
        overlayDelegate?.overlayDidChangeAspectRatioLock(self)
    }

    func overlayViewDidChangeMouseLocation() {
        overlayDelegate?.overlayDidChangeMouseLocation(self)
    }

    func overlayViewDidRequestAddCapture() {}  // editor-only

    func overlayViewRemoteSelectionDidChange(_ rect: NSRect) {
        // Convert local rect to global screen coords and forward to delegate
        let screenOrigin = screen.frame.origin
        let globalRect = NSRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width, height: rect.height)
        overlayDelegate?.overlayDidRemoteResizeSelection(self, globalRect: globalRect)
    }

    func overlayViewRemoteSelectionDidFinish(_ rect: NSRect) {
        let screenOrigin = screen.frame.origin
        let globalRect = NSRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width, height: rect.height)
        overlayDelegate?.overlayDidFinishRemoteResize(self, globalRect: globalRect)
    }

    func overlayViewDidRequestDetach() {
        guard let view = overlayView else { return }
        let sel = view.selectionRect

        // Use stitched cross-screen image if available, otherwise crop from single screen.
        let croppedImage: NSImage? =
            overlayDelegate?.overlayCrossScreenImage(self)
            ?? {
                guard let src = view.screenshotImage,
                      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                // Pixel-perfect crop via CGImage.cropping() — no color space
                // conversion, no draw pipeline, just a sub-image reference.
                let scale = view.window?.backingScaleFactor ?? 2.0
                let imgH = CGFloat(srcCG.height) / scale
                // CGImage uses top-left origin; sel is in AppKit bottom-left coords.
                let cropRect = CGRect(
                    x: sel.origin.x * scale,
                    y: (imgH - sel.origin.y - sel.height) * scale,
                    width: sel.width * scale,
                    height: sel.height * scale)
                guard let cropped = srcCG.cropping(to: cropRect) else { return nil }
                return NSImage(cgImage: cropped, size: sel.size)
            }()
        guard let image = croppedImage else { return }

        // Clone annotations and shift them from overlay coords to image-relative (0,0) origin.
        let state = view.snapshotEditorState()
        let shiftedAnnotations = state.annotations.map { ann -> Annotation in
            let c = ann.clone()
            c.move(dx: -sel.origin.x, dy: -sel.origin.y)
            return c
        }

        let tool = view.currentTool
        let color = view.currentColor
        let stroke = view.currentStrokeWidth

        dismiss()
        overlayDelegate?.overlayDidCancel(self)
        DetachedEditorWindowController.open(
            image: image, tool: tool, color: color, strokeWidth: stroke,
            annotations: shiftedAnnotations, fromCapture: true)
    }

    @available(macOS 14.0, *)
    func overlayViewDidRequestRemoveBackground() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                guard let result = request.results?.first else {
                    throw NSError(domain: "Macshot", code: 1)
                }

                let maskPixelBuffer = try result.generateScaledMaskForImage(
                    forInstances: result.allInstances, from: handler)

                let originalCIImage = CIImage(cgImage: cgImage)
                let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)

                // Blend original with mask
                guard let filter = CIFilter(name: "CIBlendWithMask") else {
                    throw NSError(domain: "Macshot", code: 2)
                }
                filter.setValue(originalCIImage, forKey: kCIInputImageKey)
                filter.setValue(maskCIImage, forKey: kCIInputMaskImageKey)
                filter.setValue(
                    CIImage(color: .clear).cropped(to: originalCIImage.extent),
                    forKey: kCIInputBackgroundImageKey)

                guard let outputCIImage = filter.outputImage else {
                    throw NSError(domain: "Macshot", code: 3)
                }

                let context = BeautifyRenderer.sharedCIContext
                guard
                    let finalCGImage = context.createCGImage(
                        outputCIImage, from: outputCIImage.extent)
                else { throw NSError(domain: "Macshot", code: 4) }

                let finalNSImage = NSImage(cgImage: finalCGImage, size: image.size)

                DispatchQueue.main.async {
                    let pinOrigin = self.selectionPinOrigin()
                    self.dismiss()
                    self.overlayDelegate?.overlayDidConfirm(
                        self,
                        capturedImage: finalNSImage,
                        annotationData: nil,
                        context: .standard,
                        windowTitle: self.capturedWindowTitle,
                        pinOrigin: pinOrigin
                    )
                }
            } catch {
                #if DEBUG
                    print("Vision background removal error: \(error.localizedDescription)")
                #endif
                DispatchQueue.main.async {
                    self.overlayView?.showOverlayError(
                        "Background removal failed — no clear subject found.")
                }
            }
        }
    }

    func overlayViewDidRequestQuickSave() {
        // Snapshot post-processing config before dismissing
        let hasEffects = overlayView?.effectsActive ?? false
        let effectsCfg = overlayView?.effectsConfig ?? ImageEffectsConfig()
        let hasBeautify = overlayView?.beautifyEnabled ?? false
        let beautifyCfg = overlayView?.beautifyConfig ?? BeautifyConfig()
        let snapWindowImg = overlayView?.snappedWindowImage

        guard let compositedImage = captureRegion() else {
            dismiss()
            overlayDelegate?.overlayDidCancel(self)
            return
        }

        // Snapshot annotations + selection rect before dismiss
        let snapshotAnns = overlayView?.annotations ?? []
        let snapshotSel = overlayView?.selectionRect ?? .zero

        // Snapshot annotation data — use snapped window image for clean corners
        let hasAnnotations = overlayView?.annotations.contains(where: { $0.isMovable }) ?? false
        let annotationData: CaptureAnnotationData?
        if hasAnnotations {
            let rawImage: NSImage? = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? snapWindowImg : overlayView?.captureSelectedRegionRaw()
            if let raw = rawImage {
                annotationData = snapshotAnnotationData(rawImage: raw)
            } else {
                annotationData = nil
            }
        } else {
            annotationData = nil
        }

        dismiss()

        // Apply post-processing
        var image = compositedImage
        if hasEffects { image = ImageEffects.apply(to: image, config: effectsCfg) }
        if hasBeautify {
            let beautifyInput = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? compositeAnnotationsOnSnappedWindow(snapWindowImg!, annotations: snapshotAnns, selectionRect: snapshotSel)
                : image
            image = BeautifyRenderer.render(image: beautifyInput, config: beautifyCfg)
        }

        let pinOrigin = selectionPinOrigin()
        overlayDelegate?.overlayDidConfirm(
            self,
            capturedImage: image,
            annotationData: annotationData,
            context: .standard,
            windowTitle: capturedWindowTitle,
            pinOrigin: pinOrigin
        )
    }

    func overlayViewDidRequestFileSave() {
        // Snapshot post-processing config before saving. Keep the overlay alive
        // until the centered hint has been shown, otherwise the user never sees it.
        let hasEffects = overlayView?.effectsActive ?? false
        let effectsCfg = overlayView?.effectsConfig ?? ImageEffectsConfig()
        let hasBeautify = overlayView?.beautifyEnabled ?? false
        let beautifyCfg = overlayView?.beautifyConfig ?? BeautifyConfig()
        let snapWindowImg = overlayView?.snappedWindowImage
        let snapshotAnns = overlayView?.annotations ?? []
        let snapshotSel = overlayView?.selectionRect ?? .zero

        guard let rawImage = captureRegion() else {
            dismiss()
            overlayDelegate?.overlayDidCancel(self)
            return
        }

        // Apply post-processing
        var image = rawImage
        if hasEffects { image = ImageEffects.apply(to: image, config: effectsCfg) }
        if hasBeautify {
            let beautifyInput = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? compositeAnnotationsOnSnappedWindow(snapWindowImg!, annotations: snapshotAnns, selectionRect: snapshotSel)
                : image
            image = BeautifyRenderer.render(image: beautifyInput, config: beautifyCfg)
        }

        let pinOrigin = selectionPinOrigin()
        saveImageToDirectory(image) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let fileURL):
                self.playCopySound()
                self.overlayView?.showOverlayHint(
                    String(format: L("Saved to %@"), fileURL.lastPathComponent))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.overlayDelegate?.overlayDidConfirm(
                        self,
                        capturedImage: image,
                        annotationData: nil,
                        context: .manualSave,
                        windowTitle: self.capturedWindowTitle,
                        pinOrigin: pinOrigin
                    )
                }
            case .failure:
                self.overlayView?.showOverlayError(L("Save failed"))
            }
        }
    }

    private func saveImageToDirectory(
        _ image: NSImage,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        // 使用统一的 ImageSaveService
        ImageSaveService.saveToDefaultDirectoryAsync(image, kind: .screenshot, completion: completion)
    }

    func overlayViewDidRequestSave() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image
        guard let imageData = ImageEncoder.encode(image) else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [ImageEncoder.utType]
        savePanel.nameFieldStringValue = FilenameTemplateEngine.makeFilename(
            kind: .screenshot,
            fileExtension: ImageEncoder.fileExtension
        )
        savePanel.level = NSWindow.Level(258)

        savePanel.directoryURL = SaveDirectoryAccess.directoryHint()
        let pinOrigin = selectionPinOrigin()
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = savePanel.url {
                try? imageData.write(to: url)
                SaveDirectoryAccess.save(url: url.deletingLastPathComponent())
                self.playCopySound()
                self.dismiss()
                self.overlayDelegate?.overlayDidConfirm(
                    self,
                    capturedImage: nil,
                    annotationData: nil,
                    context: .manualSave,
                    windowTitle: self.capturedWindowTitle,
                    pinOrigin: pinOrigin
                )
            } else {
                self.overlayWindow?.makeKeyAndOrderFront(nil)
                if let view = self.overlayView {
                    self.overlayWindow?.makeFirstResponder(view)
                }
            }
        }
    }

    func overlayViewDidShowHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {
        // Broadcast hint state to all other screens
        overlayDelegate?.overlayViewDidShowHint(
            message: message,
            opacity: opacity,
            colorString: colorString,
            attributedString: attributedString
        )
    }

    func overlayViewDidShowError(message: String) {
        // Broadcast error state to all other screens
        overlayDelegate?.overlayViewDidShowError(message: message)
    }
}

// MARK: - Custom Window subclass

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var autorecalculatesKeyViewLoop: Bool {
        get { false }
        set { }
    }

    /// Tags on `OverlayView` inline numeric `NSTextField`s (zoom). Field editor stays transparent so rounded pills drawn in `OverlayView` remain visible.
    private static let overlayInlineNumericFieldTags: Set<Int> = [889]

    override func fieldEditor(_ createFlag: Bool, for obj: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: obj)
        guard let textView = editor as? NSTextView,
              let field = obj as? NSTextField,
              Self.overlayInlineNumericFieldTags.contains(field.tag)
        else { return editor }

        let font =
            field.font
            ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        // Transparent so `OverlayView.drawSizeLabel` / `drawZoomLabel` rounded pills stay visible; opaque editor would hide corner radius and look taller.
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.white.withAlphaComponent(0.35),
            .foregroundColor: NSColor.white,
        ]
        return editor
    }
}

/// Retained delegate for NSSharingServicePicker — dismisses overlay only when user picks a service.
private class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    let onPick: () -> Void
    let onDismiss: () -> Void
    init(onPick: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onPick = onPick
        self.onDismiss = onDismiss
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        if service != nil {
            onPick()
        } else {
            onDismiss()
        }
    }
}
