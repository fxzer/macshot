import Cocoa
import CoreImage
import UniformTypeIdentifiers
import Vision

extension OverlayWindowController: OverlayViewDelegate {
    func overlayViewDidFinishSelection(_ rect: NSRect) {
    }

    func overlayViewSelectionDidChange(_ rect: NSRect) {
        let screenOrigin = screen.frame.origin
        let globalRect = NSRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width, height: rect.height)
        overlayDelegate?.overlayDidChangeSelection(self, globalRect: globalRect)
    }

    func overlayViewDidCancel() {
        dismiss()
        overlayDelegate?.overlayDidCancel(self)
    }

    func overlayViewDidConfirm() {
        var memory = MemoryDiagnostics.makeScope(
            "OverlayWindowController.overlayViewDidConfirm",
            images: [("screenshotImage", overlayView?.screenshotImage)],
            metadata: "screen=\(screen.localizedName)"
        )
        // Snapshot post-processing config before dismissing (view will be torn down)
        let hasEffects = overlayView?.effectsActive ?? false
        let effectsCfg = overlayView?.effectsConfig ?? ImageEffectsConfig()
        let hasBeautify = overlayView?.beautifyEnabled ?? false
        let beautifyCfg = overlayView?.beautifyConfig ?? BeautifyConfig()
        let snapWindowImg = overlayView?.snappedWindowImage

        // Capture the composited image (screenshot + annotations baked in).
        // This is a single render — no double capture.
        guard let compositedImage = captureRegion() else {
            memory.finish("captureRegion failed")
            dismiss()
            overlayDelegate?.overlayDidCancel(self)
            return
        }
        memory.step("captureRegion", images: [("compositedImage", compositedImage)])

        // Snapshot annotations + selection rect before dismiss (view will be torn down)
        let snapshotAnnotations = overlayView?.annotations ?? []
        let snapshotSelRect = overlayView?.selectionRect ?? .zero

        // Snapshot annotation data using the raw screenshot (without annotations).
        // For window snaps, use the independently captured window image (transparent corners)
        // so the editor shows clean corners when re-editing.
        let hasAnnotations = overlayView?.annotations.contains(where: { $0.isMovable }) ?? false
        let annotationData: CaptureAnnotationData?
        if hasAnnotations {
            let rawImage: NSImage? = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? snapWindowImg : overlayView?.captureSelectedRegionRaw()
            if let raw = rawImage {
                annotationData = snapshotAnnotationData(rawImage: raw)
                memory.step(
                    "snapshotAnnotationData",
                    images: [("rawImage", raw)],
                    metadata: "annotations=\(annotationData?.annotations.count ?? 0)"
                )
            } else {
                annotationData = nil
            }
        } else {
            annotationData = nil
        }

        let pinOrigin = selectionPinOrigin()

        // Dismiss immediately — user is free to continue working
        dismiss()
        memory.step("dismissed overlay")

        // Apply post-processing if needed
        var finalImage = compositedImage
        if hasEffects {
            finalImage = ImageEffects.apply(to: finalImage, config: effectsCfg)
            memory.step("effects applied", images: [("effectsImage", finalImage)])
        }
        if hasBeautify {
            // For snapped windows, use the independently captured window image (transparent corners)
            // with annotations composited on top (using pre-dismiss snapshot)
            let beautifyInput = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? compositeAnnotationsOnSnappedWindow(snapWindowImg!, annotations: snapshotAnnotations, selectionRect: snapshotSelRect)
                : finalImage
            finalImage = BeautifyRenderer.render(image: beautifyInput, config: beautifyCfg)
            memory.step("beautify applied", images: [("beautifyImage", finalImage)])
        }

        // Don't save annotation data if effects/beautify were applied — the raw image
        // wouldn't match what the user sees, making annotation re-editing confusing.
        overlayDelegate?.overlayDidConfirm(
            self,
            capturedImage: finalImage,
            annotationData: annotationData,
            context: .standard,
            windowTitle: capturedWindowTitle,
            pinOrigin: pinOrigin
        )
        memory.finish(
            "delegate confirm",
            images: [("finalImage", finalImage), ("annotationRawImage", annotationData?.rawImage)],
            metadata: "hasAnnotations=\(annotationData != nil) effects=\(hasEffects) beautify=\(hasBeautify)"
        )
    }

    func overlayViewDidRequestPin() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image

        let globalOrigin = selectionPinOrigin() ?? .zero

        dismiss()
        overlayDelegate?.overlayDidRequestPin(self, image: image, at: globalOrigin)
    }

    func overlayViewDidRequestOCR() {
        guard let image = captureRegion() else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let delegate = self.overlayDelegate
        overlayDelegate?.overlayDidStartOCR(self)

        DispatchQueue.global(qos: .userInitiated).async { [cgImage, weak delegate] in
            let request = VisionOCR.makeTextRecognitionRequest { request, error in
                var lines: [String] = []
                if let observations = request.results as? [VNRecognizedTextObservation] {
                    for observation in observations {
                        if let candidate = observation.topCandidates(1).first {
                            lines.append(candidate.string)
                        }
                    }
                }
                let text = lines.joined(separator: "\n")
                DispatchQueue.main.async {
                    delegate?.overlayDidFinishOCR(nil, text: text)
                }
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    func overlayViewDidRequestUpload() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image
        dismiss()
        overlayDelegate?.overlayDidRequestUpload(self, image: image)
    }

    func overlayViewDidRequestShare(anchorView: NSView?) {
        // Prevent re-entry: if a share session is active or was just dismissed, ignore
        if shareDelegate != nil { return }
        if Date().timeIntervalSince(shareDismissTime) < 0.5 {
            return
        }

        // 如果有其他popover打开，先关闭它
        if PopoverHelper.isVisible {
            PopoverHelper.dismiss()
            // 延迟打开共享面板，让旧的先完全关闭
            DispatchQueue.main.async { [weak self] in
                self?.overlayViewDidRequestShare(anchorView: anchorView)
            }
            return
        }

        // Performance diagnostics
        let startTime = Date()

        guard var image = captureRegion() else { return }
        let captureTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] captureRegion: \(String(format: "%.0f", captureTime * 1000))ms")
        #endif

        image = applyBeautifyIfNeeded(image) ?? image
        let beautifyTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] applyBeautifyIfNeeded: \(String(format: "%.0f", beautifyTime * 1000))ms (delta: \(String(format: "%.0f", (beautifyTime - captureTime) * 1000))ms)")
        #endif

        // Use PNG for sharing (fast encoding, WebP picture preset is too slow: 8+ seconds)
        // PNG encoding takes ~50-100ms vs WebP's 8+ seconds with picture preset
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        let encodeTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] PNG encode: \(String(format: "%.0f", encodeTime * 1000))ms (delta: \(String(format: "%.0f", (encodeTime - beautifyTime) * 1000))ms)")
        #endif

        guard let tempURL = TemporaryFileManager.writeShareImageData(pngData, fileExtension: "png") else {
            return
        }
        let writeTime = Date().timeIntervalSince(startTime)
        #if DEBUG
        NSLog("[Share] write to temp file: \(String(format: "%.0f", writeTime * 1000))ms (delta: \(String(format: "%.0f", (writeTime - encodeTime) * 1000))ms)")
        #endif
        #if DEBUG
        NSLog("[Share] Total preparation time: \(String(format: "%.0f", writeTime * 1000))ms")
        #endif

        // Get the screen position of the share button
        let screenRect: NSRect
        if let anchor = anchorView, let win = anchor.window {
            let viewRect = anchor.convert(anchor.bounds, to: nil)
            screenRect = win.convertToScreen(viewRect)
        } else {
            let mid = NSScreen.main?.frame ?? NSRect(x: 400, y: 400, width: 100, height: 100)
            screenRect = NSRect(x: mid.midX - 20, y: mid.midY - 20, width: 40, height: 40)
        }

        // Make the overlay click-through so the system share picker (and the AirDrop
        // device UI it spawns) receives mouse events and the cursor isn't hijacked.
        //
        // Two problems are fixed by this single change:
        //  1. Click-through: the overlay is transparent but still eats clicks. Lowering its
        //     level to .floating alone is not enough because NSSharingService/AirDrop panels
        //     live at standard levels and the overlay would stay on top of them.
        //  2. Cursor: OverlayView's tracking area uses `.activeAlways`, so it keeps getting
        //     mouseMoved even when not key and re-asserts the active tool cursor (e.g. the
        //     pencil crosshair) over the system picker. With ignoresMouseEvents the overlay
        //     no longer receives mouseMoved, so the system arrow cursor shows through.
        let savedLevel = overlayWindow?.level ?? NSWindow.Level(257)
        let savedIgnoresMouseEvents = overlayWindow?.ignoresMouseEvents ?? false
        overlayWindow?.level = .floating
        overlayWindow?.ignoresMouseEvents = true
        NSCursor.arrow.set()

        let picker = NSSharingServicePicker(items: [tempURL])
        let delegate = SharePickerDelegate(
            onPick: { [weak self] _ in
                guard let self = self else { return }
                self.overlayWindow?.level = savedLevel
                self.overlayWindow?.ignoresMouseEvents = savedIgnoresMouseEvents
                self.shareDelegate = nil
                let img = image
                let pinOrigin = self.selectionPinOrigin()
                self.dismiss()
                self.overlayDelegate?.overlayDidConfirm(
                    self,
                    capturedImage: img,
                    annotationData: nil,
                    context: .standard,
                    windowTitle: self.capturedWindowTitle,
                    pinOrigin: pinOrigin
                )
            },
            onDismiss: { [weak self] in
                guard let self = self else { return }
                self.overlayWindow?.level = savedLevel
                self.overlayWindow?.ignoresMouseEvents = savedIgnoresMouseEvents
                // Re-assert the tool cursor now that the overlay is interactive again.
                self.overlayView?.updateCursorForCurrentTool()
                self.shareDelegate = nil
                self.shareDismissTime = Date()
            }
        )
        shareDelegate = delegate
        picker.delegate = delegate

        // Show anchored to the button in the overlay view
        // 使用侧边弹出方向，与包装和调色工具保持一致
        if let anchor = anchorView {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX)
        } else if let view = overlayView {
            let center = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY - 1, width: 2, height: 2)
            picker.show(relativeTo: center, of: view, preferredEdge: .minX)
        }
    }

    func overlayViewDidRequestEnterRecordingMode() {
        enterRecordingMode()
    }

    func overlayViewDidRequestStartRecording(rect: NSRect) {
        // Convert overlay-local rect to screen coordinates
        let screenRect = NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        overlayDelegate?.overlayDidRequestStartRecording(self, rect: screenRect, screen: screen)
    }

    /// Detach the webcam setup preview so it can be reused during recording.
    func detachWebcamPreview() -> WebcamOverlay? {
        overlayView?.detachWebcamSetupPreview()
    }

    func overlayViewDidRequestStopRecording() {
        overlayDelegate?.overlayDidRequestStopRecording(self)
    }

    func overlayViewDidRequestScrollCapture(rect: NSRect) {
        let screenRect = NSRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.minY + rect.minY,
            width: rect.width,
            height: rect.height
        )
        overlayDelegate?.overlayDidRequestScrollCapture(self, rect: screenRect, screen: screen)
    }

    func overlayViewDidRequestStopScrollCapture() {
        overlayDelegate?.overlayDidRequestStopScrollCapture(self)
    }

    func overlayViewDidRequestToggleAutoScroll() {
        overlayDelegate?.overlayDidRequestToggleAutoScroll(self)
    }

    func overlayViewDidRequestAccessibilityPermission() {
        overlayDelegate?.overlayDidRequestAccessibilityPermission(self)
    }

    func overlayViewDidRequestInputMonitoringPermission() {
        overlayDelegate?.overlayDidRequestInputMonitoringPermission(self)
    }

    func overlayViewDidBeginSelection() {
        overlayDelegate?.overlayDidBeginSelection(self)
    }

    func overlayViewDidChangeWindowSnapState() {
        overlayDelegate?.overlayDidChangeWindowSnapState(self)
    }

    func overlayViewDidChangeAspectRatioLock() {
        overlayDelegate?.overlayDidChangeAspectRatioLock(self)
    }

    func overlayViewDidChangeMouseLocation() {
        overlayDelegate?.overlayDidChangeMouseLocation(self)
    }

    func overlayViewDidRequestAddCapture() {}  // editor-only

    func overlayViewRemoteSelectionDidChange(_ rect: NSRect) {
        // Convert local rect to global screen coords and forward to delegate
        let screenOrigin = screen.frame.origin
        let globalRect = NSRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width, height: rect.height)
        overlayDelegate?.overlayDidRemoteResizeSelection(self, globalRect: globalRect)
    }

    func overlayViewRemoteSelectionDidFinish(_ rect: NSRect) {
        let screenOrigin = screen.frame.origin
        let globalRect = NSRect(
            x: rect.origin.x + screenOrigin.x,
            y: rect.origin.y + screenOrigin.y,
            width: rect.width, height: rect.height)
        overlayDelegate?.overlayDidFinishRemoteResize(self, globalRect: globalRect)
    }

    func overlayViewDidRequestDetach() {
        guard let view = overlayView else { return }
        view.commitTextFieldIfNeeded()
        let sel = view.selectionRect

        // Use stitched cross-screen image if available, otherwise crop from single screen.
        let croppedImage: NSImage? =
            overlayDelegate?.overlayCrossScreenImage(self)
            ?? {
                guard let src = view.screenshotImage,
                      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                // Pixel-perfect crop via CGImage.cropping() — no color space
                // conversion, no draw pipeline, just a sub-image reference.
                let scale = view.window?.backingScaleFactor ?? 2.0
                let imgH = CGFloat(srcCG.height) / scale
                // CGImage uses top-left origin; sel is in AppKit bottom-left coords.
                let cropRect = CGRect(
                    x: sel.origin.x * scale,
                    y: (imgH - sel.origin.y - sel.height) * scale,
                    width: sel.width * scale,
                    height: sel.height * scale)
                guard let cropped = srcCG.cropping(to: cropRect) else { return nil }
                return NSImage(cgImage: cropped, size: sel.size)
            }()
        guard let image = croppedImage else { return }

        // Clone annotations and shift them from overlay coords to image-relative (0,0) origin.
        let state = view.snapshotEditorState()
        let shiftedAnnotations = state.annotations.map { ann -> Annotation in
            let c = ann.clone()
            c.move(dx: -sel.origin.x, dy: -sel.origin.y)
            return c
        }

        let tool = view.currentTool
        let color = view.currentColor
        let stroke = view.activeStrokeWidthForTool(tool)

        dismiss()
        overlayDelegate?.overlayDidCancel(self)
        DetachedEditorWindowController.open(
            image: image, tool: tool, color: color, strokeWidth: stroke,
            annotations: shiftedAnnotations, fromCapture: true)
    }

    @available(macOS 14.0, *)
    func overlayViewDidRequestRemoveBackground() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image

        // Show loading state
        overlayView?.isRemovingBackground = true

        backgroundRemovalToken?.cancel()
        backgroundRemovalToken = BackgroundRemovalProcessor.removeBackground(from: image) { [weak self] token, result in
            guard let self = self else { return }
            guard self.backgroundRemovalToken === token else { return }
            self.backgroundRemovalToken = nil
            self.overlayView?.isRemovingBackground = false
            self.overlayView?.needsDisplay = true

            switch result {
            case .success(let finalImage):
                let pinOrigin = self.selectionPinOrigin()
                self.dismiss()
                self.overlayDelegate?.overlayDidConfirm(
                    self,
                    capturedImage: finalImage,
                    annotationData: nil,
                    context: .standard,
                    windowTitle: self.capturedWindowTitle,
                    pinOrigin: pinOrigin
                )
            case .failure(let error):
                self.overlayView?.showOverlayError(error.localizedDescription)
            }
        }
    }

    func overlayViewDidRequestQuickSave() {
        var memory = MemoryDiagnostics.makeScope(
            "OverlayWindowController.quickSave",
            images: [("screenshotImage", overlayView?.screenshotImage)],
            metadata: "screen=\(screen.localizedName)"
        )
        // Snapshot post-processing config before dismissing
        let hasEffects = overlayView?.effectsActive ?? false
        let effectsCfg = overlayView?.effectsConfig ?? ImageEffectsConfig()
        let hasBeautify = overlayView?.beautifyEnabled ?? false
        let beautifyCfg = overlayView?.beautifyConfig ?? BeautifyConfig()
        let snapWindowImg = overlayView?.snappedWindowImage

        guard let compositedImage = captureRegion() else {
            memory.finish("captureRegion failed")
            dismiss()
            overlayDelegate?.overlayDidCancel(self)
            return
        }
        memory.step("captureRegion", images: [("compositedImage", compositedImage)])

        // Snapshot annotations + selection rect before dismiss
        let snapshotAnns = overlayView?.annotations ?? []
        let snapshotSel = overlayView?.selectionRect ?? .zero

        // Snapshot annotation data — use snapped window image for clean corners
        let hasAnnotations = overlayView?.annotations.contains(where: { $0.isMovable }) ?? false
        let annotationData: CaptureAnnotationData?
        if hasAnnotations {
            let rawImage: NSImage? = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? snapWindowImg : overlayView?.captureSelectedRegionRaw()
            if let raw = rawImage {
                annotationData = snapshotAnnotationData(rawImage: raw)
                memory.step(
                    "snapshotAnnotationData",
                    images: [("rawImage", raw)],
                    metadata: "annotations=\(annotationData?.annotations.count ?? 0)"
                )
            } else {
                annotationData = nil
            }
        } else {
            annotationData = nil
        }

        dismiss()
        memory.step("dismissed overlay")

        // Apply post-processing
        var image = compositedImage
        if hasEffects {
            image = ImageEffects.apply(to: image, config: effectsCfg)
            memory.step("effects applied", images: [("effectsImage", image)])
        }
        if hasBeautify {
            let beautifyInput = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? compositeAnnotationsOnSnappedWindow(snapWindowImg!, annotations: snapshotAnns, selectionRect: snapshotSel)
                : image
            image = BeautifyRenderer.render(image: beautifyInput, config: beautifyCfg)
            memory.step("beautify applied", images: [("beautifyImage", image)])
        }

        let pinOrigin = selectionPinOrigin()
        overlayDelegate?.overlayDidConfirm(
            self,
            capturedImage: image,
            annotationData: annotationData,
            context: .standard,
            windowTitle: capturedWindowTitle,
            pinOrigin: pinOrigin
        )
        memory.finish(
            "delegate confirm",
            images: [("finalImage", image), ("annotationRawImage", annotationData?.rawImage)],
            metadata: "hasAnnotations=\(annotationData != nil) effects=\(hasEffects) beautify=\(hasBeautify)"
        )
    }

    func overlayViewDidRequestFileSave() {
        overlayView?.commitTextFieldIfNeeded()

        // Snapshot post-processing config before saving. Keep the overlay alive
        // until the centered hint has been shown, otherwise the user never sees it.
        let hasEffects = overlayView?.effectsActive ?? false
        let effectsCfg = overlayView?.effectsConfig ?? ImageEffectsConfig()
        let hasBeautify = overlayView?.beautifyEnabled ?? false
        let beautifyCfg = overlayView?.beautifyConfig ?? BeautifyConfig()
        let snapWindowImg = overlayView?.snappedWindowImage
        let snapshotAnns = overlayView?.annotations ?? []
        let snapshotSel = overlayView?.selectionRect ?? .zero

        guard let rawImage = captureRegion() else {
            dismiss()
            overlayDelegate?.overlayDidCancel(self)
            return
        }

        // Apply post-processing
        var image = rawImage
        if hasEffects { image = ImageEffects.apply(to: image, config: effectsCfg) }
        if hasBeautify {
            let beautifyInput = (beautifyCfg.isWindowSnap && snapWindowImg != nil)
                ? compositeAnnotationsOnSnappedWindow(snapWindowImg!, annotations: snapshotAnns, selectionRect: snapshotSel)
                : image
            image = BeautifyRenderer.render(image: beautifyInput, config: beautifyCfg)
        }

        let pinOrigin = selectionPinOrigin()
        saveImageToDirectory(image) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.dismiss()
                self.overlayDelegate?.overlayDidConfirm(
                    self,
                    capturedImage: image,
                    annotationData: nil,
                    context: .manualSave,
                    windowTitle: self.capturedWindowTitle,
                    pinOrigin: pinOrigin
                )
            case .failure(let error):
                let message = error.localizedDescription.isEmpty ? L("Save failed") : error.localizedDescription
                self.overlayView?.showOverlayError(message)
            }
        }
    }

    func saveImageToDirectory(
        _ image: NSImage,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.saveImageToPreferredDirectory(image, showFailureToast: false, completion: completion)
        } else {
            ImageSaveService.saveToDefaultDirectoryAsync(image, kind: .screenshot, completion: completion)
        }
    }

    func overlayViewDidRequestSave() {
        guard var image = captureRegion() else { return }
        image = applyBeautifyIfNeeded(image) ?? image

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [ImageEncoder.utType]
        savePanel.nameFieldStringValue = FilenameTemplateEngine.makeFilename(
            kind: .screenshot,
            fileExtension: ImageEncoder.fileExtension
        )

        savePanel.directoryURL = SaveDirectoryAccess.directoryHint()
        let pinOrigin = selectionPinOrigin()
        FilePanelPresenter.begin(savePanel, ownerWindow: overlayWindow) { [weak self] response in
            guard let self = self else { return }
            if response == .OK, let url = savePanel.url {
                let result = ImageSaveService.save(image, to: url)
                switch result {
                case .success(let fileURL):
                    (NSApp.delegate as? AppDelegate)?.showSaveResultToast(.success(fileURL))
                    SaveDirectoryAccess.save(url: fileURL.deletingLastPathComponent())
                    self.dismiss()
                    self.overlayDelegate?.overlayDidConfirm(
                        self,
                        capturedImage: nil,
                        annotationData: nil,
                        context: .manualSave,
                        windowTitle: self.capturedWindowTitle,
                        pinOrigin: pinOrigin
                    )
                case .failure(let error):
                    let message = error.localizedDescription.isEmpty ? L("Save failed") : error.localizedDescription
                    self.overlayView?.showOverlayError(message)
                }
            } else {
                self.overlayWindow?.makeKeyAndOrderFront(nil)
                if let view = self.overlayView {
                    self.overlayWindow?.makeFirstResponder(view)
                }
            }
        }
    }

    func overlayViewDidShowHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {
        // Broadcast hint state to all other screens
        overlayDelegate?.overlayViewDidShowHint(
            message: message,
            opacity: opacity,
            colorString: colorString,
            attributedString: attributedString
        )
    }

    func overlayViewDidShowError(message: String) {
        // Broadcast error state to all other screens
        overlayDelegate?.overlayViewDidShowError(message: message)
    }
}
