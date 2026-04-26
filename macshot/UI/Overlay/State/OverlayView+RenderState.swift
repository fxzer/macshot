import AppKit

final class OverlayRenderState {
    var cachedCompositedImage: NSImage?
    var cachedAnnotationLayer: NSImage?
    var cachedAnnotationLayerExcludingSelected: NSImage?
    var cachedOpaqueRect: NSRect?
    var estimatedCacheMemory = 0
    var isTranslating = false
    var translateEnabled = false
    var isRemovingBackground = false
    var isCropDragging = false
    var cropDragStart: NSPoint = .zero
    var cropDragRect: NSRect = .zero
    var isResizingAnnotation = false
    var annotationResizeHandle: OverlayView.ResizeHandle = .none
    var annotationResizeAnchorIndex = -1
    var isRotatingAnnotation = false
    var rotationStartAngle: CGFloat = 0
    var rotationOriginal: CGFloat = 0
    var annotationRotateHandleRect: NSRect = .zero
    var annotationResizeOrigStart: NSPoint = .zero
    var annotationResizeOrigEnd: NSPoint = .zero
    var annotationResizeOrigTextOrigin: NSPoint = .zero
    var annotationResizeOrigControlPoint: NSPoint = .zero
    var annotationResizeOrigFontSize: CGFloat = 0
    var annotationResizeMouseStart: NSPoint = .zero
    var annotationDeleteButtonRect: NSRect = .zero
    var annotationEditButtonRect: NSRect = .zero
    var annotationResizeHandleRects: [(OverlayView.ResizeHandle, NSRect)] = []
    var multiSelectDeleteButtonRect: NSRect = .zero
    var overlayErrorMessage: String?
    let barcodeDetector = BarcodeDetector()
}

extension OverlayView {
    private var shouldDrawCurrentAnnotationInline: Bool {
        guard let annotation = currentAnnotation else { return false }
        if annotation.tool == .number && numberedCalloutPreview.sourcePoint != nil {
            return false
        }
        if annotation.tool == .loupe && magnifiedCalloutPreview.sourcePoint != nil {
            return false
        }
        return true
    }

    var cachedCompositedImage: NSImage? {
        get { renderState.cachedCompositedImage }
        set {
            renderState.cachedCompositedImage = newValue
            if newValue == nil {
                return
            }
            if !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation
                && !isScrollAdjustingProperty
            {
                setCachedAnnotationLayer(nil)
            }
        }
    }

    var cachedAnnotationLayer: NSImage? {
        get { renderState.cachedAnnotationLayer }
        set { renderState.cachedAnnotationLayer = newValue }
    }

    var cachedAnnotationLayerExcludingSelected: NSImage? {
        get { renderState.cachedAnnotationLayerExcludingSelected }
        set { renderState.cachedAnnotationLayerExcludingSelected = newValue }
    }

    var cachedOpaqueRect: NSRect? {
        get { renderState.cachedOpaqueRect }
        set { renderState.cachedOpaqueRect = newValue }
    }

    var estimatedCacheMemory: Int {
        get { renderState.estimatedCacheMemory }
        set { renderState.estimatedCacheMemory = newValue }
    }

    var isTranslating: Bool {
        get { renderState.isTranslating }
        set { renderState.isTranslating = newValue }
    }

    var translateEnabled: Bool {
        get { renderState.translateEnabled }
        set { renderState.translateEnabled = newValue }
    }

    var isRemovingBackground: Bool {
        get { renderState.isRemovingBackground }
        set {
            let oldValue = renderState.isRemovingBackground
            renderState.isRemovingBackground = newValue
            guard newValue != oldValue else { return }
            if newValue {
                startBackgroundRemovalSpinner()
            } else {
                stopBackgroundRemovalSpinner()
            }
            needsDisplay = true
        }
    }

    var isCropDragging: Bool {
        get { renderState.isCropDragging }
        set { renderState.isCropDragging = newValue }
    }

    var cropDragStart: NSPoint {
        get { renderState.cropDragStart }
        set { renderState.cropDragStart = newValue }
    }

    var cropDragRect: NSRect {
        get { renderState.cropDragRect }
        set { renderState.cropDragRect = newValue }
    }

    var isResizingAnnotation: Bool {
        get { renderState.isResizingAnnotation }
        set { renderState.isResizingAnnotation = newValue }
    }

    var annotationResizeHandle: ResizeHandle {
        get { renderState.annotationResizeHandle }
        set { renderState.annotationResizeHandle = newValue }
    }

    var annotationResizeAnchorIndex: Int {
        get { renderState.annotationResizeAnchorIndex }
        set { renderState.annotationResizeAnchorIndex = newValue }
    }

    var isRotatingAnnotation: Bool {
        get { renderState.isRotatingAnnotation }
        set { renderState.isRotatingAnnotation = newValue }
    }

    var rotationStartAngle: CGFloat {
        get { renderState.rotationStartAngle }
        set { renderState.rotationStartAngle = newValue }
    }

    var rotationOriginal: CGFloat {
        get { renderState.rotationOriginal }
        set { renderState.rotationOriginal = newValue }
    }

    var annotationRotateHandleRect: NSRect {
        get { renderState.annotationRotateHandleRect }
        set { renderState.annotationRotateHandleRect = newValue }
    }

    var annotationResizeOrigStart: NSPoint {
        get { renderState.annotationResizeOrigStart }
        set { renderState.annotationResizeOrigStart = newValue }
    }

    var annotationResizeOrigEnd: NSPoint {
        get { renderState.annotationResizeOrigEnd }
        set { renderState.annotationResizeOrigEnd = newValue }
    }

    var annotationResizeOrigTextOrigin: NSPoint {
        get { renderState.annotationResizeOrigTextOrigin }
        set { renderState.annotationResizeOrigTextOrigin = newValue }
    }

    var annotationResizeOrigControlPoint: NSPoint {
        get { renderState.annotationResizeOrigControlPoint }
        set { renderState.annotationResizeOrigControlPoint = newValue }
    }

    var annotationResizeOrigFontSize: CGFloat {
        get { renderState.annotationResizeOrigFontSize }
        set { renderState.annotationResizeOrigFontSize = newValue }
    }

    var annotationResizeMouseStart: NSPoint {
        get { renderState.annotationResizeMouseStart }
        set { renderState.annotationResizeMouseStart = newValue }
    }

    var annotationDeleteButtonRect: NSRect {
        get { renderState.annotationDeleteButtonRect }
        set { renderState.annotationDeleteButtonRect = newValue }
    }

    var annotationEditButtonRect: NSRect {
        get { renderState.annotationEditButtonRect }
        set { renderState.annotationEditButtonRect = newValue }
    }

    var annotationResizeHandleRects: [(ResizeHandle, NSRect)] {
        get { renderState.annotationResizeHandleRects }
        set { renderState.annotationResizeHandleRects = newValue }
    }

    var multiSelectDeleteButtonRect: NSRect {
        get { renderState.multiSelectDeleteButtonRect }
        set { renderState.multiSelectDeleteButtonRect = newValue }
    }

    var overlayErrorMessage: String? {
        get { renderState.overlayErrorMessage }
        set { renderState.overlayErrorMessage = newValue }
    }

    var barcodeDetector: BarcodeDetector { renderState.barcodeDetector }

    func drawCurrentAnnotationIfNeeded(in context: NSGraphicsContext) {
        guard shouldDrawCurrentAnnotationInline else { return }
        guard let annotation = currentAnnotation else { return }
        let monitor = PerfMonitor(enabled: annotation.tool == .marker)
        annotation.draw(in: context)
        monitor.finish(
            tool: "Marker",
            context: "live draw",
            metadata: "points=\(annotation.points?.count ?? 0) strokeWidth=\(String(format: "%.1f", annotation.strokeWidth)) smart=\(smartMarkerEnabled ? 1 : 0)"
        )
    }

    func drawAnnotationListLive(_ annotations: [Annotation], in context: NSGraphicsContext) {
        for annotation in annotations where annotation.tool == .pixelate {
            annotation.draw(in: context)
        }
        for annotation in annotations where annotation.tool != .pixelate {
            annotation.draw(in: context)
        }
    }
}
