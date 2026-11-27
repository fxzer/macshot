import AppKit

enum AutoCaptureAction: Equatable {
    case none
    case ocr
    case quickSave
    case scrollCapture
    case confirm
}

final class OverlayCaptureSessionState {
    var suppressBackdropUntilCapture = false
    var autoCaptureAction: AutoCaptureAction = .none
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
    let windowSnapHover = WindowSnapHoverTracker()
    var windowSnapCooldown = true
    var selectionIsWindowSnap = false
    var snappedWindowID: CGWindowID?
    var snappedWindowImage: NSImage?
}

extension OverlayView {
    var suppressBackdropUntilCapture: Bool {
        get { captureSessionState.suppressBackdropUntilCapture }
        set { captureSessionState.suppressBackdropUntilCapture = newValue }
    }

    var autoCaptureAction: AutoCaptureAction {
        get { captureSessionState.autoCaptureAction }
        set { captureSessionState.autoCaptureAction = newValue }
    }

    var hasPendingAutoAction: Bool {
        captureSessionState.autoCaptureAction != .none
    }

    var autoOCRMode: Bool {
        get { captureSessionState.autoCaptureAction == .ocr }
        set { captureSessionState.autoCaptureAction = newValue ? .ocr : (captureSessionState.autoCaptureAction == .ocr ? .none : captureSessionState.autoCaptureAction) }
    }

    var autoQuickSaveMode: Bool {
        get { captureSessionState.autoCaptureAction == .quickSave }
        set { captureSessionState.autoCaptureAction = newValue ? .quickSave : (captureSessionState.autoCaptureAction == .quickSave ? .none : captureSessionState.autoCaptureAction) }
    }

    var autoScrollCaptureMode: Bool {
        get { captureSessionState.autoCaptureAction == .scrollCapture }
        set { captureSessionState.autoCaptureAction = newValue ? .scrollCapture : (captureSessionState.autoCaptureAction == .scrollCapture ? .none : captureSessionState.autoCaptureAction) }
    }

    var autoConfirmMode: Bool {
        get { captureSessionState.autoCaptureAction == .confirm }
        set { captureSessionState.autoCaptureAction = newValue ? .confirm : (captureSessionState.autoCaptureAction == .confirm ? .none : captureSessionState.autoCaptureAction) }
    }

    @discardableResult
    func triggerPendingAutoOCRIfReady() -> Bool {
        guard autoOCRMode, state == .selected else { return false }
        guard screenshotImage != nil else { return false }
        autoOCRMode = false
        overlayDelegate?.overlayViewDidRequestOCR()
        return true
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
        captureSessionState.windowSnapHover.target?.rect
    }

    var hoveredWindowID: CGWindowID? {
        captureSessionState.windowSnapHover.target?.windowID
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

    func activateAppUnderSelection() {
        guard selectionRect.width > 0, let window else { return }
        let centerInWindow = convert(
            NSPoint(x: selectionRect.midX, y: selectionRect.midY), to: nil)
        let centerScreen = window.convertToScreen(NSRect(origin: centerInWindow, size: .zero)).origin

        guard let target = windowSnapTarget(atScreenPoint: centerScreen) else { return }
        NSRunningApplication(processIdentifier: target.ownerPID)?.activate(options: [])
    }
}
