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

        // 1. 先检测 4 个角手柄（优先级最高，热区设为宽敞的 24x24 像素，以角点为中心扩展）
        let cornerHitSize: CGFloat = max(24, handleSize + 10)
        let halfCorner = cornerHitSize / 2
        if NSRect(x: r.minX - halfCorner, y: r.maxY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .topLeft
        }
        if NSRect(x: r.maxX - halfCorner, y: r.maxY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .topRight
        }
        if NSRect(x: r.minX - halfCorner, y: r.minY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .bottomLeft
        }
        if NSRect(x: r.maxX - halfCorner, y: r.minY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .bottomRight
        }

        // 2. 四条边框的拖拽热区宽度：由原先极窄的 6px 拓宽至 18px（边框线内外各 9px），彻底消除误触重新框选
        let edgeThickness: CGFloat = 18
        let halfEdge = edgeThickness / 2
        if NSRect(x: r.minX, y: r.maxY - halfEdge, width: r.width, height: edgeThickness).contains(point) {
            return .top
        }
        if NSRect(x: r.minX, y: r.minY - halfEdge, width: r.width, height: edgeThickness).contains(point) {
            return .bottom
        }
        if NSRect(x: r.minX - halfEdge, y: r.minY, width: edgeThickness, height: r.height).contains(point) {
            return .left
        }
        if NSRect(x: r.maxX - halfEdge, y: r.minY, width: edgeThickness, height: r.height).contains(point) {
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

        let cornerHitSize: CGFloat = max(24, handleSize + 10)
        let halfCorner = cornerHitSize / 2
        if NSRect(x: r.minX - halfCorner, y: r.maxY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .topLeft
        }
        if NSRect(x: r.maxX - halfCorner, y: r.maxY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .topRight
        }
        if NSRect(x: r.minX - halfCorner, y: r.minY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .bottomLeft
        }
        if NSRect(x: r.maxX - halfCorner, y: r.minY - halfCorner, width: cornerHitSize, height: cornerHitSize).contains(point) {
            return .bottomRight
        }

        let edgeThickness: CGFloat = 18
        let halfEdge = edgeThickness / 2
        if NSRect(x: r.minX, y: r.maxY - halfEdge, width: r.width, height: edgeThickness).contains(point) {
            return .top
        }
        if NSRect(x: r.minX, y: r.minY - halfEdge, width: r.width, height: edgeThickness).contains(point) {
            return .bottom
        }
        if NSRect(x: r.minX - halfEdge, y: r.minY, width: edgeThickness, height: r.height).contains(point) {
            return .left
        }
        if NSRect(x: r.maxX - halfEdge, y: r.minY, width: edgeThickness, height: r.height).contains(point) {
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
