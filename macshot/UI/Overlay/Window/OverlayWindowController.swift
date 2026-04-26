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

    var backgroundRemovalToken: BackgroundRemovalProcessor.CancellationToken?
    var overlayView: OverlayView?
    var overlayWindow: OverlayWindow?
    var shareDelegate: SharePickerDelegate?
    var onFirstFrameShown: (() -> Void)?
    var captureAsset: CaptureImageAsset?
    var shareDismissTime: Date = .distantPast
    var windowNumber: CGWindowID {
        overlayWindow.map { CGWindowID($0.windowNumber) } ?? CGWindowID.max
    }
    var screen: NSScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    var screenshotImage: NSImage? { overlayView?.screenshotImage }
    var selectionRect: NSRect { overlayView?.selectionRect ?? .zero }
    var remoteSelectionRect: NSRect { overlayView?.remoteSelectionRect ?? .zero }

    // Session recording overrides (from toolbar popover, nil = use UserDefaults default)
    var sessionRecordingFPS: Int? { overlayView?.sessionRecordingFPS }
    var sessionRecordingOnStop: String? { overlayView?.sessionRecordingOnStop }
    var sessionRecordingDelay: Int? { overlayView?.sessionRecordingDelay }
    var sessionRecordingControlsMode: String? { overlayView?.sessionRecordingControlsMode }

    init(screen: NSScreen) {
        var perf = PerfMonitor(label: "OWC.init[\(screen.localizedName)]")
        self.screen = screen

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
        perf.step("window")

        let view = OverlayView()
        perf.step("OverlayView()")

        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        view.overlayDelegate = self

        window.contentView = view
        self.overlayWindow = window
        self.overlayView = view
        view.onFirstFrameDrawn = { [weak self] in
            CaptureDiagnostics.log("[macshot-perf][OWC.init] onFirstFrameDrawn screen=\(self?.screen.localizedName ?? "?")")
            self?.onFirstFrameShown?()
            self?.onFirstFrameShown = nil
        }
        perf.finish()
    }

    convenience init(capture: ScreenCapture) {
        self.init(screen: capture.screen)
        applyCapture(capture)
    }

    func applyCapture(_ capture: ScreenCapture) {
        screen = capture.screen
        captureAsset = capture.asset

        let nsImage = capture.asset.displayImage
        CaptureDiagnostics.log(
            "[macshot-perf][OWC.capture] apply displayImage \(String(format: "%.0f", nsImage.size.width))x\(String(format: "%.0f", nsImage.size.height))"
        )
        overlayView?.screenshotImage = nsImage
        overlayView?.setDisplayCGImage(capture.asset.displayCGImage)
        overlayView?.needsDisplay = true

        if overlayWindow?.isVisible == true {
            prepareCaptureImageInBackground()
        }
    }

    func showOverlay() {
        var perf = PerfMonitor(label: "showOverlay[\(screen.localizedName)]")
        guard let window = overlayWindow else { return }
        // Show immediately; do not call displayIfNeeded() here — it blocks the main thread
        // until the full frame is rendered and makes the hotkey→drag path feel sluggish.
        overlayView?.needsDisplay = true

        // Prepare color sampling image BEFORE showing the window to avoid blocking first frame
        prepareCaptureImageInBackground()
        perf.step("prepareCaptureImage")

        presentWindow(window)
        perf.step("presentWindow")
        perf.finish()
    }

    func makeKey() {
        promoteWindowToKeyWhenReady()
    }

    func prepareCaptureImageInBackground() {
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

    private func presentWindow(_ window: OverlayWindow) {
        if NSApp.isActive {
            promoteWindowToKey(window)
            return
        }

        window.orderFrontRegardless()
        promoteWindowToKeyWhenReady()
    }

    private func promoteWindowToKeyWhenReady(attempt: Int = 0) {
        guard let window = overlayWindow else { return }
        if NSApp.isActive {
            promoteWindowToKey(window)
            return
        }

        if attempt == 0 {
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        }

        guard attempt < 12 else {
            promoteWindowToKey(window)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.promoteWindowToKeyWhenReady(attempt: attempt + 1)
        }
    }

    private func promoteWindowToKey(_ window: OverlayWindow) {
        window.makeKeyAndOrderFront(nil)
        if let view = overlayView {
            window.makeFirstResponder(view)
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
        backgroundRemovalToken?.cancel()
        backgroundRemovalToken = nil
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

    func saveSelectionIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "rememberLastSelection"),
            let view = overlayView, view.state == .selected,
            view.selectionRect.width > 1, view.selectionRect.height > 1
        else { return }
        UserDefaults.standard.set(NSStringFromRect(view.selectionRect), forKey: "lastSelectionRect")
        UserDefaults.standard.set(
            NSStringFromRect(screen.frame), forKey: "lastSelectionScreenFrame")
    }

    func captureRegion() -> NSImage? {
        return overlayDelegate?.overlayCrossScreenImage(self)
            ?? overlayView?.captureSelectedRegion()
    }

    /// Snapshot annotations for editable history, using a pre-captured raw image.
    /// Returns nil if there are no movable annotations.
    func snapshotAnnotationData(rawImage: NSImage) -> CaptureAnnotationData? {
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
    func compositeAnnotationsOnSnappedWindow(_ windowImage: NSImage, annotations: [Annotation], selectionRect: NSRect) -> NSImage {
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

    func applyBeautifyIfNeeded(_ image: NSImage?) -> NSImage? {
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

    func copyImageToClipboard(_ image: NSImage) {
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
