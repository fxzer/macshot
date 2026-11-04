//
//  OverlayView+HandleHitTesting.swift
//  macshot
//
//  Selection and remote resize handle hit testing.
//

import AppKit

extension OverlayView {

    // MARK: - Handle hit testing

    func allHandleRects() -> [(ResizeHandle, NSRect)] {
        let r = selectionRect
        let s = handleSize
        return [
            (.topLeft, NSRect(x: r.minX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.topRight, NSRect(x: r.maxX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottomLeft, NSRect(x: r.minX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.bottomRight, NSRect(x: r.maxX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.top, NSRect(x: r.midX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottom, NSRect(x: r.midX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.left, NSRect(x: r.minX - s / 2, y: r.midY - s / 2, width: s, height: s)),
            (.right, NSRect(x: r.maxX - s / 2, y: r.midY - s / 2, width: s, height: s)),
        ]
    }

    func hitTestHandle(at point: NSPoint) -> ResizeHandle {
        let r = selectionRect
        guard r.width >= 1, r.height >= 1 else { return .none }

        // 1. 四个角手柄：外侧保持 12px 宽敞捕获，内侧收窄至 4px 避免误触
        let outerCorner: CGFloat = 12.0
        let innerCorner: CGFloat = 4.0
        let cornerW = outerCorner + innerCorner
        let cornerH = outerCorner + innerCorner

        // TopLeft
        if NSRect(x: r.minX - outerCorner, y: r.maxY - innerCorner, width: cornerW, height: cornerH).contains(point) {
            return .topLeft
        }
        // TopRight
        if NSRect(x: r.maxX - innerCorner, y: r.maxY - innerCorner, width: cornerW, height: cornerH).contains(point) {
            return .topRight
        }
        // BottomLeft
        if NSRect(x: r.minX - outerCorner, y: r.minY - outerCorner, width: cornerW, height: cornerH).contains(point) {
            return .bottomLeft
        }
        // BottomRight
        if NSRect(x: r.maxX - innerCorner, y: r.minY - outerCorner, width: cornerW, height: cornerH).contains(point) {
            return .bottomRight
        }

        // 2. 四条边框：采用内外不对称热区。外侧保持 9px 宽敞命中带防滑出误触重新框选；
        //    内侧收窄至 3px，大幅释放框内操作空间，彻底解决框内操作误触调框大小的问题。
        let outerEdge: CGFloat = 9.0
        let innerEdge: CGFloat = 3.0
        let edgeSpan = outerEdge + innerEdge

        // Top
        if NSRect(x: r.minX, y: r.maxY - innerEdge, width: r.width, height: edgeSpan).contains(point) {
            return .top
        }
        // Bottom
        if NSRect(x: r.minX, y: r.minY - outerEdge, width: r.width, height: edgeSpan).contains(point) {
            return .bottom
        }
        // Left
        if NSRect(x: r.minX - outerEdge, y: r.minY, width: edgeSpan, height: r.height).contains(point) {
            return .left
        }
        // Right
        if NSRect(x: r.maxX - innerEdge, y: r.minY, width: edgeSpan, height: r.height).contains(point) {
            return .right
        }

        return .none
    }

    func handleRectsForRect(_ r: NSRect) -> [(ResizeHandle, NSRect)] {
        let s = handleSize
        return [
            (.topLeft, NSRect(x: r.minX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.topRight, NSRect(x: r.maxX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottomLeft, NSRect(x: r.minX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.bottomRight, NSRect(x: r.maxX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.top, NSRect(x: r.midX - s / 2, y: r.maxY - s / 2, width: s, height: s)),
            (.bottom, NSRect(x: r.midX - s / 2, y: r.minY - s / 2, width: s, height: s)),
            (.left, NSRect(x: r.minX - s / 2, y: r.midY - s / 2, width: s, height: s)),
            (.right, NSRect(x: r.maxX - s / 2, y: r.midY - s / 2, width: s, height: s)),
        ]
    }

    func hitTestRemoteHandle(at point: NSPoint) -> ResizeHandle {
        let r = remoteSelectionRect
        guard r.width >= 1, r.height >= 1 else { return .none }

        let outerCorner: CGFloat = 12.0
        let innerCorner: CGFloat = 4.0
        let cornerW = outerCorner + innerCorner
        let cornerH = outerCorner + innerCorner

        if NSRect(x: r.minX - outerCorner, y: r.maxY - innerCorner, width: cornerW, height: cornerH).contains(point) {
            return .topLeft
        }
        if NSRect(x: r.maxX - innerCorner, y: r.maxY - innerCorner, width: cornerW, height: cornerH).contains(point) {
            return .topRight
        }
        if NSRect(x: r.minX - outerCorner, y: r.minY - outerCorner, width: cornerW, height: cornerH).contains(point) {
            return .bottomLeft
        }
        if NSRect(x: r.maxX - innerCorner, y: r.minY - outerCorner, width: cornerW, height: cornerH).contains(point) {
            return .bottomRight
        }

        let outerEdge: CGFloat = 9.0
        let innerEdge: CGFloat = 3.0
        let edgeSpan = outerEdge + innerEdge

        if NSRect(x: r.minX, y: r.maxY - innerEdge, width: r.width, height: edgeSpan).contains(point) {
            return .top
        }
        if NSRect(x: r.minX, y: r.minY - outerEdge, width: r.width, height: edgeSpan).contains(point) {
            return .bottom
        }
        if NSRect(x: r.minX - outerEdge, y: r.minY, width: edgeSpan, height: r.height).contains(point) {
            return .left
        }
        if NSRect(x: r.maxX - innerEdge, y: r.minY, width: edgeSpan, height: r.height).contains(point) {
            return .right
        }
        return .none
    }

    func drawRemoteResizeHandles() {
        for (_, rect) in handleRectsForRect(remoteSelectionRect) {
            ToolbarLayout.handleColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    func anchorForHandle(_ handle: ResizeHandle, in r: NSRect) -> NSPoint {
        switch handle {
        case .topLeft: return NSPoint(x: r.maxX, y: r.minY)
        case .topRight: return NSPoint(x: r.minX, y: r.minY)
        case .bottomLeft: return NSPoint(x: r.maxX, y: r.maxY)
        case .bottomRight: return NSPoint(x: r.minX, y: r.maxY)
        case .top: return NSPoint(x: r.midX, y: r.minY)
        case .bottom: return NSPoint(x: r.midX, y: r.maxY)
        case .left: return NSPoint(x: r.maxX, y: r.midY)
        case .right: return NSPoint(x: r.minX, y: r.midY)
        case .none, .move: return .zero
        }
    }
}
