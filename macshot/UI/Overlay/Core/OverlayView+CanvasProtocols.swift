//
//  OverlayView+CanvasProtocols.swift
//  macshot
//
//  Canvas protocol conformances and effects screenshot helpers.
//

import AppKit

extension OverlayView {
    func effectsProcessedScreenshot(_ screenshot: NSImage) -> NSImage {
        if let cached = cachedEffectsScreenshot { return cached }
        let config = effectsConfig
        guard !config.isIdentity else { return screenshot }
        let processed = ImageEffects.apply(to: screenshot, config: config)
        cachedEffectsScreenshot = processed
        return processed
    }
}

extension OverlayView: AnnotationCanvas {
    var activeAnnotation: Annotation? {
        get { currentAnnotation }
        set { currentAnnotation = newValue }
    }

    func setNeedsDisplay() {
        needsDisplay = true
    }

    func nextNumberValue() -> Int {
        nextNumberValueForNewAnnotation()
    }

    func initialStrokeWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .select:
            return currentPencilStrokeWidth
        case .line:
            return currentLineStrokeWidth
        case .arrow:
            return currentArrowStrokeWidth
        case .marker:
            return currentMarkerSize
        case .number:
            return currentNumberSize
        default:
            return currentStrokeWidth
        }
    }

    func autoSelectNewAnnotation(_ annotation: Annotation) {
        selectedAnnotation = annotation
        cachedCompositedImage = nil
    }

    func beginMagnifiedCalloutPreview(sourcePoint: NSPoint, color: NSColor) {
        clearLoupePreview()
        magnifiedCalloutPreview.begin(
            at: sourcePoint,
            diameter: currentLoupeSize,
            color: color
        )
    }

    func updateMagnifiedCalloutPreview(destinationPoint: NSPoint) {
        let drawingBounds = selectionRect.intersection(bounds).isEmpty
            ? selectionRect : selectionRect.intersection(bounds)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        magnifiedCalloutPreview.update(
            destination: destinationPoint,
            constrainedTo: drawingBounds,
            image: loupeSourceCGImage,
            imageDrawRect: captureDrawRect,
            color: currentColor,
            backingScale: scale
        )
    }

    func finishMagnifiedCalloutPreview() -> LoupeCalloutPreviewSnapshot? {
        magnifiedCalloutPreview.finish()
    }

    func cancelMagnifiedCalloutPreview() {
        magnifiedCalloutPreview.hide()
    }

    func beginNumberedCalloutPreview(
        sourcePoint: NSPoint,
        bubbleDiameter: CGFloat,
        numberText: String,
        color: NSColor
    ) {
        clearDrawingCursorPreview()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        numberedCalloutPreview.begin(
            at: sourcePoint,
            diameter: bubbleDiameter,
            numberText: numberText,
            color: color,
            backingScale: scale
        )
    }

    func updateNumberedCalloutPreview(destinationPoint: NSPoint) {
        let drawingBounds = selectionRect.intersection(bounds).isEmpty
            ? selectionRect : selectionRect.intersection(bounds)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        numberedCalloutPreview.update(
            destination: destinationPoint,
            constrainedTo: drawingBounds,
            color: opacityAppliedColor(for: .number),
            backingScale: scale
        )
    }

    func finishNumberedCalloutPreview() -> LoupeCalloutPreviewSnapshot? {
        numberedCalloutPreview.finish()
    }

    func cancelNumberedCalloutPreview() {
        numberedCalloutPreview.hide()
    }
}

extension OverlayView: TextEditingCanvas {}
