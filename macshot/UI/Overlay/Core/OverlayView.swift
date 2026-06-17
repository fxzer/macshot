import AVFoundation
import Cocoa
import UniformTypeIdentifiers

class OverlayView: NSView {

    // MARK: - Properties

    weak var overlayDelegate: OverlayViewDelegate?
    var onFirstFrameDrawn: (() -> Void)?
    var hasEmittedFirstFrame = false
    let interactionState = OverlayInteractionState()
    let toolState = OverlayToolState()
    let toolbarState = OverlayToolbarState()
    let appearanceState = OverlayAppearanceState()
    lazy var previewState = OverlayPreviewState(hostView: self)
    let renderState = OverlayRenderState()
    let captureSessionState = OverlayCaptureSessionState()

    /// When true, hides overlay-only toolbar buttons (record, delay, cancel, move, scroll capture).
    /// Override point for subclasses. EditorView returns true.
    var isEditorMode: Bool { false }
    /// True when a sharing service is actively running (e.g. AirDrop popover is open)
    var isSharingActive = false
    /// When true, NSScrollView handles zoom/pan/centering. Coordinate transforms become identity.
    var isInsideScrollView: Bool { false }
    /// When in scroll view mode, toolbar strips are added to this view (window content) instead of self.
    weak var chromeParentView: NSView?

    var screenshotImage: NSImage? {
        didSet {
            _loupeSourceCGImage = nil
            // Set needsDisplay synchronously so the first frame includes the
            // screenshot image — avoids a blank overlay flash.
            needsDisplay = true
            // Defer color sampler magnifier until the view is in a window.
            DispatchQueue.main.async {
                if self.state == .idle && self.screenshotImage != nil {
                    self.showColorSamplerMagnifier()
                }
            }
        }
    }

    /// Display image used for on-screen preview.
    var displayCGImage: CGImage?
    /// Standardized image used for color sampling and loupe reads.
    var originalCGImage: CGImage?
    var colorSamplingCGImage: CGImage?
    var _loupeSourceCGImage: CGImage?
    /// Loupe source image — lazily computed on first access to avoid
    /// expensive cgImage(forProposedRect:) in the screenshotImage setter.
    var loupeSourceCGImage: CGImage? {
        if _loupeSourceCGImage == nil {
            _loupeSourceCGImage = colorSamplingCGImage
                ?? displayCGImage
                ?? screenshotImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return _loupeSourceCGImage
    }

    var state: State = .idle

    /// Mouse-moved tracking installed in `viewDidMoveToWindow`; removed before re-adding to avoid stacking areas.
    var mouseMovedTrackingArea: NSTrackingArea?

    // Debounce timer for scroll wheel property adjustments (prevents memory explosion)
    var scrollPropertyAdjustTimer: Timer?
    var pendingScrollPropertyCommit: (() -> Void)?
    private var pendingPropertyChange: (annotation: Annotation, snapshot: Annotation, newValue: CGFloat, key: String)?
    /// True while the user is adjusting annotation properties via scroll wheel.
    /// Enables the split-layer fast path (draw cached static layer + only the selected annotation live).
    var isScrollAdjustingProperty: Bool = false

    // Selection / interaction state moved to OverlayView+InteractionState.swift

    // Annotations
    var annotations: [Annotation] = [] {
        didSet {
            // Memory optimization: use autoreleasepool to ensure cached images are released promptly
            // This reduces memory pressure when annotations change frequently (e.g., during drawing)
            autoreleasepool {
                invalidateAnnotationCaches()
                cachedCompositedImage = nil
                cachedEffectsScreenshot = nil
            }
            // Update move button enabled state when annotations change (defer heavy NSView work)
            if showToolbars { scheduleDeferredToolbarRebuild() }
        }
    }
    var undoStack: [UndoEntry] = [] {
        didSet {
            // Enforce depth limit: evict oldest entries and release their large image assets.
            if undoStack.count > maxUndoCount {
                let overCount = undoStack.count - maxUndoCount
                for i in 0..<overCount {
                    releaseUndoEntryImages(undoStack[i])
                }
                undoStack.removeFirst(overCount)
            }
            updateUndoRedoButtonStates()
        }
    }
    var redoStack: [UndoEntry] = [] {
        didSet {
            if redoStack.count > maxUndoCount {
                let overCount = redoStack.count - maxUndoCount
                for i in 0..<overCount {
                    releaseUndoEntryImages(redoStack[i])
                }
                redoStack.removeFirst(overCount)
            }
            updateUndoRedoButtonStates()
        }
    }

    /// Release large cached images held by an undo entry that is being evicted.
    /// This is safe because evicted entries can no longer be undone/redone.
    private func releaseUndoEntryImages(_ entry: UndoEntry) {
        switch entry {
        case .added(let ann), .deleted(let ann, _):
            ann.outlineGlowImage = nil
            // sourceImage is a reference to screenshotImage — don't nil it here
            // (it may still be referenced by live annotations).
        case .propertyChange(_, let snapshot):
            snapshot.outlineGlowImage = nil
            snapshot.textImage = nil
            snapshot.sourceImage = nil
        case .imageTransform:
            break  // NSImage in imageTransform is handled by Swift ARC
        }
    }
    var currentAnnotation: Annotation?
    /// Whether the user is actively drawing/dragging a new annotation.
    var isActivelyDrawing: Bool { currentAnnotation != nil }

    // MARK: - Tool handlers
    lazy var toolHandlers: [AnnotationTool: AnnotationToolHandler] = {
        let handlers: [AnnotationToolHandler] = [
            PencilToolHandler(),
            MarkerToolHandler(),
            LineToolHandler(),
            ArrowToolHandler(),
            RectangleToolHandler(),
            FilledRectangleToolHandler(),
            EllipseToolHandler(),
            PixelateToolHandler(),
            LoupeToolHandler(),
            MeasureToolHandler(),
            NumberToolHandler(),
            StampToolHandler(),
        ]
        return Dictionary(uniqueKeysWithValues: handlers.map { ($0.tool, $0) })
    }()
    /// currentColor with opacity applied — used for all tools except marker, loupe, measure, pixelate, blur
    var annotationColor: NSColor { currentColor.withAlphaComponent(currentColorOpacity) }

    // Select/move mode
    /// All currently selected annotations (supports multi-select via Shift+Click).
    var selectedAnnotations: [Annotation] = [] {
        didSet {
            if (selectedAnnotations.first !== oldValue.first || selectedAnnotations.count != oldValue.count)
                && isScrollAdjustingProperty
            {
                finalizeScrollPropertyAdjustmentIfNeeded()
            }
            let oldSingle = oldValue.first
            let newSingle = selectedAnnotations.first
            if newSingle !== oldSingle || oldValue.count != selectedAnnotations.count {
                toolOptionsRowView?.clearEditingAnnotation()

                if selectedAnnotations.count == 1, let ann = newSingle {
                    // Sync global color to the selected annotation's color (base color)
                    // This ensures the next drawing tool uses the color of the last selected object.
                    self.currentColor = ann.color.withAlphaComponent(1.0)

                    // Load text annotation properties into textEditor so toolbar shows correct state
                    if ann.tool == .text {
                        textEditor.restoreState(from: ann)
                    }
                    toolOptionsRowView?.rebuild(forAnnotation: ann)
                    repositionToolbars()
                } else if selectedAnnotations.isEmpty {
                    if let tool = currentTool as AnnotationTool? {
                        toolOptionsRowView?.rebuild(for: tool)
                        repositionToolbars()
                    }
                } else {
                    // Multi-select: revert to tool options (no per-annotation editing)
                    if let tool = currentTool as AnnotationTool? {
                        toolOptionsRowView?.rebuild(for: tool)
                        repositionToolbars()
                    }
                }
            }
        }
    }

    // Annotation interaction state moved to OverlayView+InteractionState.swift

    // Text editing — state managed by TextEditingController
    let textEditor = TextEditingController()
    var textEditView: NSTextView? { textEditor.textView }
    var textEditingBounds: NSRect { selectionRect }

    // Text box interaction state moved to OverlayView+InteractionState.swift
    // (Text box move handle removed — standard annotation chrome handles movement)

    /// Maximum cache memory usage in bytes (100MB)
    private let maxCacheMemory: Int = 100_000_000
    /// Maximum number of undo/redo steps retained in memory.
    /// Each entry can hold one or more Annotation objects (with optional baked images),
    /// so an unbounded stack is the primary cause of post-annotation memory growth.
    private let maxUndoCount: Int = 30

    /// Estimate memory size of an NSImage based on its pixel dimensions (RGBA, 4 bytes/pixel).
    /// Avoids expensive tiffRepresentation which triggers full rasterization.
    private func estimateImageSize(_ image: NSImage?) -> Int {
        guard let image = image else { return 0 }
        // Use pixel dimensions from the first bitmap rep, or fall back to logical size × 2 (Retina)
        if let rep = image.representations.first {
            let pw = rep.pixelsWide > 0 ? rep.pixelsWide : Int(image.size.width * 2)
            let ph = rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(image.size.height * 2)
            return pw * ph * 4  // RGBA
        }
        return Int(image.size.width * image.size.height * 4 * 4)  // worst-case: 2x Retina
    }

    private func recalculateCacheMemoryUsage() {
        var total = estimateImageSize(cachedAnnotationLayer)
            + estimateImageSize(cachedAnnotationLayerExcludingSelected)
        // Also account for per-annotation glow images (each is a full CIFilter output bitmap).
        for ann in annotations {
            total += estimateImageSize(ann.outlineGlowImage)
        }
        estimatedCacheMemory = total
    }

    private func evictAnnotationCachesIfNeeded() {
        if estimatedCacheMemory > maxCacheMemory {
            // Clear all caches to free memory
            cachedAnnotationLayer = nil
            cachedAnnotationLayerExcludingSelected = nil
            estimatedCacheMemory = 0
        }
    }

    func setCachedAnnotationLayer(_ image: NSImage?) {
        if image != nil {
            cachedAnnotationLayerExcludingSelected = nil
        }
        cachedAnnotationLayer = image
        recalculateCacheMemoryUsage()
        evictAnnotationCachesIfNeeded()
    }

    func setCachedAnnotationLayerExcludingSelected(_ image: NSImage?) {
        if image != nil {
            cachedAnnotationLayer = nil
        }
        cachedAnnotationLayerExcludingSelected = image
        recalculateCacheMemoryUsage()
        evictAnnotationCachesIfNeeded()
    }

    func buildInteractionAnnotationLayer(excluding excluded: Set<ObjectIdentifier>) -> NSImage {
        setCachedAnnotationLayer(nil)
        return buildAnnotationLayer(excluding: excluded)
    }

    /// Invalidate cache with memory tracking
    /// Invalidate annotation caches with explicit memory management.
    /// This should be called within an autoreleasepool to ensure cached images are released promptly.
    func invalidateAnnotationCaches() {
        setCachedAnnotationLayer(nil)
        setCachedAnnotationLayerExcludingSelected(nil)
    }

    // Window snapping
    static let initialWindowSnapDelay: TimeInterval = 0.06

    // Radial color wheel (right-click in drawing mode)
    let colorWheel = ColorWheelRenderer()

    // Handle
    let handleSize: CGFloat = 10

    // MARK: - Setup

    deinit {
        CaptureDiagnostics.log(
            "[macshot-life][OverlayView] deinit tool=\(String(describing: currentTool)) annotations=\(annotations.count) undo=\(undoStack.count) redo=\(redoStack.count) cacheEstimate=\(MemoryDiagnostics.format(bytes: UInt64(estimatedCacheMemory))) mem=\(MemoryDiagnostics.currentSummary())"
        )
        // Clean up all timers to prevent memory leaks
        resetZoomUIState()

        scrollPropertyAdjustTimer?.invalidate()
        scrollPropertyAdjustTimer = nil

        longPressTimer?.invalidate()
        longPressTimer = nil

        hoveredAnnotationClearTimer?.invalidate()
        hoveredAnnotationClearTimer = nil

        beautifyToolbarAnimTimer?.invalidate()
        beautifyToolbarAnimTimer = nil

        backgroundRemovalSpinnerTimer?.invalidate()
        backgroundRemovalSpinnerTimer = nil

        overlayErrorTimer?.invalidate()
        overlayErrorTimer = nil

        resetHintState()

        resetPermissionState()

        invalidateEditorZoomTimers()

        // Remove aspect ratio observers
        if let observer = aspectRatioObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = aspectRatioShortcutObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        NotificationCenter.default.removeObserver(
            self,
            name: .toolbarColorsDidChange,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .saveDirectoryDidChange,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: nil
        )
    }

    // MARK: - Subclass override points

    /// Override to handle cursor for editor chrome (top bar). Base returns false.
    func updateCursorForChrome(at point: NSPoint) -> Bool { return false }

    /// Check if a view-space point is within the image/selection area.
    /// In overlay mode, compares directly. In editor mode, converts to canvas space first.
    func pointIsInSelection(_ viewPoint: NSPoint) -> Bool {
        if isEditorMode {
            let canvasPoint = viewToCanvas(viewPoint)
            return selectionRect.contains(canvasPoint)
        }
        return selectionRect.contains(viewPoint)
    }

    /// Override point for editor background drawing. Base does nothing (overlay has no editor background).
    func drawEditorBackground(context: NSGraphicsContext) {
    }

    /// Override to clip the selection image in overlay mode. Base returns true when not in editor mode.
    func shouldClipSelectionImage() -> Bool { !isEditorMode }

    /// Override to control selection border drawing. Base returns true when not in editor mode.
    func shouldDrawSelectionBorder() -> Bool { !isEditorMode }

    /// Override to control size label drawing. Base returns true when not recording/scrolling/editing.
    func shouldDrawSizeLabel() -> Bool { !isRecording && !isScrollCapturing && !isEditorMode }

    /// Override to adjust a view-space point for editor canvas offset. Base returns point unchanged.
    func adjustPointForEditor(_ p: NSPoint) -> NSPoint { p }

    /// Reverse of adjustPointForEditor for mapping canvas-space coordinates back into view space.
    func restorePointFromEditor(_ p: NSPoint) -> NSPoint { p }

    /// Override point for editor-specific graphics context transform. Base does nothing.
    func applyEditorTransform(to context: NSGraphicsContext) {}

    /// Override to control whether selection resize handles are active. Base returns true when not in editor mode or scroll capturing.
    func shouldAllowSelectionResize() -> Bool { !isEditorMode && !isScrollCapturing }

    /// Override to control whether a new selection can be started. Base returns true when not recording and not in editor mode.
    func shouldAllowNewSelection() -> Bool { !isRecording && !isEditorMode }

    /// Override to allow panning at 1x zoom. Base returns false.
    func canPanAtOneX() -> Bool { false }

    /// Override point for editor-specific zoom clamping. Base does nothing.
    func clampZoomAnchorForEditor(r: NSRect, z: CGFloat, ac: NSPoint, av: inout NSPoint) {}

    /// Override to change the rect used when drawing the screenshot in `captureSelectedRegion`. Base returns bounds.
    var captureDrawRect: NSRect { isEditorMode ? selectionRect : bounds }

    /// Override to control whether detach (open in editor) is allowed. Base returns true when not in editor mode.
    func shouldAllowDetach() -> Bool { !isEditorMode }

    /// Override to handle clicks on chrome areas. Base returns false.
    func handleTopChromeClick(at point: NSPoint) -> Bool { false }

    // MARK: - Drawing
    // drawZoomLabel → Modes/OverlayView+Zooming.swift
    // Helper text / size label / selection handles moved to OverlayView+SelectionFeedback.swift
    // Color persistence / sampling moved to OverlayView+ColorSampler.swift
    // Beautify preview / toolbar animation moved to OverlayView+BeautifyDrawing.swift
    // Image transforms moved to OverlayView+ImageTransforms.swift

    // Snap/alignment guide helpers moved to OverlayView+SnapGuides.swift
    // Auto-measure helpers moved to OverlayView+AutoMeasure.swift
    // Zoom helpers (canvasToView, viewToCanvas, setZoom, resetZoom, commitCrop, etc.) → Modes/OverlayView+Zooming.swift
    // Annotation controls moved to OverlayView+AnnotationControls.swift
    // Outline glow rendering moved to OverlayView+AnnotationOutlineGlow.swift
    // Overlay feedback moved to OverlayView+OverlayFeedback.swift
    // Toolbar layout moved to Controls/OverlayView+Toolbar.swift

    // Handle hit testing moved to OverlayView+HandleHitTesting.swift

    // MARK: - Mouse Events

    // Mouse event overrides moved to Input/OverlayView+MouseEvents.swift
    // Zoom events (editorZoom, scrollWheel, magnify) → Modes/OverlayView+Zooming.swift

    // Selection resizing moved to OverlayView+SelectionResize.swift

    // Toolbar actions moved to Controls/OverlayView+Toolbar.swift

    // Annotation property helpers moved to OverlayView+AnnotationProperties.swift
    // Annotation interaction moved to OverlayView+AnnotationInteraction.swift

    // Text editing moved to OverlayView+TextEditing.swift
    // Annotation context helpers moved to OverlayView+AnnotationInteraction.swift

    // Remember-last-selection helpers moved to OverlayView+SelectionMemory.swift
    // Keyboard overrides moved to OverlayView+Keyboard.swift
    // Selection drag helpers moved to OverlayView+SelectionDrag.swift
    // Aspect-ratio helpers moved to OverlayView+AspectRatio.swift

    // Clipboard helpers moved to OverlayView+Clipboard.swift
    // Render-cache helpers moved to OverlayView+RenderCache.swift
    // Output rendering moved to OverlayView+OutputRendering.swift

    // Lifecycle and tool options moved to OverlayView+Lifecycle.swift / OverlayView+ToolOptions.swift
}

// Canvas protocol conformances moved to OverlayView+CanvasProtocols.swift

extension OverlayView {
    var selectionRect: NSRect {
        get { interactionState.selectionRect }
        set { interactionState.selectionRect = newValue }
    }

    var remoteSelectionRect: NSRect {
        get { interactionState.remoteSelectionRect }
        set { interactionState.remoteSelectionRect = newValue }
    }

    var remoteSelectionFullRect: NSRect {
        get { interactionState.remoteSelectionFullRect }
        set { interactionState.remoteSelectionFullRect = newValue }
    }

    var isResizingRemoteSelection: Bool {
        get { interactionState.isResizingRemoteSelection }
        set { interactionState.isResizingRemoteSelection = newValue }
    }

    var remoteResizeHandle: ResizeHandle {
        get { interactionState.remoteResizeHandle }
        set { interactionState.remoteResizeHandle = newValue }
    }

    var remoteResizeAnchor: NSPoint {
        get { interactionState.remoteResizeAnchor }
        set { interactionState.remoteResizeAnchor = newValue }
    }

    var selectionStart: NSPoint {
        get { interactionState.selectionStart }
        set { interactionState.selectionStart = newValue }
    }

    var isDraggingSelection: Bool {
        get { interactionState.isDraggingSelection }
        set { interactionState.isDraggingSelection = newValue }
    }

    var isResizingSelection: Bool {
        get { interactionState.isResizingSelection }
        set { interactionState.isResizingSelection = newValue }
    }

    var resizeHandle: ResizeHandle {
        get { interactionState.resizeHandle }
        set { interactionState.resizeHandle = newValue }
    }

    var dragOffset: NSPoint {
        get { interactionState.dragOffset }
        set { interactionState.dragOffset = newValue }
    }

    var selectionDragStart: NSPoint {
        get { interactionState.selectionDragStart }
        set { interactionState.selectionDragStart = newValue }
    }

    var selectionDragOffset: NSPoint {
        get { interactionState.selectionDragOffset }
        set { interactionState.selectionDragOffset = newValue }
    }

    var lastDragPoint: NSPoint? {
        get { interactionState.lastDragPoint }
        set { interactionState.lastDragPoint = newValue }
    }

    var spaceRepositioning: Bool {
        get { interactionState.spaceRepositioning }
        set { interactionState.spaceRepositioning = newValue }
    }

    var spaceRepositionLast: NSPoint {
        get { interactionState.spaceRepositionLast }
        set { interactionState.spaceRepositionLast = newValue }
    }

    var selectionWasRestoredFromMemory: Bool {
        get { interactionState.selectionWasRestoredFromMemory }
        set { interactionState.selectionWasRestoredFromMemory = newValue }
    }

    var aspectRatioLock: AspectRatioLock {
        get { interactionState.aspectRatioLock }
        set { interactionState.aspectRatioLock = newValue }
    }

    var aspectRatioObserver: NSObjectProtocol? {
        get { interactionState.aspectRatioObserver }
        set { interactionState.aspectRatioObserver = newValue }
    }

    var aspectRatioShortcutObserver: NSObjectProtocol? {
        get { interactionState.aspectRatioShortcutObserver }
        set { interactionState.aspectRatioShortcutObserver = newValue }
    }

    var isMouseOnThisScreen: Bool {
        get { interactionState.isMouseOnThisScreen }
        set { interactionState.isMouseOnThisScreen = newValue }
    }

    var isDraggingAnnotation: Bool {
        get { interactionState.isDraggingAnnotation }
        set { interactionState.isDraggingAnnotation = newValue }
    }

    var didMoveAnnotation: Bool {
        get { interactionState.didMoveAnnotation }
        set { interactionState.didMoveAnnotation = newValue }
    }

    var annotationDragStart: NSPoint {
        get { interactionState.annotationDragStart }
        set { interactionState.annotationDragStart = newValue }
    }

    var shiftClickPendingDeselect: Annotation? {
        get { interactionState.shiftClickPendingDeselect }
        set { interactionState.shiftClickPendingDeselect = newValue }
    }

    var isLassoSelecting: Bool {
        get { interactionState.isLassoSelecting }
        set { interactionState.isLassoSelecting = newValue }
    }

    var lassoStart: NSPoint {
        get { interactionState.lassoStart }
        set { interactionState.lassoStart = newValue }
    }

    var lassoRect: NSRect {
        get { interactionState.lassoRect }
        set { interactionState.lassoRect = newValue }
    }

    var longPressTimer: Timer? {
        get { interactionState.longPressTimer }
        set { interactionState.longPressTimer = newValue }
    }

    var longPressPoint: NSPoint {
        get { interactionState.longPressPoint }
        set { interactionState.longPressPoint = newValue }
    }

    var longPressTriggered: Bool {
        get { interactionState.longPressTriggered }
        set { interactionState.longPressTriggered = newValue }
    }

    var hoveredAnnotation: Annotation? {
        get { interactionState.hoveredAnnotation }
        set { interactionState.hoveredAnnotation = newValue }
    }

    var hoveredAnnotationClearTimer: Timer? {
        get { interactionState.hoveredAnnotationClearTimer }
        set { interactionState.hoveredAnnotationClearTimer = newValue }
    }

    var isResizingTextBox: Bool {
        get { interactionState.isResizingTextBox }
        set { interactionState.isResizingTextBox = newValue }
    }

    var textBoxResizeHandle: ResizeHandle {
        get { interactionState.textBoxResizeHandle }
        set { interactionState.textBoxResizeHandle = newValue }
    }

    var textBoxResizeStart: NSPoint {
        get { interactionState.textBoxResizeStart }
        set { interactionState.textBoxResizeStart = newValue }
    }

    var textBoxOrigFrame: NSRect {
        get { interactionState.textBoxOrigFrame }
        set { interactionState.textBoxOrigFrame = newValue }
    }

    var textBoxOrigFontSize: CGFloat {
        get { interactionState.textBoxOrigFontSize }
        set { interactionState.textBoxOrigFontSize = newValue }
    }

    var isDraggingTextBox: Bool {
        get { interactionState.isDraggingTextBox }
        set { interactionState.isDraggingTextBox = newValue }
    }

    var textBoxDragStart: NSPoint {
        get { interactionState.textBoxDragStart }
        set { interactionState.textBoxDragStart = newValue }
    }

    var textBoxDragOrigFrame: NSRect {
        get { interactionState.textBoxDragOrigFrame }
        set { interactionState.textBoxDragOrigFrame = newValue }
    }
}
