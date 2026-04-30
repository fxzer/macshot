import Cocoa

// MARK: - OverlayWindowControllerDelegate

extension AppDelegate: OverlayWindowControllerDelegate {
    func overlayDidCancel(_ controller: OverlayWindowController) {
        dismissOverlays()
    }

    func overlayDidConfirm(
        _ controller: OverlayWindowController,
        capturedImage: NSImage?,
        annotationData: CaptureAnnotationData?,
        context: CaptureCompletionContext,
        windowTitle: String?,
        pinOrigin: NSPoint?
    ) {
        MemoryDiagnostics.snapshot(
            "AppDelegate.overlayDidConfirm.beforeDismiss",
            images: [("capturedImage", capturedImage), ("annotationRawImage", annotationData?.rawImage)],
            metadata: "context=\(context) hasPinOrigin=\(pinOrigin != nil)"
        )
        dismissOverlays()
        guard let image = capturedImage else { return }

        ScreenshotHistory.shared.add(
            image: image,
            rawImage: annotationData?.rawImage,
            annotations: annotationData?.annotations
        )
        let entryID = ScreenshotHistory.shared.entries.first?.id
        MemoryDiagnostics.snapshot(
            "AppDelegate.overlayDidConfirm.afterHistory",
            images: [("capturedImage", image), ("annotationRawImage", annotationData?.rawImage)],
            metadata: "entryID=\(entryID ?? "nil")"
        )
        DispatchQueue.main.async { [weak self] in
            self?.performScreenshotPostActions(
                image: image,
                annotationData: annotationData,
                historyEntryID: entryID,
                windowTitle: windowTitle,
                context: context
            )
        }
    }

    func overlayDidRequestPin(_ controller: OverlayWindowController, image: NSImage, at globalOrigin: NSPoint) {
        MemoryDiagnostics.snapshot(
            "AppDelegate.overlayDidRequestPin",
            images: [("image", image)],
            metadata: "origin=\(NSStringFromPoint(globalOrigin))"
        )
        ScreenshotHistory.shared.add(image: image)
        performFloatingPanelOverlayAction { [weak self] in
            self?.showPin(image: image, at: globalOrigin)
        }
    }

    func overlayDidStartOCR(_ controller: OverlayWindowController) {
        beginOCRSessionIfNeeded()
    }

    func overlayDidFinishOCR(_ controller: OverlayWindowController, text: String) {
        finishOCRSession(text: text)
    }

    func overlayDidRequestUpload(_ controller: OverlayWindowController, image: NSImage) {
        MemoryDiagnostics.snapshot("AppDelegate.overlayDidRequestUpload", images: [("image", image)])
        ScreenshotHistory.shared.add(image: image)
        performFloatingPanelOverlayAction { [weak self] in
            self?.uploadImage(image)
        }
    }

    func overlayDidRequestStartRecording(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        recordingFlowCoordinator.startRecording(from: controller, rect: rect, screen: screen)
    }

    func overlayDidRequestStopRecording(_ controller: OverlayWindowController) {
        recordingFlowCoordinator.handleStopRecordingRequest()
    }

    func overlayDidRequestScrollCapture(_ controller: OverlayWindowController, rect: NSRect, screen: NSScreen) {
        scrollCaptureFlowCoordinator.startScrollCapture(from: controller, rect: rect, screen: screen)
    }

    func overlayDidRequestStopScrollCapture(_ controller: OverlayWindowController) {
        scrollCaptureFlowCoordinator.stopScrollCapture()
    }

    func overlayDidRequestAccessibilityPermission(_ controller: OverlayWindowController) {
        dismissOverlays()
        SystemPermissionPrompter.requestAccessibilityPermission(
            message: L("macshot needs Accessibility permission to show keystrokes during recording. Please grant access in System Settings, then try again.")
        )
    }

    func overlayDidRequestInputMonitoringPermission(_ controller: OverlayWindowController) {
        dismissOverlays()
        SystemPermissionPrompter.requestInputMonitoringPermission(
            message: L("macshot needs Input Monitoring permission to show keystrokes during recording. Please grant access in System Settings, then try again.")
        )
    }

    func overlayDidRequestToggleAutoScroll(_ controller: OverlayWindowController) {
        scrollCaptureFlowCoordinator.toggleAutoScroll(from: controller)
    }

    func overlayDidBeginSelection(_ controller: OverlayWindowController) {
        overlaySessionCoordinator.beginSelection(from: controller)
    }

    func overlayDidChangeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        overlaySessionCoordinator.changeSelection(from: controller, globalRect: globalRect)
    }

    func overlayDidRemoteResizeSelection(_ controller: OverlayWindowController, globalRect: NSRect) {
        overlaySessionCoordinator.remoteResizeSelection(from: controller, globalRect: globalRect)
    }

    func overlayDidFinishRemoteResize(_ controller: OverlayWindowController, globalRect: NSRect) {
        overlaySessionCoordinator.finishRemoteResize(from: controller, globalRect: globalRect)
    }

    func overlayCrossScreenImage(_ controller: OverlayWindowController) -> NSImage? {
        overlaySessionCoordinator.crossScreenImage(for: controller)
    }

    func overlayDidChangeWindowSnapState(_ controller: OverlayWindowController) {
        overlaySessionCoordinator.handleWindowSnapStateChange(from: controller)
    }

    func overlayDidChangeAspectRatioLock(_ controller: OverlayWindowController) {
        overlaySessionCoordinator.handleAspectRatioLockChange(from: controller)
    }

    func overlayDidChangeMouseLocation(_ controller: OverlayWindowController) {
        overlaySessionCoordinator.handleMouseLocationChange(from: controller)
    }

    func overlayViewDidShowHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {
        overlaySessionCoordinator.broadcastHint(
            message: message,
            opacity: opacity,
            colorString: colorString,
            attributedString: attributedString
        )
    }

    func overlayViewDidShowError(message: String) {
        overlaySessionCoordinator.broadcastError(message: message)
    }
}
