import Cocoa

extension OverlayView {

    /// 当前是否处于“鼠标悬停即高亮窗口”的状态。
    var canHoverWindowSnap: Bool {
        state == .idle && windowSnapEnabled && !isRegionSnapKeyHeld
            && !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1)
    }

    /// 视图坐标 → AppKit 全局屏幕坐标。
    func screenPointForWindowSnap(_ viewPoint: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        let pointInWindow = convert(viewPoint, to: nil)
        return window.convertToScreen(NSRect(origin: pointInWindow, size: .zero)).origin
    }

    /// 同步识别 AppKit 全局屏幕坐标 `screenPoint` 下的窗口。
    func windowSnapTarget(atScreenPoint screenPoint: NSPoint) -> WindowSnapDetector.Target? {
        guard let viewWindow = window else { return nil }
        return WindowSnapDetector.target(
            atScreenPoint: screenPoint,
            overlayWindowNumber: viewWindow.windowNumber,
            overlayWindowOrigin: viewWindow.frame.origin,
            overlayBounds: bounds
        )
    }

    /// 鼠标移动时的悬停识别：查询在后台线程执行，避免 WindowServer 往返阻塞主线程。
    func queryWindowSnap(at screenPoint: NSPoint) {
        guard canHoverWindowSnap, let viewWindow = window else { return }
        let overlayWindowNumber = viewWindow.windowNumber
        let overlayWindowOrigin = viewWindow.frame.origin
        let overlayBounds = bounds
        captureSessionState.windowSnapHover.track(
            screenPoint,
            query: { point, completion in
                DispatchQueue.global(qos: .userInteractive).async {
                    let target = WindowSnapDetector.target(
                        atScreenPoint: point,
                        overlayWindowNumber: overlayWindowNumber,
                        overlayWindowOrigin: overlayWindowOrigin,
                        overlayBounds: overlayBounds
                    )
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { completion(target) }
                    }
                }
            },
            handler: { [weak self] target in
                guard let self else { return }
                self.needsDisplay = true
                CaptureDiagnostics.log(
                    "[macshot-window-snap] hover windowID=\(String(describing: target?.windowID)) rect=\(String(describing: target?.screenRect))"
                )
            }
        )
    }

    /// 同步识别点击位置的窗口，并让在途的悬停查询失效。
    /// 悬停查询是异步的，点击时直接沿用缓存可能选中上一次高亮的窗口。
    func confirmWindowSnapTarget(at viewPoint: NSPoint) -> WindowSnapDetector.Target? {
        guard windowSnapEnabled,
              !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1),
              let screenPoint = screenPointForWindowSnap(viewPoint)
        else {
            return nil
        }
        clearWindowSnapHover()
        let startedAt = CFAbsoluteTimeGetCurrent()
        let target = windowSnapTarget(atScreenPoint: screenPoint)
        CaptureDiagnostics.log(
            "[macshot-window-snap] click windowID=\(String(describing: target?.windowID)) rect=\(String(describing: target?.screenRect)) elapsed=\(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - startedAt) * 1000))ms"
        )
        return target
    }

    /// 清空悬停高亮，并丢弃尚未返回的悬停查询。
    func clearWindowSnapHover() {
        if captureSessionState.windowSnapHover.invalidate() {
            needsDisplay = true
        }
    }

    /// 遮罩出现或重新开启吸附时，鼠标还没有移动也先识别当前鼠标下的窗口。
    func refreshWindowSnapHoverAtMouseLocation() {
        guard !windowSnapCooldown, !suppressBackdropUntilCapture,
              let frame = window?.frame, frame.contains(NSEvent.mouseLocation)
        else { return }
        queryWindowSnap(at: NSEvent.mouseLocation)
    }

    func drawWindowSnapHighlight() {
        guard state == .idle, windowSnapEnabled, !isRegionSnapKeyHeld,
              let rect = hoveredWindowRect, !rect.isEmpty else {
            return
        }

        ToolbarLayout.accentColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        let border = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 2
        ToolbarLayout.accentColor.withAlphaComponent(0.85).setStroke()
        border.stroke()
    }
}
