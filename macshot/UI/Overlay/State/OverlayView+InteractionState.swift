import AppKit

final class OverlayInteractionState {
    var selectionRect: NSRect = .zero
    var remoteSelectionRect: NSRect = .zero
    var remoteSelectionFullRect: NSRect = .zero
    var isResizingRemoteSelection = false
    var remoteResizeHandle: OverlayView.ResizeHandle = .none
    var remoteResizeAnchor: NSPoint = .zero
    var selectionStart: NSPoint = .zero
    var isDraggingSelection = false
    var isResizingSelection = false
    var resizeHandle: OverlayView.ResizeHandle = .none
    var dragOffset: NSPoint = .zero
    var selectionDragStart: NSPoint = .zero
    var selectionDragOffset: NSPoint = .zero
    var lastDragPoint: NSPoint?
    var spaceRepositioning = false
    var spaceRepositionLast: NSPoint = .zero
    var selectionWasRestoredFromMemory = false
    var aspectRatioLock: OverlayView.AspectRatioLock = .none
    var aspectRatioObserver: NSObjectProtocol?
    var aspectRatioShortcutObserver: NSObjectProtocol?
    var isMouseOnThisScreen = false
    var isDraggingAnnotation = false
    var didMoveAnnotation = false
    var annotationDragStart: NSPoint = .zero
    weak var shiftClickPendingDeselect: Annotation?
    var isLassoSelecting = false
    var lassoStart: NSPoint = .zero
    var lassoRect: NSRect = .zero
    var longPressTimer: Timer?
    var longPressPoint: NSPoint = .zero
    var longPressTriggered = false
    var hoveredAnnotation: Annotation?
    var hoveredAnnotationClearTimer: Timer?
    var isResizingTextBox = false
    var textBoxResizeHandle: OverlayView.ResizeHandle = .none
    var textBoxResizeStart: NSPoint = .zero
    var textBoxOrigFrame: NSRect = .zero
    var textBoxOrigFontSize: CGFloat = 0
    var isDraggingTextBox = false
    var textBoxDragStart: NSPoint = .zero
    var textBoxDragOrigFrame: NSRect = .zero
}
