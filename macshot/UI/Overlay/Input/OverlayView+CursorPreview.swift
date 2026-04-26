//
//  OverlayView+CursorPreview.swift
//  macshot
//
//  Tool cursor preview state, updates, and drawing for OverlayView.
//

import AppKit

extension OverlayView {

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
        let r = (radius + margin) * zoomLevel
        if oldCanvas != .zero {
            let oldView = canvasToView(oldCanvas)
            setNeedsDisplay(
                NSRect(x: oldView.x - r, y: oldView.y - r, width: r * 2, height: r * 2))
        }
        let newView = canvasToView(newCanvas)
        setNeedsDisplay(
            NSRect(x: newView.x - r, y: newView.y - r, width: r * 2, height: r * 2))
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
                canvasStampPt.y - (stampPreviewPoint?.y ?? 0)
            ) > 0.5
        {
            let oldPt = stampPreviewPoint ?? .zero
            stampPreviewPoint = canvasStampPt
            invalidateCursorPreview(
                oldCanvas: oldPt, newCanvas: canvasStampPt, radius: stampPreviewRadius)
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
        invalidateCursorPreview(
            oldCanvas: oldPt, newCanvas: oldPt, radius: stampPreviewRadius)
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
        let rect = NSRect(
            x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
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
}
