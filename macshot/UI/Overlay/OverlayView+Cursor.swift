//
//  OverlayView+Cursor.swift
//  macshot
//
//  Cursor management and cursor preview rendering for OverlayView.
//  Handles system cursor updates, resize cursors, and tool-specific cursor previews.
//

import AppKit

extension OverlayView {

    // MARK: - Cursor Visual Mode

    /// Controls whether the system cursor or a custom tool cursor preview is shown.
    enum CursorVisualMode {
        case system
        case toolPreview
    }

    // MARK: - Static Cursors

    /// Transparent 1x1 cursor used to hide the system cursor while the drawing dot preview is shown.
    private static let invisibleCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        return NSCursor(image: img, hotSpot: .zero)
    }()

    /// Diagonal resize cursor for top-left <-> bottom-right (backslash direction).
    /// macOS doesn't provide this publicly, so we use a private API.
    private static let nwseCursor: NSCursor = {
        if let cursor = NSCursor.perform(
            NSSelectorFromString("_windowResizeNorthWestSouthEastCursor"))?.takeUnretainedValue()
            as? NSCursor
        {
            return cursor
        }
        return .crosshair
    }()

    /// Diagonal resize cursor for top-right <-> bottom-left (slash direction).
    /// macOS doesn't provide this publicly, so we use a private API.
    private static let neswCursor: NSCursor = {
        if let cursor = NSCursor.perform(
            NSSelectorFromString("_windowResizeNorthEastSouthWestCursor"))?.takeUnretainedValue()
            as? NSCursor
        {
            return cursor
        }
        return .crosshair
    }()

    // MARK: - Cursor State

    /// Returns the appropriate resize cursor if the point is on a selection handle, nil otherwise.
    func resizeHandleCursor(at point: NSPoint) -> NSCursor? {
        let r = selectionRect
        let hs = handleSize + 4
        let edgeT: CGFloat = 6

        // Corner handles
        if NSRect(x: r.minX - hs / 2, y: r.maxY - hs / 2, width: hs, height: hs).contains(point)
            || NSRect(x: r.maxX - hs / 2, y: r.minY - hs / 2, width: hs, height: hs).contains(point)
        {
            return Self.nwseCursor
        }
        if NSRect(x: r.maxX - hs / 2, y: r.maxY - hs / 2, width: hs, height: hs).contains(point)
            || NSRect(x: r.minX - hs / 2, y: r.minY - hs / 2, width: hs, height: hs).contains(point)
        {
            return Self.neswCursor
        }

        // Edge handles
        if NSRect(x: r.minX + hs / 2, y: r.maxY - edgeT / 2, width: r.width - hs, height: edgeT)
            .contains(point)
            || NSRect(x: r.minX + hs / 2, y: r.minY - edgeT / 2, width: r.width - hs, height: edgeT)
                .contains(point)
        {
            return .resizeUpDown
        }
        if NSRect(x: r.minX - edgeT / 2, y: r.minY + hs / 2, width: edgeT, height: r.height - hs)
            .contains(point)
            || NSRect(
                x: r.maxX - edgeT / 2, y: r.minY + hs / 2, width: edgeT, height: r.height - hs
            ).contains(point)
        {
            return .resizeLeftRight
        }
        return nil
    }

    /// Returns the appropriate cursor for a given resize handle.
    func cursorForHandle(_ handle: ResizeHandle) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight: return Self.nwseCursor
        case .topRight, .bottomLeft: return Self.neswCursor
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .none, .move: return .arrow
        }
    }

    // MARK: - Main Cursor Update

    /// Imperative cursor management. Called from mouseMoved and a 30fps timer.
    /// Simplified: arrow for chrome, resize cursors for handles, tool cursor for canvas.
    func updateCursorForPoint(_ point: NSPoint) {
        cursorVisualMode = .system
        let canvasPoint = viewToCanvas(point)

        // Arrow cursor when mouse is over an open popover
        if PopoverHelper.isMouseInsidePopover {
            NSCursor.arrow.set()
            return
        }

        // In editor mode, check if mouse is over the top bar
        // The top bar is a sibling of the scroll view in chromeParentView, not a subview of EditorView
        if isEditorMode, let topBar = findTopBar() {
            let mouseInWindow = convert(point, to: nil)
            // Convert top bar frame to window coordinates
            let topBarFrameInWindow = topBar.convert(topBar.bounds, to: nil)
            if topBarFrameInWindow.contains(mouseInWindow) {
                NSCursor.arrow.set()
                return
            }
        }

        // Non-interactive states — simple cursors
        if textEditView != nil {
            if isDraggingTextBox {
                NSCursor.closedHand.set()
                return
            }
            if let sv = textEditor.scrollView {
                if let handle = hitTestLiveTextResizeHandle(at: point, frame: sv.frame) {
                    cursorForHandle(handle).set()
                    return
                }
                if isPointOnLiveTextDragEdge(point, frame: sv.frame) {
                    NSCursor.openHand.set()
                    return
                }
                if sv.frame.contains(point) {
                    NSCursor.iBeam.set()
                    return
                }
            }
            NSCursor.arrow.set()
            return
        }

        if zoomLabelRect.contains(point) && zoomLabelOpacity > 0 {
            NSCursor.arrow.set()
            return
        }
        if state == .idle || state == .selecting {
            // Recording mode: arrow cursor (no selection interaction)
            if isRecording {
                NSCursor.arrow.set()
                return
            }
            // Show resize cursor for remote selection handles
            if state == .idle && remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1 {
                let remoteHandle = hitTestRemoteHandle(at: point)
                if remoteHandle != .none {
                    cursorForHandle(remoteHandle).set()
                    return
                }
            }
            NSCursor.crosshair.set()
            return
        }
        guard state == .selected else { return }

        // Chrome areas — arrow
        if isPointOnChrome(point) {
            NSCursor.arrow.set()
            return
        }

        // Selection resize handles (overlay only, not during scroll capture)
        if !isEditorMode && !isScrollCapturing, let handleCursor = resizeHandleCursor(at: point) {
            handleCursor.set()
            return
        }

        // Annotation control cursors (resize handles, rotation, delete, body)
        if state == .selected && !isDraggingAnnotation && !isResizingAnnotation && !isRotatingAnnotation {
            // Check selected annotation's handles first
            if selectedAnnotation != nil {
                // Unrotate point for handle hit test
                let handlePoint: NSPoint
                if let ann = selectedAnnotation, ann.rotation != 0 && ann.supportsRotation {
                    let center = NSPoint(x: ann.boundingRect.midX, y: ann.boundingRect.midY)
                    let cos_r = cos(-ann.rotation)
                    let sin_r = sin(-ann.rotation)
                    let dx = canvasPoint.x - center.x
                    let dy = canvasPoint.y - center.y
                    handlePoint = NSPoint(x: center.x + dx * cos_r - dy * sin_r,
                                           y: center.y + dx * sin_r + dy * cos_r)
                } else {
                    handlePoint = canvasPoint
                }

                // Resize handles — directional cursors for shapes, open hand for line/arrow points
                let isShapeTool = [AnnotationTool.rectangle, .filledRectangle, .ellipse, .text,
                                   .number, .pixelate, .blur, .stamp].contains(selectedAnnotation?.tool)
                for (_, handleEntry) in annotationResizeHandleRects.enumerated() {
                    let (handle, rect) = handleEntry
                    if rect.insetBy(dx: -4, dy: -4).contains(handlePoint) {
                        if isShapeTool {
                            switch handle {
                            case .topLeft, .bottomRight: Self.nwseCursor.set()
                            case .topRight, .bottomLeft: Self.neswCursor.set()
                            case .top, .bottom: NSCursor.resizeUpDown.set()
                            case .left, .right: NSCursor.resizeLeftRight.set()
                            default: NSCursor.openHand.set()
                            }
                        } else {
                            NSCursor.openHand.set()
                        }
                        return
                    }
                }

                // Rotation handle
                if annotationRotateHandleRect != .zero
                    && annotationRotateHandleRect.insetBy(dx: -6, dy: -6).contains(canvasPoint) {
                    // Use a rotation-style cursor (crosshair works as a generic grab indicator)
                    NSCursor.openHand.set()
                    return
                }

                // Delete button
                if annotationDeleteButtonRect.contains(canvasPoint) {
                    NSCursor.arrow.set()
                    return
                }

                // Edit button
                if annotationEditButtonRect != .zero && annotationEditButtonRect.contains(canvasPoint) {
                    NSCursor.arrow.set()
                    return
                }
            }

            // Multi-select delete button
            if selectedAnnotations.count > 1 && multiSelectDeleteButtonRect.contains(canvasPoint) {
                NSCursor.arrow.set()
                return
            }

            // Body hover — open hand (skip for pencil where click still draws immediately)
            if currentTool != .select {
                if let selected = selectedAnnotation, selected.hitTest(point: canvasPoint) {
                    NSCursor.openHand.set()
                    return
                }
                if annotations.reversed().contains(where: { $0.isMovable && $0.hitTest(point: canvasPoint) }) {
                    NSCursor.openHand.set()
                    return
                }
            }

            // Inside selection area but not on any annotation — show drag cursor (Snipaste-style)
            // This allows dragging the entire selection without clicking the move button
            if currentTool == .select && pointIsInSelection(point) {
                NSCursor.closedHand.set()
                return
            }
        }

        // Tool preview takes over only after higher-priority interaction cursors have been ruled out.
        if (currentTool == .stamp && shouldShowStampPreview(at: point))
            || (currentTool == .loupe && shouldShowLoupePreview(at: point))
            || shouldShowDrawingCursorPreview(at: point)
        {
            cursorVisualMode = .toolPreview
            Self.invisibleCursor.set()
        } else if let handler = toolHandlers[currentTool], let cursor = handler.cursorForCanvas(self) {
            cursor.set()
        } else {
            switch currentTool {
            case .select: NSCursor.arrow.set()
            case .text: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        }
    }

    func updateCursorForCurrentTool() {
        guard let win = window else { return }
        let point = convert(win.mouseLocationOutsideOfEventStream, from: nil)
        updateCursorForPoint(point)
        updateToolCursorPreviews(at: point)
    }

    func refreshToolCursorPreview() {
        guard window != nil else { return }
        updateCursorForCurrentTool()
        needsDisplay = true
    }

    // Cursor preview helpers moved to OverlayView+CursorPreview.swift
    // Loupe preview drawing moved to OverlayView+LoupePreview.swift
}
