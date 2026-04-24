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
                    let dx = point.x - center.x
                    let dy = point.y - center.y
                    handlePoint = NSPoint(x: center.x + dx * cos_r - dy * sin_r,
                                          y: center.y + dx * sin_r + dy * cos_r)
                } else {
                    handlePoint = point
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
                    && annotationRotateHandleRect.insetBy(dx: -6, dy: -6).contains(point) {
                    // Use a rotation-style cursor (crosshair works as a generic grab indicator)
                    NSCursor.openHand.set()
                    return
                }

                // Delete button
                if annotationDeleteButtonRect.contains(point) {
                    NSCursor.arrow.set()
                    return
                }

                // Edit button
                if annotationEditButtonRect != .zero && annotationEditButtonRect.contains(point) {
                    NSCursor.arrow.set()
                    return
                }
            }

            // Multi-select delete button
            if selectedAnnotations.count > 1 && multiSelectDeleteButtonRect.contains(point) {
                NSCursor.arrow.set()
                return
            }

            // Body hover — open hand (skip for pencil where click still draws immediately)
            if currentTool != .select {
                let canvasPoint = viewToCanvas(point)
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
            if currentTool == .select && selectionRect.contains(point) {
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

    // MARK: - Cursor Preview Properties

    /// Core radius of the drawing cursor preview (without padding).
    var drawingCursorCoreRadius: CGFloat {
        switch currentTool {
        case .marker:
            if smartMarkerEnabled {
                return max((smartMarkerLineHeight ?? currentMarkerSize) / 2, 6)
            }
            return max(currentMarkerSize / 2, 6)
        case .number:
            return NumberCalloutGeometry.bubbleRadius(for: currentNumberSize)
        case .loupe:
            return max(currentLoupeSize / 2, 12)
        default:
            return max(activeDrawingPreviewStrokeWidth / 2, 5)
        }
    }

    /// Half-extent of the drawing cursor preview (used for dirty rect invalidation).
    var drawingCursorRadius: CGFloat {
        switch currentTool {
        case .marker:
            return max(drawingCursorCoreRadius + 2, 8)
        case .pencil:
            return max(drawingCursorCoreRadius + 2, 6)
        case .measure:
            return 16
        case .number:
            return max(drawingCursorCoreRadius + 8, 18)
        case .pixelate, .blur:
            return max(drawingCursorCoreRadius + 12, 18)
        case .line, .arrow, .rectangle, .filledRectangle, .ellipse:
            return max(drawingCursorCoreRadius + 10, 16)
        default:
            return max(drawingCursorCoreRadius + 8, 14)
        }
    }

    /// Stroke width for drawing cursor preview.
    var activeDrawingPreviewStrokeWidth: CGFloat {
        max(activeStrokeWidthForTool(currentTool), 1)
    }

    /// Color for drawing cursor preview.
    var activeDrawingPreviewColor: NSColor {
        switch currentTool {
        case .pixelate, .blur:
            return NSColor.white
        default:
            return opacityAppliedColor(for: currentTool)
        }
    }

    var shouldDrawActiveDrawingCursorPreview: Bool {
        guard supportsDrawingCursorPreview(for: currentTool),
            drawingCursorPoint != .zero,
            currentAnnotation == nil,
            !isDraggingAnnotation,
            !isResizingAnnotation,
            !isRotatingAnnotation
        else { return false }
        return true
    }

    // MARK: - Cursor Preview Support

    func supportsDrawingCursorPreview(for tool: AnnotationTool) -> Bool {
        switch tool {
        case .pencil, .marker, .line, .arrow, .measure, .number:
            return true
        default:
            return false
        }
    }

    func shouldShowDrawingCursorPreview(at viewPoint: NSPoint) -> Bool {
        guard state == .selected,
            !isRecording,
            supportsDrawingCursorPreview(for: currentTool),
            pointIsInSelection(viewPoint),
            !isPointOnChrome(viewPoint)
        else { return false }
        return true
    }

    func shouldShowStampPreview(at viewPoint: NSPoint) -> Bool {
        guard currentTool == .stamp,
            currentStampImage != nil,
            state == .selected,
            !isRecording,
            pointIsInSelection(viewPoint),
            !isPointOnChrome(viewPoint)
        else { return false }
        return true
    }

    func shouldShowLoupePreview(at viewPoint: NSPoint) -> Bool {
        guard currentTool == .loupe,
            state == .selected,
            !isRecording,
            pointIsInSelection(viewPoint),
            !isPointOnChrome(viewPoint)
        else { return false }
        return true
    }

    // MARK: - Cursor Preview Updates

    func updateToolCursorPreviews(at viewPoint: NSPoint) {
        updateStampPreview(at: viewPoint)
        updateLoupePreview(at: viewPoint)
        updateDrawingCursorPreview(at: viewPoint)
    }

    func invalidateCursorPreview(oldCanvas: NSPoint, newCanvas: NSPoint, radius: CGFloat) {
        let margin: CGFloat = 4
        // Scale canvas-space radius to view-space pixels (zoom factor)
        let r = (radius + margin) * zoomLevel
        if oldCanvas != .zero {
            let oldView = canvasToView(oldCanvas)
            setNeedsDisplay(NSRect(x: oldView.x - r, y: oldView.y - r, width: r * 2, height: r * 2))
        }
        let newView = canvasToView(newCanvas)
        setNeedsDisplay(NSRect(x: newView.x - r, y: newView.y - r, width: r * 2, height: r * 2))
    }

    func updateSmartMarkerPreviewMetrics(at canvasPoint: NSPoint) {
        guard currentTool == .marker && smartMarkerEnabled else {
            smartMarkerLineHeight = nil
            return
        }
        if let handler = toolHandlers[.marker] as? MarkerToolHandler {
            handler.ensureOCRCache(canvas: self)
            smartMarkerLineHeight = handler.textLineHeight(at: canvasPoint, canvas: self)
        }
    }

    func updateStampPreview(at viewPoint: NSPoint) {
        guard currentTool == .stamp,
            cursorVisualMode == .toolPreview,
            shouldShowStampPreview(at: viewPoint)
        else {
            clearStampPreview()
            return
        }

        let canvasStampPt = viewToCanvas(viewPoint)
        if stampPreviewPoint == nil
            || hypot(
                canvasStampPt.x - (stampPreviewPoint?.x ?? 0),
                canvasStampPt.y - (stampPreviewPoint?.y ?? 0)) > 0.5
        {
            let oldPt = stampPreviewPoint ?? .zero
            stampPreviewPoint = canvasStampPt
            invalidateCursorPreview(oldCanvas: oldPt, newCanvas: canvasStampPt, radius: stampPreviewRadius)
        }
    }

    func updateLoupePreview(at viewPoint: NSPoint) {
        guard currentTool == .loupe,
            cursorVisualMode == .toolPreview,
            shouldShowLoupePreview(at: viewPoint)
        else {
            clearLoupePreview()
            return
        }

        let newPoint = viewToCanvas(viewPoint)
        if newPoint != loupeCursorPoint {
            let oldPt = loupeCursorPoint
            loupeCursorPoint = newPoint
            let r = currentLoupeSize / 2 + 4
            invalidateCursorPreview(oldCanvas: oldPt, newCanvas: newPoint, radius: r)
        }
    }

    func updateDrawingCursorPreview(at viewPoint: NSPoint) {
        guard cursorVisualMode == .toolPreview,
            shouldShowDrawingCursorPreview(at: viewPoint)
        else {
            clearDrawingCursorPreview()
            return
        }

        let canvasPoint = viewToCanvas(viewPoint)
        let oldPt = drawingCursorPoint
        let oldR = drawingCursorRadius
        drawingCursorPoint = canvasPoint
        updateSmartMarkerPreviewMetrics(at: canvasPoint)
        let newR = drawingCursorRadius

        if canvasPoint != oldPt || abs(newR - oldR) > 0.5 {
            let r = max(oldR, newR) + 4
            invalidateCursorPreview(oldCanvas: oldPt, newCanvas: canvasPoint, radius: r)
        }
    }

    func clearStampPreview() {
        guard let oldPt = stampPreviewPoint else { return }
        stampPreviewPoint = nil
        invalidateCursorPreview(oldCanvas: oldPt, newCanvas: oldPt, radius: stampPreviewRadius)
    }

    func clearLoupePreview() {
        guard loupeCursorPoint != .zero else { return }
        let oldPt = loupeCursorPoint
        let radius = currentLoupeSize / 2 + 4
        loupeCursorPoint = .zero
        invalidateCursorPreview(oldCanvas: oldPt, newCanvas: oldPt, radius: radius)
    }

    func clearDrawingCursorPreview() {
        guard drawingCursorPoint != .zero else { return }
        let oldPt = drawingCursorPoint
        let radius = drawingCursorRadius + 4
        drawingCursorPoint = .zero
        smartMarkerLineHeight = nil
        invalidateCursorPreview(oldCanvas: oldPt, newCanvas: oldPt, radius: radius)
    }

    // MARK: - Cursor Preview Drawing

    func drawToolCursorTicks(at center: NSPoint, radius: CGFloat, color: NSColor) {
        let inner = radius + 2
        let outer = radius + 7
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineWidth = 1.25
        path.move(to: NSPoint(x: center.x, y: center.y + inner))
        path.line(to: NSPoint(x: center.x, y: center.y + outer))
        path.move(to: NSPoint(x: center.x + inner, y: center.y))
        path.line(to: NSPoint(x: center.x + outer, y: center.y))
        path.move(to: NSPoint(x: center.x, y: center.y - inner))
        path.line(to: NSPoint(x: center.x, y: center.y - outer))
        path.move(to: NSPoint(x: center.x - inner, y: center.y))
        path.line(to: NSPoint(x: center.x - outer, y: center.y))
        color.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }

    func drawStrokeDotCursorPreview(
        at center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        filled: Bool
    ) {
        let dotRadius = max(radius, 5)
        let circleRect = NSRect(
            x: center.x - dotRadius,
            y: center.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2)
        let path = NSBezierPath(ovalIn: circleRect)
        if filled {
            color.withAlphaComponent(0.95).setFill()
            path.fill()
            let border = NSBezierPath(ovalIn: circleRect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1.0
            NSColor.white.withAlphaComponent(0.55).setStroke()
            border.stroke()
            let inner = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
            inner.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.22).setStroke()
            inner.stroke()
        } else {
            color.withAlphaComponent(0.28).setFill()
            path.fill()
            path.lineWidth = max(1.0, min(activeDrawingPreviewStrokeWidth * 0.22, 1.8))
            color.withAlphaComponent(0.95).setStroke()
            path.stroke()
        }
    }

    func drawMeasureCursorPreview(at center: NSPoint, color: NSColor) {
        let scale = max(isInsideScrollView ? 1 : zoomLevel, 0.001)
        let majorStart: CGFloat = 9 / scale
        let majorEnd: CGFloat = 14 / scale
        let lineHalf: CGFloat = 8 / scale
        let capHeight: CGFloat = 3.5 / scale
        let notchHalf: CGFloat = 2.5 / scale

        let tickPath = NSBezierPath()
        tickPath.lineCapStyle = .round
        tickPath.lineWidth = 1.25 / scale
        tickPath.move(to: NSPoint(x: center.x, y: center.y + majorStart))
        tickPath.line(to: NSPoint(x: center.x, y: center.y + majorEnd))
        tickPath.move(to: NSPoint(x: center.x + majorStart, y: center.y))
        tickPath.line(to: NSPoint(x: center.x + majorEnd, y: center.y))
        tickPath.move(to: NSPoint(x: center.x, y: center.y - majorStart))
        tickPath.line(to: NSPoint(x: center.x, y: center.y - majorEnd))
        tickPath.move(to: NSPoint(x: center.x - majorStart, y: center.y))
        tickPath.line(to: NSPoint(x: center.x - majorEnd, y: center.y))
        color.withAlphaComponent(0.9).setStroke()
        tickPath.stroke()

        let linePath = NSBezierPath()
        linePath.lineCapStyle = .round
        linePath.lineWidth = 1.6 / scale
        linePath.move(to: NSPoint(x: center.x - lineHalf, y: center.y))
        linePath.line(to: NSPoint(x: center.x + lineHalf, y: center.y))
        color.withAlphaComponent(0.95).setStroke()
        linePath.stroke()

        let capPath = NSBezierPath()
        capPath.lineCapStyle = .round
        capPath.lineWidth = 1.4 / scale
        capPath.move(to: NSPoint(x: center.x - lineHalf, y: center.y - capHeight))
        capPath.line(to: NSPoint(x: center.x - lineHalf, y: center.y + capHeight))
        capPath.move(to: NSPoint(x: center.x + lineHalf, y: center.y - capHeight))
        capPath.line(to: NSPoint(x: center.x + lineHalf, y: center.y + capHeight))
        color.withAlphaComponent(0.95).setStroke()
        capPath.stroke()

        let notchPath = NSBezierPath()
        notchPath.lineCapStyle = .round
        notchPath.lineWidth = 1.0 / scale
        notchPath.move(to: NSPoint(x: center.x, y: center.y - notchHalf))
        notchPath.line(to: NSPoint(x: center.x, y: center.y + notchHalf))
        color.withAlphaComponent(0.75).setStroke()
        notchPath.stroke()
    }

    func drawShapeToolCursorPreview(
        at center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        shape: AnnotationTool
    ) {
        drawToolCursorTicks(at: center, radius: radius, color: color)

        let rect = NSRect(x: center.x - 5.5, y: center.y - 4.5, width: 11, height: 9)
        let path: NSBezierPath
        switch shape {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        default:
            path = NSBezierPath(
                roundedRect: rect,
                xRadius: shape == .filledRectangle ? 2.5 : 2,
                yRadius: shape == .filledRectangle ? 2.5 : 2)
        }

        if shape == .filledRectangle {
            color.withAlphaComponent(0.25).setFill()
            path.fill()
        }
        path.lineWidth = max(1.2, min(activeDrawingPreviewStrokeWidth * 0.32, 2.2))
        color.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }

    func drawNumberToolCursorPreview(at center: NSPoint, radius: CGFloat, color: NSColor) {
        let circleRadius = radius
        let circleRect = NSRect(
            x: center.x - circleRadius,
            y: center.y - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2)
        let circle = NSBezierPath(ovalIn: circleRect)
        color.withAlphaComponent(0.98).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        circle.lineWidth = 0.8
        circle.stroke()

        let nextNumber = currentNumberFormat.format(numberCounter + numberStartAt)
        let fontSize = circleRadius * 1.1
        if let cgContext = NSGraphicsContext.current?.cgContext {
            NumberCalloutTextLayout.draw(
                text: nextNumber,
                font: NSFont.boldSystemFont(ofSize: fontSize),
                fillColor: color,
                in: circleRect,
                cgContext: cgContext)
        }
    }

    func drawCensorToolCursorPreview(
        at center: NSPoint,
        radius: CGFloat,
        color: NSColor,
        isBlur: Bool
    ) {
        let side = min(max(radius * 1.25, 18), 28)
        let rect = NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        let fillColor = isBlur ? color.withAlphaComponent(0.12) : color.withAlphaComponent(0.08)
        fillColor.setFill()
        path.fill()
        path.lineWidth = 1.2
        let borderColor = isBlur ? color.withAlphaComponent(0.95) : color.withAlphaComponent(0.9)
        borderColor.setStroke()
        let dashPattern: [CGFloat] = isBlur ? [4, 3] : [2, 2]
        path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        path.stroke()

        let innerStep = side / 4
        let grid = NSBezierPath()
        grid.lineWidth = 0.9
        grid.lineCapStyle = .round
        for index in 1..<4 {
            let x = rect.minX + innerStep * CGFloat(index)
            grid.move(to: NSPoint(x: x, y: rect.minY + 3))
            grid.line(to: NSPoint(x: x, y: rect.maxY - 3))
            let y = rect.minY + innerStep * CGFloat(index)
            grid.move(to: NSPoint(x: rect.minX + 3, y: y))
            grid.line(to: NSPoint(x: rect.maxX - 3, y: y))
        }
        borderColor.withAlphaComponent(isBlur ? 0.35 : 0.55).setStroke()
        grid.stroke()
    }

    func drawDrawingCursorPreview(at center: NSPoint) {
        let radius = drawingCursorCoreRadius
        let color = activeDrawingPreviewColor

        if currentTool == .marker && smartMarkerEnabled {
            // Smart marker: vertical pill that scales to text line height
            let h = smartMarkerLineHeight ?? currentMarkerSize
            let w: CGFloat = min(h * 0.55, 14)
            let pillRect = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: w / 2, yRadius: w / 2)
            currentColor.withAlphaComponent(0.45).setFill()
            pill.fill()
            currentColor.withAlphaComponent(0.8).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()
            return
        }

        if currentTool == .marker {
            let circleRect = NSRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let path = NSBezierPath(ovalIn: circleRect)
            currentColor.withAlphaComponent(0.35).setFill()
            path.fill()
            currentColor.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 1.0
            path.stroke()
            return
        }

        if currentTool == .pencil {
            // Pencil: solid dot at stroke width (fixed size — don't scale by pressure
            // to avoid distracting size ripple while moving the cursor)
            let circleRect = NSRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let path = NSBezierPath(ovalIn: circleRect)
            annotationColor.setFill()
            path.fill()
            let border = NSBezierPath(ovalIn: circleRect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1.0
            NSColor.white.withAlphaComponent(0.6).setStroke()
            border.stroke()
            let inner = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
            inner.lineWidth = 0.5
            NSColor.black.withAlphaComponent(0.3).setStroke()
            inner.stroke()
            return
        }

        switch currentTool {
        case .line, .arrow:
            drawStrokeDotCursorPreview(at: center, radius: radius, color: color, filled: true)
        case .measure:
            drawMeasureCursorPreview(at: center, color: color)
        case .rectangle, .filledRectangle, .ellipse:
            drawShapeToolCursorPreview(at: center, radius: radius, color: color, shape: currentTool)
        case .number:
            drawNumberToolCursorPreview(at: center, radius: radius, color: color)
        case .pixelate:
            drawCensorToolCursorPreview(at: center, radius: radius, color: color, isBlur: false)
        case .blur:
            drawCensorToolCursorPreview(at: center, radius: radius, color: color, isBlur: true)
        default:
            break
        }
    }

    // MARK: - Loupe Preview

    func drawLoupePreview(at center: NSPoint) {
        guard let screenshot = screenshotImage, let context = NSGraphicsContext.current else {
            return
        }
        let size = currentLoupeSize
        let squareRect = NSRect(
            x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let magnification: CGFloat = 2.0

        context.saveGraphicsState()
        context.cgContext.setAlpha(0.75)

        // Clip to circle
        let path = NSBezierPath(ovalIn: squareRect)
        path.addClip()

        // Draw magnified region directly from screenshot (no intermediate image)
        let srcSize = size / magnification
        let srcRect = NSRect(
            x: center.x - srcSize / 2, y: center.y - srcSize / 2, width: srcSize, height: srcSize)
        let imgSize = screenshot.size
        let drawRect = captureDrawRect
        let scaleX = imgSize.width / drawRect.width
        let scaleY = imgSize.height / drawRect.height
        let fromRect = NSRect(
            x: (srcRect.origin.x - drawRect.origin.x) * scaleX,
            y: (srcRect.origin.y - drawRect.origin.y) * scaleY,
            width: srcRect.width * scaleX, height: srcRect.height * scaleY)
        screenshot.draw(in: squareRect, from: fromRect, operation: .copy, fraction: 1.0)

        // Outer + inner border so the loupe edge stays visible on light and dark backgrounds
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 4
        path.stroke()

        NSColor.white.withAlphaComponent(0.82).setStroke()
        path.lineWidth = 2
        path.stroke()

        context.restoreGraphicsState()
    }
}
