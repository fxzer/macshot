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

    /// 文字框的高度始终跟随排版结果，所以只有四个角和左右两条边有手柄。
    private func liveTextHandleCenters(for frame: NSRect) -> [(ResizeHandle, NSPoint)] {
        [
            (.bottomLeft, NSPoint(x: frame.minX, y: frame.minY)),
            (.bottomRight, NSPoint(x: frame.maxX, y: frame.minY)),
            (.topLeft, NSPoint(x: frame.minX, y: frame.maxY)),
            (.topRight, NSPoint(x: frame.maxX, y: frame.maxY)),
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
            let previousFrame = scrollView.frame
            let newFrame = resizedLiveTextFrame(at: point)
            textEditor.applyLiveFrame(newFrame)
            toolOptionsRowView?.updateFontSizeDisplay(value: textEditor.fontSize)
            invalidateLiveTextFrames([previousFrame, newFrame])
            return true
        }
        if isDraggingTextBox {
            let previousFrame = scrollView.frame
            scrollView.frame.origin = NSPoint(
                x: textBoxDragOrigFrame.minX + point.x - textBoxDragStart.x,
                y: textBoxDragOrigFrame.minY + point.y - textBoxDragStart.y)
            NSCursor.closedHand.set()
            invalidateLiveTextFrames([previousFrame, scrollView.frame])
            return true
        }
        return false
    }

    /// 拖动缩放时文字框的新位置与大小。框始终贴着排好版的文字：
    /// 左右手柄只改换行宽度，顶边不动；角手柄以对角为锚点等比缩放字号。
    private func resizedLiveTextFrame(at point: NSPoint) -> NSRect {
        let orig = textBoxOrigFrame
        let dx = point.x - textBoxResizeStart.x
        // 新建框可能比常规最小值窄，按下手柄时不应突然跳大。
        let minW = min(60, orig.width)

        switch textBoxResizeHandle {
        case .right:
            return liveTextFrame(width: max(minW, orig.width + dx), minX: orig.minX)
        case .left:
            let minX = min(orig.maxX - minW, orig.minX + dx)
            return liveTextFrame(width: orig.maxX - minX, minX: minX)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let onLeft = textBoxResizeHandle == .topLeft || textBoxResizeHandle == .bottomLeft
            let onBottom = textBoxResizeHandle == .bottomLeft || textBoxResizeHandle == .bottomRight
            let anchor = NSPoint(x: onLeft ? orig.maxX : orig.minX, y: onBottom ? orig.maxY : orig.minY)
            let diagonal = NSPoint(x: onLeft ? -orig.width : orig.width, y: onBottom ? -orig.height : orig.height)
            let scale = liveTextCornerScale(at: point, anchor: anchor, diagonal: diagonal)
            // 换行宽度里的文字部分随字号等比变化，左右内边距保持不变，每一行的断行位置因此不变。
            let insets = textEditor.liveTextHorizontalInsets
            let width = max(1, orig.width - insets) * scale + insets
            // 锚定在对角。文字视图的原点对齐到整点，字形不会落在亚像素位置上发虚、抖动。
            let minX = onLeft ? (orig.maxX - width).rounded(.down) : orig.minX
            let frameWidth = onLeft ? orig.maxX - minX : width
            let height = textEditor.relayoutLiveText(fontSize: textBoxOrigFontSize * scale, width: frameWidth)
            return NSRect(
                x: minX,
                y: onBottom ? orig.maxY - height : orig.minY,
                width: frameWidth,
                height: height)
        default:
            return orig
        }
    }

    /// 左右手柄：顶边不动，高度取排版结果。
    private func liveTextFrame(width: CGFloat, minX: CGFloat) -> NSRect {
        let height = textEditor.relayoutLiveText(width: width)
        return NSRect(x: minX, y: textBoxOrigFrame.maxY - height, width: width, height: height)
    }

    /// 角手柄的缩放比例：鼠标位置在对角线上的投影，沿对角线拖回锚点时缩小。
    /// 字号限制在 6 到 200，缩放随之封顶。
    private func liveTextCornerScale(at point: NSPoint, anchor: NSPoint, diagonal: NSPoint) -> CGFloat {
        let lengthSquared = diagonal.x * diagonal.x + diagonal.y * diagonal.y
        guard lengthSquared > 0.01, textBoxOrigFontSize > 0 else { return 1 }
        let projected = ((point.x - anchor.x) * diagonal.x + (point.y - anchor.y) * diagonal.y) / lengthSquared
        return min(200 / textBoxOrigFontSize, max(6 / textBoxOrigFontSize, projected))
    }

    /// 只重绘文字框新旧位置覆盖的区域。整屏重绘要重新画底图和遮罩，内置屏分辨率下离屏实测约 15 毫秒一帧，
    /// 拖动会明显掉帧；边框、手柄和底色都画在框外 4 点以内。
    /// 编辑器里 NSScrollView 的放大管线对局部重绘会留残影，保持整屏重绘。
    private func invalidateLiveTextFrames(_ frames: [NSRect]) {
        if isEditorMode {
            needsDisplay = true
            return
        }
        for frame in frames where !frame.isEmpty {
            setNeedsDisplay(frame.insetBy(dx: -8, dy: -8))
        }
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
