import Cocoa

extension OverlayWindowController {
    func presentWindow(_ window: OverlayWindow, acceptInputIfReady: Bool) {
        window.orderFrontRegardless()
        if acceptInputIfReady {
            makeKey()
        }
    }

    func makeKey() {
        guard !isDismissed, captureAsset != nil,
              let window = overlayWindow, window.isVisible,
              let view = overlayView, view.screenshotImage != nil,
              !view.suppressBackdropUntilCapture else { return }

        // 非激活 NSPanel 可以接收键盘而不激活整个应用。原应用不会失活，
        // 因而无需强制 flush 背景或轮询 isActive 来避免其设置窗口闪动。
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.refreshWindowSnapHoverAtMouseLocation()
        CaptureDiagnostics.log("[macshot-perf][overlay] INPUT READY total=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - presentationStartedAt) * 1000))ms key=\(window.isKeyWindow) active=\(NSApp.isActive)")
        if window.isKeyWindow {
            onInputReady?()
        }
    }
}
