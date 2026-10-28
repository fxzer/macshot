import Cocoa

@MainActor
final class ScrollCaptureFlowCoordinator {

    struct Dependencies {
        let overlayControllers: () -> [OverlayWindowController]
        let dismissOverlays: () -> Void
        let handleCompletedImage: (NSImage) -> Void
    }

    private let dependencies: Dependencies

    private var scrollCaptureEngine: ScrollCaptureEngine?
    private weak var scrollCaptureOverlayController: OverlayWindowController?
    private var scrollCapturePreviewPanel: ScrollCapturePreviewPanel?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func startScrollCapture(
        from controller: OverlayWindowController,
        rect: NSRect,
        screen: NSScreen
    ) {
        guard AXIsProcessTrusted() else {
            dependencies.dismissOverlays()
            SystemPermissionPrompter.requestAccessibilityPermission(
                message: L("macshot needs Accessibility permission for scroll capture. Please grant access in System Settings, then try again.")
            )
            return
        }

        cancelSession(resetOverlayState: true)

        scrollCaptureOverlayController = controller

        let coordinator = ScrollCaptureEngine(captureRect: rect, screen: screen)
        coordinator.excludedWindowIDs = dependencies.overlayControllers().map(\.windowNumber)
        scrollCaptureEngine = coordinator

        let maxHeight = UserDefaults.standard.object(forKey: "scrollMaxHeight") as? Int ?? 30000
        controller.setScrollCaptureState(isActive: true, maxHeight: maxHeight)

        let overlayLevel = 257
        if let previewPanel = ScrollCapturePreviewPanel(
            captureRect: rect,
            screen: screen,
            overlayLevel: overlayLevel
        ) {
            previewPanel.orderFront(nil)
            scrollCapturePreviewPanel = previewPanel
        }

        coordinator.onStripAdded = { [weak self, weak controller] count in
            guard let self, let coordinator = self.scrollCaptureEngine else { return }
            controller?.updateScrollCaptureProgress(
                stripCount: count,
                pixelSize: coordinator.stitchedPixelSize,
                autoScrolling: coordinator.autoScrollActive
            )
        }
        coordinator.onPreviewUpdated = { [weak self] image in
            self?.scrollCapturePreviewPanel?.updatePreview(image: image)
        }
        coordinator.onAutoScrollStarted = { [weak self, weak controller] in
            guard let self, let coordinator = self.scrollCaptureEngine else { return }
            controller?.updateScrollCaptureProgress(
                stripCount: coordinator.stripCount,
                pixelSize: coordinator.stitchedPixelSize,
                autoScrolling: true
            )
        }
        coordinator.onSessionDone = { [weak self] finalImage in
            self?.handleSessionCompleted(finalImage: finalImage)
        }

        Task { [weak coordinator] in
            await coordinator?.startSession()
        }
    }

    func stopScrollCapture() {
        scrollCaptureEngine?.stopSession()
    }

    func toggleAutoScroll(from controller: OverlayWindowController) {
        guard let coordinator = scrollCaptureEngine else { return }

        if !coordinator.autoScrollActive && !AXIsProcessTrusted() {
            cancelSession(resetOverlayState: true)
            dependencies.dismissOverlays()
            SystemPermissionPrompter.requestAccessibilityPermission(
                message: L("macshot needs Accessibility permission to auto-scroll other apps. Please grant access in System Settings, then try again.")
            )
            return
        }

        coordinator.toggleAutoScroll()
        let autoScrolling = coordinator.isActive && coordinator.autoScrollActive
        controller.updateScrollCaptureProgress(
            stripCount: coordinator.stripCount,
            pixelSize: coordinator.stitchedPixelSize,
            autoScrolling: autoScrolling
        )
    }

    func handleOverlaysDismissed() {
        cancelSession(resetOverlayState: true)
    }

    private func handleSessionCompleted(finalImage: NSImage?) {
        let completedImage = finalImage
        clearSessionState(resetOverlayState: true)
        dependencies.dismissOverlays()

        if let completedImage {
            dependencies.handleCompletedImage(completedImage)
        }
    }

    private func cancelSession(resetOverlayState: Bool) {
        guard scrollCaptureEngine != nil || scrollCaptureOverlayController != nil || scrollCapturePreviewPanel != nil else {
            return
        }

        detachCallbacks()
        scrollCaptureEngine?.cancelSession()
        clearSessionState(resetOverlayState: resetOverlayState)
    }

    private func detachCallbacks() {
        scrollCaptureEngine?.onStripAdded = nil
        scrollCaptureEngine?.onPreviewUpdated = nil
        scrollCaptureEngine?.onAutoScrollStarted = nil
        scrollCaptureEngine?.onSessionDone = nil
    }

    private func clearSessionState(resetOverlayState: Bool) {
        scrollCapturePreviewPanel?.close()
        scrollCapturePreviewPanel = nil
        if resetOverlayState {
            scrollCaptureOverlayController?.setScrollCaptureState(isActive: false)
        }
        scrollCaptureOverlayController = nil
        scrollCaptureEngine = nil
    }
}
