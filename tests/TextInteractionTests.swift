import AppKit

// 仅替代画布其余模块；事件路由、命中和拖动代码直接加载生产文件。
@MainActor
final class TestTextEditor {
    var fontSize: CGFloat = 20
    let scrollView: NSScrollView?
    let textView: NSTextView?

    init() {
        let scroll = NSScrollView(frame: NSRect(x: 40, y: 80, width: 240, height: 100))
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.frame.size))
        text.string = "可以选字，也可以拖动整个文本框"
        scroll.documentView = text
        scrollView = scroll
        textView = text
    }

    func lockWidth() {}
    func scaleLiveText(to size: CGFloat) { fontSize = size }
    func applyLiveFrame(_ frame: NSRect, fitHeightToContent: Bool) {
        scrollView?.frame = frame
        textView?.frame.size = frame.size
    }
}

@MainActor
final class TestOptionsRow: NSView {
    func updateFontSizeDisplay(value: CGFloat) {}
}

@MainActor
class OverlayView: NSView {
    enum ResizeHandle { case none, topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, move }
    var isSharingActive = false
    var isEditorMode = false
    var chromeParentView: NSView?
    var bottomStripView: NSView?
    var rightStripView: NSView?
    var toolOptionsRowView: TestOptionsRow?
    var showToolbars = true
    let textEditor = TestTextEditor()
    var textEditView: NSTextView? { textEditor.textView }
    var isResizingTextBox = false
    var isDraggingTextBox = false
    var textBoxResizeHandle: ResizeHandle = .none
    var textBoxResizeStart = NSPoint.zero
    var textBoxOrigFrame = NSRect.zero
    var textBoxOrigFontSize: CGFloat = 0
    var textBoxDragStart = NSPoint.zero
    var textBoxDragOrigFrame = NSRect.zero
    func findTopBar() -> NSView? { nil }
    func cursorForHandle(_ handle: ResizeHandle) -> NSCursor { .arrow }
    func updateCursorForCurrentTool() {}
}

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("失败：\(description)") }
}

@MainActor
func runTextInteractionTests() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let host = window.contentView!
    let canvas = OverlayView(frame: NSRect(x: 30, y: 40, width: 800, height: 600))
    host.addSubview(canvas)
    let scrollView = canvas.textEditor.scrollView!
    canvas.addSubview(scrollView)
    scrollView.layoutSubtreeIfNeeded()
    let original = scrollView.frame

    func target(_ point: NSPoint) -> NSView? {
        canvas.hitTest(canvas.convert(point, to: host))
    }

    let body = NSPoint(x: original.midX, y: original.midY)
    check(target(body) is NSTextView, "正文应交给 NSTextView 输入和选字")

    for zoom: CGFloat in [0.25, 0.5, 1, 2] {
        canvas.bounds.size = NSSize(width: canvas.frame.width / zoom, height: canvas.frame.height / zoom)
        check(abs(canvas.liveTextViewScale - zoom) < 0.001, "读取实际窗口缩放")
        let topInside = NSPoint(x: original.minX + 36, y: original.maxY - 1)
        check(target(topInside) === canvas, "缩放 \(zoom)：上边框内侧不能被文本视图吞掉")
        let leftInside = NSPoint(x: original.minX + 1, y: original.midY)
        check(target(leftInside) === canvas, "缩放 \(zoom)：左手柄内侧应路由给画布")
        let grip = NSPoint(x: original.midX, y: original.maxY + 13 / zoom)
        check(target(grip) === canvas, "缩放 \(zoom)：外侧 13 点可开始移动")
        check(canvas.hitTestLiveTextResizeHandle(at: grip, frame: original) == nil, "拖动外圈不应抢成调整大小")
        check(target(body) is NSTextView, "缩放 \(zoom)：正文保持可编辑")
        check(!canvas.liveTextChromeContains(NSPoint(x: original.minX + 4, y: original.midY)), "正文 4 点内边距不应被吞掉")
        check(canvas.liveTextResizeHandleRects(for: original).allSatisfy { abs($0.width * zoom - 6) < 0.001 }, "手柄在窗口中保持可见大小")
    }
    canvas.bounds.size = canvas.frame.size

    let handles: [(OverlayView.ResizeHandle, NSPoint)] = [
        (.topLeft, NSPoint(x: original.minX - 8, y: original.maxY + 8)),
        (.topRight, NSPoint(x: original.maxX + 8, y: original.maxY + 8)),
        (.bottomLeft, NSPoint(x: original.minX - 8, y: original.minY - 8)),
        (.bottomRight, NSPoint(x: original.maxX + 8, y: original.minY - 8)),
        (.top, NSPoint(x: original.midX, y: original.maxY + 8)),
        (.bottom, NSPoint(x: original.midX, y: original.minY - 8)),
        (.left, NSPoint(x: original.minX - 8, y: original.midY)),
        (.right, NSPoint(x: original.maxX + 8, y: original.midY)),
    ]
    for (handle, point) in handles {
        check(target(point) === canvas, "八个方向均由画布接收")
        check(canvas.beginLiveTextInteraction(at: point) && canvas.textBoxResizeHandle == handle, "显示调整光标的方向确实可以开始操作")
        _ = canvas.endLiveTextInteraction()
    }

    let left = NSPoint(x: original.minX + 1, y: original.midY)
    check(canvas.beginLiveTextInteraction(at: left), "可按住左手柄")
    check(canvas.textBoxResizeHandle == .left, "左侧不是虚假的调整光标")
    check(canvas.updateLiveTextInteraction(at: NSPoint(x: left.x - 25, y: left.y)), "左侧拖动有实际处理")
    check(scrollView.frame.minX == original.minX - 25 && scrollView.frame.maxX == original.maxX, "左侧调整保持右边锚点")
    check(canvas.endLiveTextInteraction() && !canvas.isResizingTextBox, "松开清理调整状态")

    scrollView.frame = original
    let top = NSPoint(x: original.midX, y: original.maxY - 1)
    check(canvas.beginLiveTextInteraction(at: top), "可按住上手柄")
    check(canvas.textBoxResizeHandle == .top, "上侧不是虚假的调整光标")
    _ = canvas.updateLiveTextInteraction(at: NSPoint(x: top.x, y: top.y + 20))
    check(scrollView.frame.maxY == original.maxY + 20 && scrollView.frame.minY == original.minY, "上侧调整保持下边锚点")
    _ = canvas.endLiveTextInteraction()

    scrollView.frame = original
    let grip = NSPoint(x: original.midX, y: original.maxY + 13)
    check(canvas.beginLiveTextInteraction(at: grip) && canvas.isDraggingTextBox, "抓手外圈确实开始移动")
    _ = canvas.updateLiveTextInteraction(at: NSPoint(x: grip.x + 45, y: grip.y - 30))
    check(scrollView.frame.origin == NSPoint(x: original.minX + 45, y: original.minY - 30), "文本框跟随鼠标位移")
    check(scrollView.frame.size == original.size, "移动不改变文本框大小")
    canvas.resetLiveTextInteraction()
    check(!canvas.isDraggingTextBox && !canvas.isResizingTextBox, "取消或提交后无残留拖动状态")

    scrollView.frame = NSRect(x: 40, y: 80, width: 56, height: 32)
    let narrow = scrollView.frame
    let right = NSPoint(x: narrow.maxX, y: narrow.midY)
    _ = canvas.beginLiveTextInteraction(at: right)
    _ = canvas.updateLiveTextInteraction(at: right)
    check(scrollView.frame == narrow, "新建小框按下调整手柄不能突然跳大")
    _ = canvas.endLiveTextInteraction()

    scrollView.frame = original
    canvas.showToolbars = false
    check(!canvas.liveTextChromeContains(left), "隐藏手柄时关闭边缘热区")
    check(target(left) !== canvas, "隐藏状态的文本正文仍交给原生视图")
    canvas.showToolbars = true
    let toolbar = NSView(frame: NSRect(x: original.minX - 5, y: original.midY - 8, width: 20, height: 16))
    canvas.addSubview(toolbar)
    canvas.bottomStripView = toolbar
    check(target(left) === toolbar, "工具栏优先于重叠的文本手柄")
    canvas.isSharingActive = true
    check(target(left) == nil, "共享状态不抢事件")
    canvas.isSharingActive = false
    canvas.isEditorMode = true
    canvas.chromeParentView = host
    toolbar.removeFromSuperview()
    host.addSubview(toolbar)
    let toolbarPoint = canvas.convert(left, to: host)
    toolbar.frame = NSRect(x: toolbarPoint.x - 4, y: toolbarPoint.y - 4, width: 16, height: 16)
    check(target(left) == nil, "编辑器中兄弟工具栏按窗口坐标优先接收事件")
    toolbar.removeFromSuperview()
    canvas.bottomStripView = nil
    check(target(left) === canvas, "编辑器正文中的边缘仍能开始操作")
    check(target(body) is NSTextView, "编辑器正文仍可选字")
    print("通过：原生事件路由、正文选字、4 档缩放、上/左调整、移动、取消、小框及工具栏优先级。")
}

MainActor.assumeIsolated { runTextInteractionTests() }
