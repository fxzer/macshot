import AppKit

extension OverlayView {
    /// 以窗口中的点数定义热区，避免编辑器缩小后拖动区域也一起缩没。
    var liveTextViewScale: CGFloat {
        max(0.01, abs(convert(NSRect(x: 0, y: 0, width: 1, height: 1), to: nil).width))
    }

    func liveTextChromeContains(_ point: NSPoint) -> Bool {
        guard showToolbars, textEditView != nil, let scrollView = textEditor.scrollView else { return false }
        return hitTestLiveTextResizeHandle(at: point, frame: scrollView.frame) != nil
            || isPointOnLiveTextDragEdge(point, frame: scrollView.frame)
    }

    private func liveTextHandleCenters(for frame: NSRect) -> [(ResizeHandle, NSPoint)] {
        [
            (.bottomLeft, NSPoint(x: frame.minX, y: frame.minY)),
            (.bottomRight, NSPoint(x: frame.maxX, y: frame.minY)),
            (.topLeft, NSPoint(x: frame.minX, y: frame.maxY)),
            (.topRight, NSPoint(x: frame.maxX, y: frame.maxY)),
            (.bottom, NSPoint(x: frame.midX, y: frame.minY)),
            (.top, NSPoint(x: frame.midX, y: frame.maxY)),
            (.left, NSPoint(x: frame.minX, y: frame.midY)),
            (.right, NSPoint(x: frame.maxX, y: frame.midY)),
        ]
    }

    func liveTextResizeHandleRects(for frame: NSRect) -> [NSRect] {
        let size = 6 / liveTextViewScale
        return liveTextHandleCenters(for: frame).map { _, center in
            NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        }
    }

    func hitTestLiveTextResizeHandle(at point: NSPoint, frame: NSRect) -> ResizeHandle? {
        guard !frame.isEmpty else { return nil }
        let scale = liveTextViewScale
        let outside = 10 / scale
        let inside = min(3, min(3 / scale, min(frame.width, frame.height) / 4))
        let halfSpan = 8 / scale

        // 热区主要扩向框外，框内保留正文的插入光标和选字操作。
        for (handle, center) in liveTextHandleCenters(for: frame) {
            let rect: NSRect
            switch handle {
            case .bottomLeft:
                rect = NSRect(x: center.x - outside, y: center.y - outside, width: outside + inside, height: outside + inside)
            case .bottomRight:
                rect = NSRect(x: center.x - inside, y: center.y - outside, width: outside + inside, height: outside + inside)
            case .topLeft:
                rect = NSRect(x: center.x - outside, y: center.y - inside, width: outside + inside, height: outside + inside)
            case .topRight:
                rect = NSRect(x: center.x - inside, y: center.y - inside, width: outside + inside, height: outside + inside)
            case .bottom:
                rect = NSRect(x: center.x - halfSpan, y: center.y - outside, width: halfSpan * 2, height: outside + inside)
            case .top:
                rect = NSRect(x: center.x - halfSpan, y: center.y - inside, width: halfSpan * 2, height: outside + inside)
            case .left:
                rect = NSRect(x: center.x - outside, y: center.y - halfSpan, width: outside + inside, height: halfSpan * 2)
            case .right:
                rect = NSRect(x: center.x - inside, y: center.y - halfSpan, width: outside + inside, height: halfSpan * 2)
            default:
                continue
            }
            if rect.contains(point) { return handle }
        }
        return nil
    }

    func isPointOnLiveTextDragEdge(_ point: NSPoint, frame: NSRect) -> Bool {
        guard !frame.isEmpty else { return false }
        let outside = 14 / liveTextViewScale
        let inside = min(3, min(3 / liveTextViewScale, min(frame.width, frame.height) / 4))
        return frame.insetBy(dx: -outside, dy: -outside).contains(point)
            && !frame.insetBy(dx: inside, dy: inside).contains(point)
    }

    func beginLiveTextInteraction(at point: NSPoint) -> Bool {
        guard showToolbars, textEditView != nil, let scrollView = textEditor.scrollView else { return false }
        let frame = scrollView.frame
        if let handle = hitTestLiveTextResizeHandle(at: point, frame: frame) {
            isResizingTextBox = true
            textBoxResizeHandle = handle
            textBoxResizeStart = point
            textBoxOrigFrame = frame
            textBoxOrigFontSize = textEditor.fontSize
            textEditor.lockWidth()
            cursorForHandle(handle).set()
            return true
        }
        if isPointOnLiveTextDragEdge(point, frame: frame) {
            isDraggingTextBox = true
            textBoxDragStart = point
            textBoxDragOrigFrame = frame
            NSCursor.closedHand.set()
            return true
        }
        return frame.contains(point)
    }

    func updateLiveTextInteraction(at point: NSPoint) -> Bool {
        guard let scrollView = textEditor.scrollView else { return false }
        if isResizingTextBox {
            let dx = point.x - textBoxResizeStart.x
            let dy = point.y - textBoxResizeStart.y
            let orig = textBoxOrigFrame
            var newFrame = orig
            // 新建框可能比常规最小值窄，按下手柄时不应突然跳大。
            let minW = min(60, orig.width)
            let minH = min(max(28, textBoxOrigFontSize + 12), orig.height)
            let isCornerHandle: Bool

            switch textBoxResizeHandle {
            case .right:
                newFrame.size.width = max(minW, orig.width + dx)
                isCornerHandle = false
            case .left:
                newFrame.origin.x = min(orig.maxX - minW, orig.minX + dx)
                newFrame.size.width = orig.maxX - newFrame.minX
                isCornerHandle = false
            case .top:
                newFrame.size.height = max(minH, orig.height + dy)
                isCornerHandle = false
            case .bottom:
                newFrame.origin.y = min(orig.maxY - minH, orig.minY + dy)
                newFrame.size.height = orig.maxY - newFrame.minY
                isCornerHandle = false
            case .topRight:
                newFrame.size.width = max(minW, orig.width + dx)
                newFrame.size.height = max(minH, orig.height + dy)
                isCornerHandle = true
            case .topLeft:
                newFrame.origin.x = min(orig.maxX - minW, orig.minX + dx)
                newFrame.size.width = orig.maxX - newFrame.minX
                newFrame.size.height = max(minH, orig.height + dy)
                isCornerHandle = true
            case .bottomRight:
                newFrame.size.width = max(minW, orig.width + dx)
                newFrame.origin.y = min(orig.maxY - minH, orig.minY + dy)
                newFrame.size.height = orig.maxY - newFrame.minY
                isCornerHandle = true
            case .bottomLeft:
                newFrame.origin.x = min(orig.maxX - minW, orig.minX + dx)
                newFrame.size.width = orig.maxX - newFrame.minX
                newFrame.origin.y = min(orig.maxY - minH, orig.minY + dy)
                newFrame.size.height = orig.maxY - newFrame.minY
                isCornerHandle = true
            default:
                isCornerHandle = false
            }

            if isCornerHandle, orig.width > 0, textBoxOrigFontSize > 0 {
                let newFontSize = max(6, min(200, textBoxOrigFontSize * (newFrame.width / orig.width)))
                textEditor.scaleLiveText(to: newFontSize)
                toolOptionsRowView?.updateFontSizeDisplay(value: newFontSize)
            }
            let fitHeight = textBoxResizeHandle == .left || textBoxResizeHandle == .right
            textEditor.applyLiveFrame(newFrame, fitHeightToContent: fitHeight)
            needsDisplay = true
            return true
        }
        if isDraggingTextBox {
            scrollView.frame.origin = NSPoint(
                x: textBoxDragOrigFrame.minX + point.x - textBoxDragStart.x,
                y: textBoxDragOrigFrame.minY + point.y - textBoxDragStart.y)
            NSCursor.closedHand.set()
            needsDisplay = true
            return true
        }
        return false
    }

    func resetLiveTextInteraction() {
        isDraggingTextBox = false
        isResizingTextBox = false
        textBoxResizeHandle = .none
        textBoxOrigFontSize = 0
    }

    func endLiveTextInteraction() -> Bool {
        guard isDraggingTextBox || isResizingTextBox else { return false }
        resetLiveTextInteraction()
        updateCursorForCurrentTool()
        return true
    }
}
