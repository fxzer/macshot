import AppKit

final class OverlayCaptureSessionState {
    var suppressBackdropUntilCapture = false
    var isRecording = false
    var autoEnterRecordingMode = false
    var autoOCRMode = false
    var autoQuickSaveMode = false
    var autoScrollCaptureMode = false
    var autoConfirmMode = false
    var sessionRecordingFPS: Int?
    var sessionRecordingOnStop: String?
    var sessionRecordingDelay: Int?
    var sessionRecordingControlsMode: String?
    var isScrollCapturing = false
    var scrollCaptureStripCount = 0
    var scrollCapturePixelSize: CGSize = .zero
    var scrollCaptureMaxHeight = 0
    var scrollCaptureAutoScrolling = false
    var scrollCaptureHUDPanel: ScrollCaptureHUDPanel?
    var scrollCaptureMouseTap: CFMachPort?
    var scrollCaptureMouseTapSource: CFRunLoopSource?
    var scrollCaptureKeyMonitor: Any?
    var scrollCaptureLocalKeyMonitor: Any?
    var windowSnapEnabled =
        UserDefaults.standard.object(forKey: "windowSnapEnabled") as? Bool ?? true
    var hoveredWindowRect: NSRect?
    var hoveredWindowID: CGWindowID?
    var windowSnapCooldown = true
    var selectionIsWindowSnap = false
    var snappedWindowID: CGWindowID?
    var snappedWindowImage: NSImage?
    var windowSnapQueryInFlight = false
}

extension OverlayView {
    var suppressBackdropUntilCapture: Bool {
        get { captureSessionState.suppressBackdropUntilCapture }
        set { captureSessionState.suppressBackdropUntilCapture = newValue }
    }

    var isRecording: Bool {
        get { captureSessionState.isRecording }
        set {
            let oldValue = captureSessionState.isRecording
            captureSessionState.isRecording = newValue
            guard newValue != oldValue else { return }
            if newValue {
                commitTextFieldIfNeeded()
                stampPreviewPoint = nil
                loupeCursorPoint = .zero
                drawingCursorPoint = .zero
                autoMeasurePreview = nil
                hoveredAnnotation = nil
                selectedAnnotation = nil
                needsDisplay = true
                if UserDefaults.standard.bool(forKey: "recordKeystroke")
                    && !KeystrokeOverlay.hasInputMonitoringPermission
                {
                    UserDefaults.standard.set(false, forKey: "recordKeystroke")
                    rebuildToolbarLayout()
                    overlayDelegate?.overlayViewDidRequestInputMonitoringPermission()
                }
                preCheckRecordingPermissions()
            } else {
                stopMicLevelMonitor()
                dismissWebcamSetupPreview()
            }
        }
    }

    var autoEnterRecordingMode: Bool {
        get { captureSessionState.autoEnterRecordingMode }
        set { captureSessionState.autoEnterRecordingMode = newValue }
    }

    var autoOCRMode: Bool {
        get { captureSessionState.autoOCRMode }
        set { captureSessionState.autoOCRMode = newValue }
    }

    var autoQuickSaveMode: Bool {
        get { captureSessionState.autoQuickSaveMode }
        set { captureSessionState.autoQuickSaveMode = newValue }
    }

    var autoScrollCaptureMode: Bool {
        get { captureSessionState.autoScrollCaptureMode }
        set { captureSessionState.autoScrollCaptureMode = newValue }
    }

    var autoConfirmMode: Bool {
        get { captureSessionState.autoConfirmMode }
        set { captureSessionState.autoConfirmMode = newValue }
    }

    var sessionRecordingFPS: Int? {
        get { captureSessionState.sessionRecordingFPS }
        set { captureSessionState.sessionRecordingFPS = newValue }
    }

    var sessionRecordingOnStop: String? {
        get { captureSessionState.sessionRecordingOnStop }
        set { captureSessionState.sessionRecordingOnStop = newValue }
    }

    var sessionRecordingDelay: Int? {
        get { captureSessionState.sessionRecordingDelay }
        set { captureSessionState.sessionRecordingDelay = newValue }
    }

    var sessionRecordingControlsMode: String? {
        get { captureSessionState.sessionRecordingControlsMode }
        set { captureSessionState.sessionRecordingControlsMode = newValue }
    }

    var isScrollCapturing: Bool {
        get { captureSessionState.isScrollCapturing }
        set { captureSessionState.isScrollCapturing = newValue }
    }

    var scrollCaptureStripCount: Int {
        get { captureSessionState.scrollCaptureStripCount }
        set { captureSessionState.scrollCaptureStripCount = newValue }
    }

    var scrollCapturePixelSize: CGSize {
        get { captureSessionState.scrollCapturePixelSize }
        set { captureSessionState.scrollCapturePixelSize = newValue }
    }

    var scrollCaptureMaxHeight: Int {
        get { captureSessionState.scrollCaptureMaxHeight }
        set { captureSessionState.scrollCaptureMaxHeight = newValue }
    }

    var scrollCaptureAutoScrolling: Bool {
        get { captureSessionState.scrollCaptureAutoScrolling }
        set { captureSessionState.scrollCaptureAutoScrolling = newValue }
    }

    var scrollCaptureHUDPanel: ScrollCaptureHUDPanel? {
        get { captureSessionState.scrollCaptureHUDPanel }
        set { captureSessionState.scrollCaptureHUDPanel = newValue }
    }

    var scrollCaptureMouseTap: CFMachPort? {
        get { captureSessionState.scrollCaptureMouseTap }
        set { captureSessionState.scrollCaptureMouseTap = newValue }
    }

    var scrollCaptureMouseTapSource: CFRunLoopSource? {
        get { captureSessionState.scrollCaptureMouseTapSource }
        set { captureSessionState.scrollCaptureMouseTapSource = newValue }
    }

    var scrollCaptureKeyMonitor: Any? {
        get { captureSessionState.scrollCaptureKeyMonitor }
        set { captureSessionState.scrollCaptureKeyMonitor = newValue }
    }

    var scrollCaptureLocalKeyMonitor: Any? {
        get { captureSessionState.scrollCaptureLocalKeyMonitor }
        set { captureSessionState.scrollCaptureLocalKeyMonitor = newValue }
    }

    var windowSnapEnabled: Bool {
        get { captureSessionState.windowSnapEnabled }
        set {
            captureSessionState.windowSnapEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "windowSnapEnabled")
        }
    }

    var hoveredWindowRect: NSRect? {
        get { captureSessionState.hoveredWindowRect }
        set { captureSessionState.hoveredWindowRect = newValue }
    }

    var hoveredWindowID: CGWindowID? {
        get { captureSessionState.hoveredWindowID }
        set { captureSessionState.hoveredWindowID = newValue }
    }

    var windowSnapCooldown: Bool {
        get { captureSessionState.windowSnapCooldown }
        set { captureSessionState.windowSnapCooldown = newValue }
    }

    var selectionIsWindowSnap: Bool {
        get { captureSessionState.selectionIsWindowSnap }
        set { captureSessionState.selectionIsWindowSnap = newValue }
    }

    var snappedWindowID: CGWindowID? {
        get { captureSessionState.snappedWindowID }
        set { captureSessionState.snappedWindowID = newValue }
    }

    var snappedWindowImage: NSImage? {
        get { captureSessionState.snappedWindowImage }
        set { captureSessionState.snappedWindowImage = newValue }
    }

    var windowSnapQueryInFlight: Bool {
        get { captureSessionState.windowSnapQueryInFlight }
        set { captureSessionState.windowSnapQueryInFlight = newValue }
    }

    func activateAppUnderSelection() {
        guard selectionRect.width > 0, let window else { return }
        let centerLocal = NSPoint(x: selectionRect.midX, y: selectionRect.midY)
        let centerScreen = window.convertToScreen(NSRect(origin: centerLocal, size: .zero)).origin

        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]]
        else { return }

        let overlayWindowNumber = window.windowNumber
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                windowNumber != overlayWindowNumber
            else { continue }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgW = boundsDict["Width"] ?? 0
            let cgH = boundsDict["Height"] ?? 0
            let appKitRect = NSRect(x: cgX, y: screenHeight - cgY - cgH, width: cgW, height: cgH)

            if appKitRect.contains(centerScreen) {
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                return
            }
        }
    }

    func queryWindowSnap(at screenPoint: NSPoint) {
        guard !windowSnapQueryInFlight,
            state == .idle && windowSnapEnabled,
            !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1),
            let viewWindow = window
        else { return }
        let overlayWindowNumber = viewWindow.windowNumber
        let windowOrigin = viewWindow.frame.origin
        let viewBounds = bounds
        let screenHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        windowSnapQueryInFlight = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let result = Self.windowRectOnBackground(
                screenPoint: screenPoint,
                overlayWindowNumber: overlayWindowNumber,
                windowOrigin: windowOrigin,
                viewBounds: viewBounds,
                screenH: screenHeight)
            DispatchQueue.main.async {
                guard let self else { return }
                self.windowSnapQueryInFlight = false
                let newRect = result?.rect
                if newRect != self.hoveredWindowRect {
                    self.hoveredWindowRect = newRect
                    self.hoveredWindowID = result?.windowID
                    self.needsDisplay = true
                }
            }
        }
    }
}
