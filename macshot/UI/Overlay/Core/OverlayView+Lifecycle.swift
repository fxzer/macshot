//
//  OverlayView+Lifecycle.swift
//  macshot
//
//  Overlay editor state, selection lifecycle, and reset helpers.
//

import AppKit

extension OverlayView {

    // MARK: - Cleanup

    func snapshotEditorState() -> OverlayEditorState {
        return OverlayEditorState(
            screenshotImage: screenshotImage,
            selectionRect: selectionRect,
            annotations: annotations,
            undoStack: undoStack,
            redoStack: redoStack,
            currentTool: currentTool,
            currentColor: currentColor,
            currentStrokeWidth: currentStrokeWidth,
            currentMarkerSize: currentMarkerSize,
            currentNumberSize: currentNumberSize,
            numberCounter: numberCounter,
            beautifyEnabled: beautifyEnabled,
            beautifyStyleIndex: beautifyStyleIndex,
            effectsPreset: effectsPreset,
            effectsBrightness: effectsBrightness,
            effectsContrast: effectsContrast,
            effectsSaturation: effectsSaturation,
            effectsSharpness: effectsSharpness
        )
    }

    func setAnnotations(_ anns: [Annotation]) {
        if let img = screenshotImage {
            let bounds = captureDrawRect
            for ann in anns {
                if ann.tool == .loupe
                    || ((ann.tool == .pixelate || ann.tool == .blur) && ann.bakedBlurNSImage == nil)
                {
                    ann.sourceImage = img
                    ann.sourceImageBounds = bounds
                    if ann.tool == .loupe { ann.bakeLoupe() }
                    if ann.tool == .pixelate { ann.bakePixelate() }
                }
            }
        }
        annotations = anns
        undoStack = anns.map { .added($0) }
        redoStack = []
        cachedCompositedImage = nil
        needsDisplay = true
    }

    func applySelection(_ rect: NSRect, restoredFromMemory: Bool = false) {
        selectionRect = rect
        selectionStart = rect.origin
        state = .selected
        selectionWasRestoredFromMemory = restoredFromMemory

        hideColorSamplerMagnifier()
        if currentTool == .colorSampler {
            showColorSamplerMagnifier()
        }

        showToolbars = true
        needsDisplay = true
    }

    func applyFullScreenSelection() {
        selectionRect = bounds
        selectionStart = bounds.origin
        state = .selected
        selectionWasRestoredFromMemory = false

        hideColorSamplerMagnifier()
        if currentTool == .colorSampler {
            showColorSamplerMagnifier()
        }

        aspectRatioLock = .none
        showToolbars = true
        scheduleBarcodeDetection()
        overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
        needsDisplay = true
    }

    func clearSelection() {
        state = .idle
        selectionRect = .zero
        selectionWasRestoredFromMemory = false
        clearSelectionSizeSnapState()
        remoteSelectionRect = .zero
        remoteSelectionFullRect = .zero
        showToolbars = false
        PopoverHelper.dismiss()
        colorWheel.dismiss()
        if screenshotImage != nil {
            showColorSamplerMagnifier()
        }
        needsDisplay = true
    }

    func reset() {
        MemoryDiagnostics.snapshot(
            "OverlayView.reset.before",
            images: [
                ("screenshotImage", screenshotImage),
                ("cachedCompositedImage", cachedCompositedImage),
                ("cachedAnnotationLayer", cachedAnnotationLayer),
                ("cachedAnnotationLayerExcludingSelected", cachedAnnotationLayerExcludingSelected),
                ("cachedEffectsScreenshot", cachedEffectsScreenshot),
                ("snappedWindowImage", snappedWindowImage)
            ],
            metadata: "annotations=\(annotations.count) undo=\(undoStack.count) redo=\(redoStack.count) estimatedCache=\(MemoryDiagnostics.format(bytes: UInt64(estimatedCacheMemory)))"
        )
        state = .idle
        if isScrollCapturing {
            stopScrollCaptureMode()
        }
        selectionRect = .zero
        selectionWasRestoredFromMemory = false
        clearSelectionSizeSnapState()
        selectionIsWindowSnap = false
        snappedWindowID = nil
        snappedWindowImage = nil
        remoteSelectionRect = .zero
        remoteSelectionFullRect = .zero
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        currentAnnotation = nil
        numberCounter = 0
        showToolbars = false
        teardownToolbarChrome()
        PopoverHelper.dismiss()
        editorTooltipView?.removeFromSuperview()
        editorTooltipView = nil
        isTranslating = false
        translateEnabled = false
        autoMeasurePreview = nil
        autoMeasureKeyHeld = false
        autoMeasureBitmapCtx = nil
        selectedAnnotation = nil
        isDraggingAnnotation = false
        hoveredAnnotationClearTimer?.invalidate()
        hoveredAnnotationClearTimer = nil
        hoveredAnnotation = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        colorWheel.dismiss()
        beautifyEnabled = UserDefaults.standard.bool(forKey: "beautifyEnabled")
        beautifyStyleIndex = UserDefaults.standard.integer(forKey: "beautifyStyleIndex")
        beautifyMode =
            BeautifyMode(rawValue: UserDefaults.standard.integer(forKey: "beautifyMode")) ?? .window
        beautifyPadding = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyPadding") as? Double ?? 48)
        beautifyCornerRadius = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyCornerRadius") as? Double ?? 10)
        beautifyShadowRadius = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyShadowRadius") as? Double ?? 20)
        beautifyBgRadius = CGFloat(
            UserDefaults.standard.object(forKey: "beautifyBgRadius") as? Double ?? 8)
        previewState.lineStylePerTool.removeAll()
        previewState.rectFillStylePerTool.removeAll()
        previewState.rectCornerRadiusPerTool.removeAll()
        previewState.outlineEnabledPerTool.removeAll()
        previewState.currentArrowStyle =
            ArrowStyle(rawValue: UserDefaults.standard.integer(forKey: "currentArrowStyle"))
            ?? .single
        previewState.arrowReversed = UserDefaults.standard.bool(forKey: "arrowReversed")
        textEditor.dismiss()
        toolOptionsRowView?.clearEditingAnnotation()
        resetZoomUIState()
        invalidateEditorZoomTimers()
        resetPermissionState()
        resetHintState()
        stopBackgroundRemovalSpinner()
        clearDrawingCursorPreview()
        clearLoupePreview()
        clearStampPreview()
        if let markerHandler = toolHandlers[.marker] as? MarkerToolHandler {
            markerHandler.resetSessionState()
        }

        isResizingAnnotation = false
        loupeCursorPoint = .zero
        overlayErrorTimer?.invalidate()
        overlayErrorTimer = nil
        overlayErrorMessage = nil
        barcodeDetector.cancel()
        hoveredWindowRect = nil
        isRecording = false
        hideColorSamplerMagnifier()
        if let trackingArea = mouseMovedTrackingArea {
            removeTrackingArea(trackingArea)
            mouseMovedTrackingArea = nil
        }
        // Release all screenshot-derived image data so ARC can reclaim full-screen bitmaps.
        screenshotImage = nil
        displayCGImage = nil
        originalCGImage = nil
        colorSamplingCGImage = nil
        _loupeSourceCGImage = nil
        cachedCompositedImage = nil
        cachedAnnotationLayer = nil
        cachedAnnotationLayerExcludingSelected = nil
        cachedEffectsScreenshot = nil
        needsDisplay = true
        MemoryDiagnostics.snapshot("OverlayView.reset.after")
    }

    private func teardownToolbarChrome() {
        PopoverHelper.dismiss()

        toolOptionsRowView?.clearEditingAnnotation()
        toolOptionsRowView?.overlayView = nil
        toolOptionsRowView?.removeFromSuperview()
        toolOptionsRowView = nil

        for strip in [topStripView, bottomStripView, rightStripView].compactMap({ $0 }) {
            strip.onClick = nil
            strip.onRightClick = nil
            strip.onHover = nil
            for button in strip.buttonViews {
                button.onClick = nil
                button.onMouseDown = nil
                button.onRightClick = nil
                button.onHover = nil
            }
            strip.removeFromSuperview()
        }

        topStripView = nil
        bottomStripView = nil
        rightStripView = nil
    }
}
