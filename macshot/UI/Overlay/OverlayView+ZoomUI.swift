import AppKit
import ObjectiveC

private enum OverlayZoomAssociatedKeys {
    static var level: UInt8 = 0
    static var anchorCanvas: UInt8 = 0
    static var anchorView: UInt8 = 0
    static var fadingOut: UInt8 = 0
    static var labelOpacity: UInt8 = 0
    static var fadeTimer: UInt8 = 0
    static var labelRect: UInt8 = 0
}

extension OverlayView {
    var zoomLevel: CGFloat {
        get { associatedCGFloat(for: &OverlayZoomAssociatedKeys.level, default: 1.0) }
        set { setAssociatedCGFloat(newValue, for: &OverlayZoomAssociatedKeys.level) }
    }

    var zoomAnchorCanvas: NSPoint {
        get { associatedPoint(for: &OverlayZoomAssociatedKeys.anchorCanvas) }
        set { setAssociatedPoint(newValue, for: &OverlayZoomAssociatedKeys.anchorCanvas) }
    }

    var zoomAnchorView: NSPoint {
        get { associatedPoint(for: &OverlayZoomAssociatedKeys.anchorView) }
        set { setAssociatedPoint(newValue, for: &OverlayZoomAssociatedKeys.anchorView) }
    }

    var zoomFadingOut: Bool {
        get { associatedBool(for: &OverlayZoomAssociatedKeys.fadingOut) }
        set { setAssociatedBool(newValue, for: &OverlayZoomAssociatedKeys.fadingOut) }
    }

    var zoomLabelOpacity: CGFloat {
        get { associatedCGFloat(for: &OverlayZoomAssociatedKeys.labelOpacity, default: 0.0) }
        set { setAssociatedCGFloat(newValue, for: &OverlayZoomAssociatedKeys.labelOpacity) }
    }

    var zoomFadeTimer: Timer? {
        get { objc_getAssociatedObject(self, &OverlayZoomAssociatedKeys.fadeTimer) as? Timer }
        set {
            objc_setAssociatedObject(
                self,
                &OverlayZoomAssociatedKeys.fadeTimer,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var zoomMin: CGFloat { 1.0 }
    var zoomMax: CGFloat { 8.0 }

    var zoomLabelRect: NSRect {
        get { associatedRect(for: &OverlayZoomAssociatedKeys.labelRect) }
        set { setAssociatedRect(newValue, for: &OverlayZoomAssociatedKeys.labelRect) }
    }

    func shouldIgnoreZoomLabelMouseDown(at point: NSPoint) -> Bool {
        zoomLabelOpacity > 0 && zoomLabelRect.contains(point)
    }

    func resetZoomUIState() {
        zoomLabelOpacity = 0.0
        zoomFadingOut = false
        zoomFadeTimer?.invalidate()
        zoomFadeTimer = nil
        zoomLabelRect = .zero
    }

    private func associatedCGFloat(for key: UnsafeRawPointer, default defaultValue: CGFloat) -> CGFloat {
        guard let number = objc_getAssociatedObject(self, key) as? NSNumber else { return defaultValue }
        return CGFloat(number.doubleValue)
    }

    private func setAssociatedCGFloat(_ value: CGFloat, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSNumber(value: Double(value)),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func associatedBool(for key: UnsafeRawPointer) -> Bool {
        (objc_getAssociatedObject(self, key) as? NSNumber)?.boolValue ?? false
    }

    private func setAssociatedBool(_ value: Bool, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSNumber(value: value),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func associatedPoint(for key: UnsafeRawPointer) -> NSPoint {
        (objc_getAssociatedObject(self, key) as? NSValue)?.pointValue ?? .zero
    }

    private func setAssociatedPoint(_ value: NSPoint, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSValue(point: value),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func associatedRect(for key: UnsafeRawPointer) -> NSRect {
        (objc_getAssociatedObject(self, key) as? NSValue)?.rectValue ?? .zero
    }

    private func setAssociatedRect(_ value: NSRect, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSValue(rect: value),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}
