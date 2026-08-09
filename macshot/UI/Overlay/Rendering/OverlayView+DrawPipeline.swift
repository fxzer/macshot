import AppKit

extension OverlayView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current else { return }

        let drawT0 = CFAbsoluteTimeGetCurrent()
        drawOverlayBackdrop(in: context)
        let backdropMs = (CFAbsoluteTimeGetCurrent() - drawT0) * 1000
        drawWindowSnapHighlight()

        if !suppressBackdropUntilCapture, state == .idle {
            drawIdleHelperText()
        } else if !suppressBackdropUntilCapture, state == .selecting {
            drawSelectingHelperText()
        }

        drawRemoteSelectionIfNeeded(in: context)
        drawActiveSelectionIfNeeded(in: context)

        if colorWheel.isVisible {
            colorWheel.draw(currentColor: currentColor)
        }

        drawOverlayErrorIfNeeded()
        drawBackgroundRemovalProgressIfNeeded()
        drawOverlayHintIfNeeded()

        if state == .selected {
            barcodeDetector.draw(
                selectionRect: selectionRect, bottomBarRect: bottomBarRect, viewBounds: bounds)
        }

        drawHoveredTooltip()

        let totalDrawMs = (CFAbsoluteTimeGetCurrent() - drawT0) * 1000
        if !hasEmittedFirstFrame {
            CaptureDiagnostics.log(
                "[macshot-perf] draw() FIRST FRAME: backdrop=\(String(format: "%.1f", backdropMs))ms total=\(String(format: "%.1f", totalDrawMs))ms size=\(bounds.size)"
            )
            hasEmittedFirstFrame = true
            onFirstFrameDrawn?()
            onFirstFrameDrawn = nil
        }
    }

    private func drawOverlayBackdrop(in context: NSGraphicsContext) {
        if isEditorMode {
            drawEditorBackground(context: context)
        } else if isScrollCapturing {
            context.cgContext.clear(bounds)
        } else {
            if suppressBackdropUntilCapture && screenshotImage == nil {
                context.cgContext.clear(bounds)
                return
            }
            if let image = screenshotImage {
                image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            }

            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }

    private func drawRemoteSelectionIfNeeded(in context: NSGraphicsContext) {
        guard remoteSelectionRect.width >= 1, remoteSelectionRect.height >= 1 else { return }

        if shouldClipSelectionImage() {
            context.saveGraphicsState()
            NSBezierPath(rect: remoteSelectionRect).setClip()
            if let image = screenshotImage {
                image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            }
            context.restoreGraphicsState()
        }

        let remoteBorder = NSBezierPath(rect: remoteSelectionRect)
        remoteBorder.lineWidth = 2.0
        ToolbarLayout.accentColor.setStroke()
        remoteBorder.stroke()

        drawRemoteResizeHandles()
    }

    private func drawActiveSelectionIfNeeded(in context: NSGraphicsContext) {
        guard state != .idle, selectionRect.width >= 1, selectionRect.height >= 1 else { return }

        if isScrollCapturing {
            context.saveGraphicsState()
            context.cgContext.clear(selectionRect)
            context.restoreGraphicsState()
        }

        if shouldClipSelectionImage() {
            context.saveGraphicsState()
            NSBezierPath(rect: selectionRect).setClip()
            applyZoomTransform(to: context)
            if !isScrollCapturing, let image = screenshotImage {
                image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            }
            context.restoreGraphicsState()
        }

        let editorDrawnFromCache = (self as? EditorView)?.drewFromCompositeCache ?? false
        var hasCanvasGraphicsState = false

        func beginCanvasGraphicsStateIfNeeded() {
            guard !hasCanvasGraphicsState else { return }
            context.saveGraphicsState()
            applyCanvasTransform(to: context)
            hasCanvasGraphicsState = true
        }

        if !editorDrawnFromCache {
            if !annotations.isEmpty && !isEditorMode {
                if (isDraggingAnnotation || isResizingAnnotation || isRotatingAnnotation
                    || isScrollAdjustingProperty),
                    let staticLayer = cachedAnnotationLayerExcludingSelected
                {
                    beginCanvasGraphicsStateIfNeeded()
                    staticLayer.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                    for annotation in selectedAnnotations {
                        annotation.draw(in: context)
                    }
                } else {
                    let layer = annotationLayerImage()
                    beginCanvasGraphicsStateIfNeeded()
                    layer.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            } else if !annotations.isEmpty {
                context.saveGraphicsState()
                applyCanvasTransform(to: context)
                NSBezierPath(rect: selectionRect).setClip()
                for annotation in annotations where annotation.tool == .translateOverlay {
                    annotation.draw(in: context)
                }
                context.restoreGraphicsState()

                beginCanvasGraphicsStateIfNeeded()
                drawAnnotationListLive(annotations.filter { $0.tool != .translateOverlay }, in: context)
            }
        } else {
            beginCanvasGraphicsStateIfNeeded()
        }

        drawCurrentAnnotationIfNeeded(in: context)
        autoMeasurePreview?.draw(in: context)

        if isCropDragging && cropDragRect.width > 1 && cropDragRect.height > 1 {
            drawCropPreview()

            NSColor.white.setStroke()
            let cropBorder = NSBezierPath(rect: cropDragRect)
            cropBorder.lineWidth = 1.5
            cropBorder.stroke()

            NSColor.white.withAlphaComponent(0.3).setStroke()
            let thirdW = cropDragRect.width / 3
            let thirdH = cropDragRect.height / 3
            for i in 1...2 {
                let gridLine = NSBezierPath()
                gridLine.move(
                    to: NSPoint(x: cropDragRect.minX + thirdW * CGFloat(i), y: cropDragRect.minY))
                gridLine.line(
                    to: NSPoint(x: cropDragRect.minX + thirdW * CGFloat(i), y: cropDragRect.maxY))
                gridLine.lineWidth = 0.5
                gridLine.stroke()

                let hLine = NSBezierPath()
                hLine.move(
                    to: NSPoint(x: cropDragRect.minX, y: cropDragRect.minY + thirdH * CGFloat(i)))
                hLine.line(
                    to: NSPoint(x: cropDragRect.maxX, y: cropDragRect.minY + thirdH * CGFloat(i)))
                hLine.lineWidth = 0.5
                hLine.stroke()
            }
        }

        if currentTool == .loupe && selectionRect.contains(loupeCursorPoint)
            && loupeCursorPoint != .zero
        {
            drawLoupePreview(at: loupeCursorPoint)
        }

        for selected in selectedAnnotations {
            drawAnnotationControls(for: selected, fullControls: selectedAnnotations.count == 1)
        }
        drawMultiSelectDeleteButton()

        if shouldDrawActiveDrawingCursorPreview {
            drawDrawingCursorPreview(at: drawingCursorPoint)
        }

        if selectionSizeSnapActive {
            drawSelectionSizeSnapGuides()
        }

        drawSnapGuides()

        if isLassoSelecting && lassoRect.width > 0 && lassoRect.height > 0 {
            ToolbarLayout.accentColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(rect: lassoRect).fill()
            ToolbarLayout.accentColor.withAlphaComponent(0.6).setStroke()
            let border = NSBezierPath(rect: lassoRect)
            border.lineWidth = 1.0
            let pattern: [CGFloat] = [4, 3]
            border.setLineDash(pattern, count: 2, phase: 0)
            border.stroke()
        }

        if hasCanvasGraphicsState {
            context.restoreGraphicsState()
        }

        let showBeautifyPreview = beautifyEnabled && state == .selected && !isScrollCapturing
        let showEffectsPreview = effectsActive && state == .selected && !isScrollCapturing
            && !beautifyEnabled

        if showBeautifyPreview {
            withCanvasGraphicsState(in: context) {
                drawBeautifyPreview(context: context)
            }

            if currentAnnotation != nil || autoMeasurePreview != nil {
                withCanvasGraphicsState(in: context) {
                    drawCurrentAnnotationIfNeeded(in: context)
                    autoMeasurePreview?.draw(in: context)
                }
            }

            if !selectedAnnotations.isEmpty {
                withCanvasGraphicsState(in: context) {
                    for selected in selectedAnnotations {
                        drawAnnotationControls(
                            for: selected, fullControls: selectedAnnotations.count == 1)
                    }
                    drawMultiSelectDeleteButton()
                }
            }

            if currentTool == .loupe && selectionRect.contains(loupeCursorPoint)
                && loupeCursorPoint != .zero
            {
                withCanvasGraphicsState(in: context) {
                    drawLoupePreview(at: loupeCursorPoint)
                }
            }

            if snapGuideX != nil || snapGuideY != nil {
                withCanvasGraphicsState(in: context) {
                    drawSnapGuides()
                }
            }

            if selectionSizeSnapActive {
                withCanvasGraphicsState(in: context) {
                    drawSelectionSizeSnapGuides()
                }
            }

            if shouldDrawActiveDrawingCursorPreview {
                withCanvasGraphicsState(in: context) {
                    drawDrawingCursorPreview(at: drawingCursorPoint)
                }
            }

            if isCropDragging && cropDragRect.width > 1 && cropDragRect.height > 1 {
                withCanvasGraphicsState(in: context) {
                    drawCropPreview()
                    NSColor.white.setStroke()
                    let cropBorder = NSBezierPath(rect: cropDragRect)
                    cropBorder.lineWidth = 1.5
                    cropBorder.stroke()
                }
            }
        }

        if showEffectsPreview, let screenshot = screenshotImage {
            withCanvasGraphicsState(in: context) {
                NSBezierPath(rect: selectionRect).setClip()
                let effectsImage = effectsProcessedScreenshot(screenshot)
                effectsImage.draw(in: captureDrawRect, from: .zero, operation: .copy, fraction: 1.0)
                drawAnnotationListLive(annotations, in: context)
                drawCurrentAnnotationIfNeeded(in: context)
            }

            if !selectedAnnotations.isEmpty {
                withCanvasGraphicsState(in: context) {
                    for selected in selectedAnnotations {
                        drawAnnotationControls(
                            for: selected, fullControls: selectedAnnotations.count == 1)
                    }
                    drawMultiSelectDeleteButton()
                }
            }

            if currentTool == .loupe && selectionRect.contains(loupeCursorPoint)
                && loupeCursorPoint != .zero
            {
                withCanvasGraphicsState(in: context) {
                    drawLoupePreview(at: loupeCursorPoint)
                }
            }

            if shouldDrawActiveDrawingCursorPreview {
                withCanvasGraphicsState(in: context) {
                    drawDrawingCursorPreview(at: drawingCursorPoint)
                }
            }

            if snapGuideX != nil || snapGuideY != nil {
                withCanvasGraphicsState(in: context) {
                    drawSnapGuides()
                }
            }

            if selectionSizeSnapActive {
                withCanvasGraphicsState(in: context) {
                    drawSelectionSizeSnapGuides()
                }
            }
        }

        if shouldDrawSelectionBorder() && !showBeautifyPreview {
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = isScrollCapturing ? 2.5 : 2.0
            (isScrollCapturing ? NSColor.systemRed : ToolbarLayout.accentColor).setStroke()
            borderPath.stroke()
        }

        if shouldDrawSizeLabel() {
            drawSizeLabel()
            if zoomLabelOpacity > 0 {
                drawZoomLabel()
            }
        }

        if state == .selected && !isEditorMode && !isScrollCapturing {
            drawResizeHandles()
        }

        drawLiveTextEditorIfNeeded(in: context)
        drawStampPreviewIfNeeded(in: context)

        if showToolbars && state == .selected && !isScrollCapturing {
            if !isEditorMode { repositionToolbars() }
        }
    }

    private func drawLiveTextEditorIfNeeded(in context: NSGraphicsContext) {
        if let scrollView = textEditor.scrollView {
            scrollView.isHidden = false
        }

        guard let scrollView = textEditor.scrollView, textEditView != nil else { return }

        let pad: CGFloat = 4
        let pillRect = scrollView.frame.insetBy(dx: -pad, dy: -pad)
        let cornerRadius: CGFloat = 4

        if textEditor.bgEnabled {
            textEditor.bgColor.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }

        if textEditor.outlineEnabled {
            textEditor.outlineColor.setStroke()
            let outlinePath = NSBezierPath(
                roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
            outlinePath.lineWidth = 2
            outlinePath.stroke()
        }

        if scrollView.isHidden, let textView = textEditView, let attributedText = textView.textStorage,
            attributedText.length > 0
        {
            let inset = textView.textContainerInset
            let textRect = NSRect(
                x: scrollView.frame.minX + inset.width, y: scrollView.frame.minY + inset.height,
                width: scrollView.frame.width - inset.width * 2,
                height: scrollView.frame.height - inset.height * 2)
            context.saveGraphicsState()
            let flipped = NSAffineTransform()
            flipped.translateX(by: 0, yBy: scrollView.frame.maxY + scrollView.frame.minY)
            flipped.scaleX(by: 1, yBy: -1)
            flipped.concat()
            attributedText.draw(in: textRect)
            context.restoreGraphicsState()
        }

        NSColor.white.withAlphaComponent(0.4).setStroke()
        let borderPath = NSBezierPath(rect: scrollView.frame)
        borderPath.lineWidth = 1
        let pattern: [CGFloat] = [4, 3]
        borderPath.setLineDash(pattern, count: 2, phase: 0)
        borderPath.stroke()

        let handleSize: CGFloat = 6
        let handleRects = [
            NSRect(
                x: scrollView.frame.minX - handleSize / 2,
                y: scrollView.frame.minY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.maxX - handleSize / 2,
                y: scrollView.frame.minY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.minX - handleSize / 2,
                y: scrollView.frame.maxY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.maxX - handleSize / 2,
                y: scrollView.frame.maxY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.midX - handleSize / 2,
                y: scrollView.frame.minY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.midX - handleSize / 2,
                y: scrollView.frame.maxY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.minX - handleSize / 2,
                y: scrollView.frame.midY - handleSize / 2,
                width: handleSize,
                height: handleSize),
            NSRect(
                x: scrollView.frame.maxX - handleSize / 2,
                y: scrollView.frame.midY - handleSize / 2,
                width: handleSize,
                height: handleSize),
        ]

        for rect in handleRects {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            NSColor.black.withAlphaComponent(0.3).setStroke()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).stroke()
        }
    }

    private func drawStampPreviewIfNeeded(in context: NSGraphicsContext) {
        guard let previewPoint = stampPreviewPoint, let image = currentStampImage,
            shouldShowStampPreview(at: canvasToView(previewPoint))
        else { return }

        let stampSize: CGFloat = 64
        let aspect = image.size.width / max(image.size.height, 1)
        let width = aspect >= 1 ? stampSize : stampSize * aspect
        let height = aspect >= 1 ? stampSize / aspect : stampSize
        let previewRect = NSRect(
            x: previewPoint.x - width / 2,
            y: previewPoint.y - height / 2,
            width: width,
            height: height)

        withCanvasGraphicsState(in: context) {
            image.draw(
                in: previewRect, from: .zero, operation: .sourceOver, fraction: 0.5,
                respectFlipped: true, hints: nil)
        }
    }

    private func withCanvasGraphicsState(in context: NSGraphicsContext, _ body: () -> Void) {
        context.saveGraphicsState()
        applyCanvasTransform(to: context)
        body()
        context.restoreGraphicsState()
    }
}
