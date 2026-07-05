import AppKit

extension OverlayView {
    func startScrollCaptureMode() {
        isScrollCapturing = true
        scrollCaptureStripCount = 0
        scrollCapturePixelSize = .zero
        scrollCaptureAutoScrolling = false

        showToolbars = false
        bottomStripView?.isHidden = true
        rightStripView?.isHidden = true
        toolOptionsRowView?.isHidden = true

        activateAppUnderSelection()
        window?.ignoresMouseEvents = true

        if AXIsProcessTrusted() {
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
                callback: { _, _, _, _ in nil },
                userInfo: nil)
            if let tap {
                let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                scrollCaptureMouseTap = tap
                scrollCaptureMouseTapSource = source
            }
        }

        let handleScrollKey: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.isScrollCapturing else { return }
            if event.keyCode == 53 {
                self.overlayDelegate?.overlayViewDidRequestStopScrollCapture()
            }
        }
        scrollCaptureKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handleScrollKey(event)
        }
        scrollCaptureLocalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleScrollKey(event)
            if event.keyCode == 53 { return nil }
            return event
        }

        let panel = ScrollCaptureHUDPanel()
        panel.hudView.onStop = { [weak self] in
            self?.overlayDelegate?.overlayViewDidRequestStopScrollCapture()
        }
        panel.hudView.onToggleAutoScroll = { [weak self] in
            self?.overlayDelegate?.overlayViewDidRequestToggleAutoScroll()
        }
        panel.hudView.update(
            stripCount: 0,
            pixelSize: .zero,
            backingScale: window?.backingScaleFactor ?? 2,
            maxScrollHeight: scrollCaptureMaxHeight,
            autoScrolling: scrollCaptureAutoScrolling)
        if let window {
            panel.position(relativeTo: selectionRect, in: window)
        }
        panel.orderFront(nil)
        scrollCaptureHUDPanel = panel

        needsDisplay = true
    }

    func stopScrollCaptureMode() {
        isScrollCapturing = false
        scrollCaptureStripCount = 0
        scrollCapturePixelSize = .zero
        scrollCaptureAutoScrolling = false

        showToolbars = true
        bottomStripView?.isHidden = false
        rightStripView?.isHidden = false
        toolOptionsRowView?.isHidden = false
        // `showToolbars = true` already schedules a coalesced toolbar rebuild via
        // scheduleDeferredToolbarRebuild — no explicit rebuild call needed here.

        if let monitor = scrollCaptureKeyMonitor {
            NSEvent.removeMonitor(monitor)
            scrollCaptureKeyMonitor = nil
        }
        if let monitor = scrollCaptureLocalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            scrollCaptureLocalKeyMonitor = nil
        }
        if let tap = scrollCaptureMouseTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = scrollCaptureMouseTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            scrollCaptureMouseTap = nil
            scrollCaptureMouseTapSource = nil
        }
        scrollCaptureHUDPanel?.close()
        scrollCaptureHUDPanel = nil
        window?.ignoresMouseEvents = false

        needsDisplay = true
    }

    func updateScrollCaptureHUD() {
        scrollCaptureHUDPanel?.hudView.update(
            stripCount: scrollCaptureStripCount,
            pixelSize: scrollCapturePixelSize,
            backingScale: window?.backingScaleFactor ?? 2,
            maxScrollHeight: scrollCaptureMaxHeight,
            autoScrolling: scrollCaptureAutoScrolling)
        if let window {
            scrollCaptureHUDPanel?.position(relativeTo: selectionRect, in: window)
        }
    }
}
