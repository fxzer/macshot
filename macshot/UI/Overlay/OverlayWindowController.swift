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

    func playCopySound() {
        let soundEnabled = UserDefaults.standard.object(forKey: "playCopySound") as? Bool ?? true
        guard soundEnabled else { return }
        AppDelegate.captureSound?.stop()
        AppDelegate.captureSound?.play()
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
