import AppKit

// 仅替代模型与工具栏常量；文本编辑、事件路由、命中和拖动代码直接加载生产文件。
@MainActor enum AnnotationTool { case text }

@MainActor final class Annotation {
    let tool: AnnotationTool
    var startPoint = NSPoint.zero
    var endPoint = NSPoint.zero
    var color = NSColor.white
    var strokeWidth: CGFloat = 2
    var attributedText: NSAttributedString?
    var text = ""
    var fontSize: CGFloat = 20
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isStrikethrough = false
    var fontFamilyName: String?
    var textBgColor: NSColor?
    var textOutlineColor: NSColor?
    var textAlignment: NSTextAlignment = .left
    var textImage: NSImage?
    var textDrawRect = NSRect.zero

    init(tool: AnnotationTool, startPoint: NSPoint, endPoint: NSPoint, color: NSColor, strokeWidth: CGFloat) {
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.strokeWidth = strokeWidth
    }
}

@MainActor enum UndoEntry { case added(Annotation) }
@MainActor enum ToolbarLayout { static let accentColor = NSColor.systemBlue }

@MainActor final class FakeCanvas: TextEditingCanvas {
    var annotations: [Annotation] = []
    var undoStack: [UndoEntry] = []
    var redoStack: [UndoEntry] = []
    var currentColor: NSColor = .green
    var currentStrokeWidth: CGFloat = 2
    var textEditingBounds: NSRect

    init(bounds: NSRect) { textEditingBounds = bounds }

    func viewToCanvas(_ point: NSPoint) -> NSPoint { point }
    func canvasToView(_ point: NSPoint) -> NSPoint { point }
    func opacityAppliedColor(for tool: AnnotationTool) -> NSColor { currentColor }
}

@MainActor final class TestOptionsRow: NSView {
    var shownFontSize: CGFloat = 0

    func updateFontSizeDisplay(value: CGFloat) { shownFontSize = value }
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
    let textEditor = TextEditingController()
    var textEditView: NSTextView? { textEditor.textView }
    var isResizingTextBox = false
    var isDraggingTextBox = false
    var textBoxResizeHandle: ResizeHandle = .none
    var textBoxResizeStart = NSPoint.zero
    var textBoxOrigFrame = NSRect.zero
    var textBoxOrigFontSize: CGFloat = 0
    var textBoxDragStart = NSPoint.zero
    var textBoxDragOrigFrame = NSRect.zero
    // 记录局部重绘请求，以及 AppKit 实际传给 draw(_:) 的范围。
    var invalidRects: [NSRect] = []
    var dirtyRects: [NSRect] = []
    var clipBoxes: [NSRect] = []
    func findTopBar() -> NSView? { nil }
    func cursorForHandle(_ handle: ResizeHandle) -> NSCursor { .arrow }
    func updateCursorForCurrentTool() {}
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidRects.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
    override func draw(_ dirtyRect: NSRect) {
        dirtyRects.append(dirtyRect)
        if let context = NSGraphicsContext.current?.cgContext {
            clipBoxes.append(context.boundingBoxOfClipPath)
        }
    }
}

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("失败：\(description)") }
}

/// 一次完整的拖动缩放：每一步都走生产的排版、外框和重绘路径，并在显示之后检查结果。
@MainActor
struct ResizeProbe {
    var clippedSteps = 0
    var scrolledSteps = 0
    var overflowSteps = 0
    var uncoveredSteps = 0
    var unclippedDraws = 0
    var fullRedrawSteps = 0
    var topInsets = Set<CGFloat>()
    var startFrame = NSRect.zero
    var endFrame = NSRect.zero
    var startFontSize: CGFloat = 0
    var endFontSize: CGFloat = 0
    var shownFontSize: CGFloat = 0

    var staysInsideFrame: Bool { clippedSteps == 0 && scrolledSteps == 0 && overflowSteps == 0 }
    var paintsOnlyTextFrames: Bool {
        uncoveredSteps == 0 && unclippedDraws == 0 && fullRedrawSteps == 0
    }
}

@MainActor
func resizeProbe(
    text: String, handle: OverlayView.ResizeHandle, steps: Int, delta: NSPoint, editor: Bool = false
) -> ResizeProbe {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let canvas = OverlayView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
    window.contentView!.addSubview(canvas)
    canvas.isEditorMode = editor
    let options = TestOptionsRow(frame: .zero)
    canvas.addSubview(options)
    canvas.toolOptionsRowView = options

    canvas.textEditor.show(in: canvas, at: NSPoint(x: 300, y: 400), color: .green,
                           canvas: FakeCanvas(bounds: canvas.bounds))
    guard let textView = canvas.textEditor.textView,
          let scrollView = canvas.textEditor.scrollView,
          let layoutManager = textView.layoutManager,
          let container = textView.textContainer else {
        fatalError("测试依赖 TextKit 1 排版引擎")
    }
    textView.insertText(text, replacementRange: textView.selectedRange())
    canvas.textEditor.resizeToFit()
    window.layoutIfNeeded()
    window.displayIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))

    let frame = scrollView.frame
    let start: NSPoint
    switch handle {
    case .right: start = NSPoint(x: frame.maxX, y: frame.midY)
    case .left: start = NSPoint(x: frame.minX, y: frame.midY)
    case .topRight: start = NSPoint(x: frame.maxX, y: frame.maxY)
    case .topLeft: start = NSPoint(x: frame.minX, y: frame.maxY)
    case .bottomLeft: start = NSPoint(x: frame.minX, y: frame.minY)
    default: start = NSPoint(x: frame.maxX, y: frame.minY)
    }

    var probe = ResizeProbe()
    probe.startFrame = frame
    probe.startFontSize = canvas.textEditor.fontSize
    check(canvas.beginLiveTextInteraction(at: start) && canvas.textBoxResizeHandle == handle, "\(handle) 手柄可以开始拖动")
    var previous = frame

    for step in 1...steps {
        let target = NSPoint(x: start.x + delta.x * CGFloat(step), y: start.y + delta.y * CGFloat(step))
        canvas.invalidRects.removeAll()
        canvas.dirtyRects.removeAll()
        canvas.clipBoxes.removeAll()
        _ = canvas.updateLiveTextInteraction(at: target)
        let requested = canvas.invalidRects
        window.layoutIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))

        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let visible = scrollView.contentView.bounds
        let current = scrollView.frame
        if !visible.contains(used) { probe.clippedSteps += 1 }
        if visible.origin != .zero { probe.scrolledSteps += 1 }
        if textView.frame.height - current.height > 0.001 { probe.overflowSteps += 1 }

        // 首行顶边到框顶的距离（NSTextView 自身是左上原点）：文字贴着框顶时恒为 4 点内边距。
        let line = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let lineTop = textView.textContainerOrigin.y + line.minY
        let lineTopInCanvas = textView.convert(NSPoint(x: 0, y: lineTop), to: canvas).y
        probe.topInsets.insert((current.maxY - lineTopInCanvas).rounded())

        // 底色画到框外 4 点，局部重绘必须盖住旧框与新框。
        let needed = previous.union(current).insetBy(dx: -4, dy: -4)
        let covered = requested.reduce(CGRect.null) { $0.union($1) }
        if canvas.dirtyRects.contains(where: { $0 == canvas.bounds }) { probe.fullRedrawSteps += 1 }
        if !editor {
            if !needed.isEmpty, !covered.contains(needed) { probe.uncoveredSteps += 1 }
            for (dirty, clip) in zip(canvas.dirtyRects, canvas.clipBoxes)
            where !clip.insetBy(dx: -0.5, dy: -0.5).contains(dirty) {
                probe.unclippedDraws += 1
            }
        }
        previous = current
    }

    probe.endFrame = scrollView.frame
    probe.endFontSize = canvas.textEditor.fontSize
    probe.shownFontSize = options.shownFontSize
    check(canvas.endLiveTextInteraction() && !canvas.isResizingTextBox, "松开清理调整状态")
    return probe
}

@MainActor
func runTextInteractionTests() {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let host = window.contentView!
    let canvas = OverlayView(frame: NSRect(x: 30, y: 40, width: 800, height: 600))
    host.addSubview(canvas)
    // 放在画布中下部：放大 2 倍后正文仍落在窗口内。
    canvas.textEditor.show(in: canvas, at: NSPoint(x: 40, y: 200), color: .green,
                           canvas: FakeCanvas(bounds: canvas.bounds))
    let typing = canvas.textEditor.textView!
    typing.insertText("可以选字，也可以拖动整个文本框", replacementRange: typing.selectedRange())
    canvas.textEditor.resizeToFit()
    let scrollView = canvas.textEditor.scrollView!
    scrollView.layoutSubtreeIfNeeded()
    let original = scrollView.frame

    func target(_ point: NSPoint) -> NSView? {
        canvas.hitTest(canvas.convert(point, to: host))
    }

    let body = NSPoint(x: original.midX, y: original.midY)
    check(target(body) is NSTextView, "正文应交给 NSTextView 输入和选字")
    check(original.height == 32, "新建文字的框高由排版结果决定")

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
        let handleRects = canvas.liveTextResizeHandleRects(for: original)
        check(handleRects.count == 6, "高度跟随排版，只画四个角和左右两个手柄")
        check(handleRects.allSatisfy { abs($0.width * zoom - 6) < 0.001 }, "手柄在窗口中保持可见大小")
    }
    canvas.bounds.size = canvas.frame.size

    let handles: [(OverlayView.ResizeHandle, NSPoint)] = [
        (.topLeft, NSPoint(x: original.minX - 8, y: original.maxY + 8)),
        (.topRight, NSPoint(x: original.maxX + 8, y: original.maxY + 8)),
        (.bottomLeft, NSPoint(x: original.minX - 8, y: original.minY - 8)),
        (.bottomRight, NSPoint(x: original.maxX + 8, y: original.minY - 8)),
        (.left, NSPoint(x: original.minX - 8, y: original.midY)),
        (.right, NSPoint(x: original.maxX + 8, y: original.midY)),
    ]
    for (handle, point) in handles {
        check(target(point) === canvas, "六个方向均由画布接收")
        check(canvas.beginLiveTextInteraction(at: point) && canvas.textBoxResizeHandle == handle, "显示调整光标的方向确实可以操作")
        _ = canvas.endLiveTextInteraction()
    }

    // 上、下边缘不再有只改高度的手柄：那样会把文字挤出框外。
    for edgePoint in [NSPoint(x: original.midX, y: original.maxY + 8),
                      NSPoint(x: original.midX, y: original.minY - 8)] {
        check(canvas.beginLiveTextInteraction(at: edgePoint) && canvas.isDraggingTextBox
              && canvas.textBoxResizeHandle == .none, "上、下边缘外侧按住即整体移动")
        _ = canvas.endLiveTextInteraction()
    }
    let insideTop = NSPoint(x: original.midX, y: original.maxY - 1)
    check(canvas.beginLiveTextInteraction(at: insideTop) && canvas.isDraggingTextBox
          && canvas.textBoxResizeHandle == .none, "上边缘内侧 1 点同样只用于整体移动")
    _ = canvas.endLiveTextInteraction()

    let left = NSPoint(x: original.minX + 1, y: original.midY)
    check(canvas.beginLiveTextInteraction(at: left), "可按住左手柄")
    check(canvas.textBoxResizeHandle == .left, "左侧不是虚假的调整光标")
    check(canvas.updateLiveTextInteraction(at: NSPoint(x: left.x - 25, y: left.y)), "左侧拖动有实际处理")
    check(scrollView.frame.minX == original.minX - 25 && scrollView.frame.maxX == original.maxX, "左侧调整保持右边锚点")
    check(scrollView.frame.maxY == original.maxY, "左侧调整保持顶边不动")
    check(canvas.endLiveTextInteraction() && !canvas.isResizingTextBox, "松开清理调整状态")

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
    check(scrollView.frame.minX == narrow.minX && scrollView.frame.width == narrow.width, "新建小框按下调整手柄宽度不能突然跳大")
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

    // 拖动缩放：对应「文字被裁、一直在动」的问题。
    let grow = resizeProbe(text: "dsfa", handle: .bottomRight, steps: 40, delta: NSPoint(x: 6, y: 0.5))
    check(grow.staysInsideFrame, "右下角放大：文字全程完整可见")
    check(grow.topInsets == [4], "缩放过程中文字顶边与框顶的间距始终是 4 点内边距")
    check(grow.endFrame.minX == grow.startFrame.minX && grow.endFrame.maxY == grow.startFrame.maxY, "右下角缩放保持左上角不动")
    check(grow.endFontSize > grow.startFontSize * 3 && grow.endFrame.width > grow.startFrame.width * 3, "横向拖动右下角会等比放大字号和文字框")
    check(grow.shownFontSize == grow.endFontSize, "工具栏字号显示跟随缩放")
    check(grow.paintsOnlyTextFrames, "遮罩只重绘文字框新旧位置，并且 draw 被裁到该范围")

    let diagonal = resizeProbe(text: "hello dsfa world", handle: .bottomRight, steps: 30, delta: NSPoint(x: 5, y: -5))
    check(diagonal.staysInsideFrame && diagonal.topInsets == [4], "45° 拖动：文字不裁、不跳")
    check(diagonal.endFontSize > diagonal.startFontSize * 2, "斜向拖动同样放大字号")

    let vertical = resizeProbe(text: "dsfa", handle: .bottomRight, steps: 30, delta: NSPoint(x: 0.5, y: -3))
    check(vertical.staysInsideFrame && vertical.endFontSize > vertical.startFontSize * 1.5, "以纵向为主的拖动也能放大字号")

    let shrink = resizeProbe(text: "dsfa", handle: .bottomRight, steps: 60, delta: NSPoint(x: -2.4, y: 0.6))
    check(shrink.staysInsideFrame && shrink.topInsets == [4], "拖回锚点缩小时文字不裁、不跳")
    check(shrink.endFontSize == 6, "字号缩小到 6 点下限后停住")

    let wrap = resizeProbe(text: "可以选字，也可以拖动整个文本框，再编辑时高度变化", handle: .right, steps: 60, delta: NSPoint(x: -6, y: 0))
    check(wrap.staysInsideFrame && wrap.topInsets == [4], "右手柄缩窄：换行增多时外框跟着变高")
    check(wrap.endFrame.maxY == wrap.startFrame.maxY && wrap.endFrame.height > wrap.startFrame.height * 2, "右手柄调整保持顶边不动")
    check(wrap.paintsOnlyTextFrames, "换行变高时同样只重绘文字框区域")

    let mixed = resizeProbe(text: "Fix 文字缩放时的 jitter and clipping bugs in live text editing", handle: .left, steps: 50, delta: NSPoint(x: 7, y: 0))
    check(mixed.staysInsideFrame && mixed.endFrame.maxX == mixed.startFrame.maxX, "左手柄缩窄：保持右边锚点，文字不裁")

    let topLeft = resizeProbe(text: "第一行文字\n第二行文字\n第三行文字", handle: .topLeft, steps: 30, delta: NSPoint(x: -4, y: -4))
    check(topLeft.staysInsideFrame && topLeft.topInsets == [4], "左上角放大：多行文字不裁、不跳")
    check(topLeft.endFrame.maxX == topLeft.startFrame.maxX && topLeft.endFrame.minY == topLeft.startFrame.minY, "左上角缩放保持右下角不动")

    for (handle, delta) in [(OverlayView.ResizeHandle.topRight, NSPoint(x: 6, y: -5)),
                            (.bottomLeft, NSPoint(x: -6, y: 5))] {
        let probe = resizeProbe(text: "hello dsfa world", handle: handle, steps: 30, delta: delta)
        check(probe.staysInsideFrame && probe.topInsets == [4], "\(handle) 放大：文字不裁、不跳")
    }

    let editor = resizeProbe(text: "hello dsfa world", handle: .bottomRight, steps: 20, delta: NSPoint(x: 5, y: -5), editor: true)
    check(editor.staysInsideFrame, "编辑器里缩放同样不裁字")
    check(editor.fullRedrawSteps == 20, "编辑器保持整屏重绘，避开滚动视图放大管线的残影")

    print("通过：原生事件路由、正文选字、4 档缩放、6 个手柄、上/下边缘移动、上/左调整、小框、工具栏优先级；"
          + "四角缩放与左右换行共 10 组拖动全程不裁字、不滚动、文字不跳，遮罩只重绘文字框区域。")
}

MainActor.assumeIsolated { runTextInteractionTests() }
