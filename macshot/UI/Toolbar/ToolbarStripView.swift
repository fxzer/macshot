import Cocoa

/// Real NSView container for a row (horizontal) or column (vertical) of ToolbarButtonViews.
/// Dark rounded background matching the existing toolbar look.
class ToolbarStripView: NSView {

    enum Orientation { case horizontal, vertical }

    let orientation: Orientation
    private(set) var buttonViews: [ToolbarButtonView] = []
    private var separatorViews: [ToolbarSeparatorView] = []  // Separator views
    /// Set to true in editor mode so gap clicks pass through to the image beneath.
    var passesThrough = false

    var onClick: ((ToolbarButtonAction) -> Void)?
    var onMouseDown: ((ToolbarButtonAction) -> Void)?
    var onRightClick: ((ToolbarButtonAction, NSView) -> Void)?
    var onHover: ((ToolbarButtonAction, Bool) -> Void)?

    private let padding: CGFloat = 4
    private let spacing: CGFloat = 2
    private let separatorSpacing: CGFloat = 6  // Extra spacing around separators

    init(orientation: Orientation) {
        self.orientation = orientation
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Rebuild buttons from ToolbarButton data.
    func setButtons(_ buttons: [ToolbarButton]) {
        // 清除旧视图
        for bv in buttonViews { bv.removeFromSuperview() }
        for sep in separatorViews { sep.removeFromSuperview() }
        buttonViews.removeAll()
        separatorViews.removeAll()

        // 定义分隔线位置（在工具按钮索引之后插入分隔线）
        // 画笔组(3): 画笔 线条 箭头 荧光笔
        // 形状组(7): 矩形 椭圆 马赛克 放大镜
        // 标注组(11): 文字 编号 表情 测量
        // 功能组(15): 取色 颜色 撤销 重做
        let separatorIndices: Set<Int> = [3, 7, 11, 15]

        for (index, data) in buttons.enumerated() {
            let bv = ToolbarButtonView(action: data.action, sfSymbol: data.sfSymbol, tooltip: data.tooltip)
            bv.isOn = data.isSelected
            bv.tintColor = data.tintColor
            bv.swatchColor = data.bgColor
            bv.hasContextMenu = data.hasContextMenu
            bv.onClick = { [weak self] action in self?.onClick?(action) }
            bv.onRightClick = { [weak self] action, view in self?.onRightClick?(action, view) }
            bv.onHover = { [weak self] action, hovered in self?.onHover?(action, hovered) }
            addSubview(bv)
            buttonViews.append(bv)

            // 在指定位置后添加分隔线
            if separatorIndices.contains(index) && index < buttons.count - 1 {
                let separator = ToolbarSeparatorView()
                addSubview(separator)
                separatorViews.append(separator)
            }
        }
        layoutButtons()
    }

    /// Update visual state without rebuilding.
    func updateState(from buttons: [ToolbarButton]) {
        var buttonIndex = 0
        for view in buttonViews {
            guard let btn = view as? ToolbarButtonView else { continue }
            guard buttonIndex < buttons.count else { break }
            let data = buttons[buttonIndex]
            btn.isOn = data.isSelected
            btn.tintColor = data.tintColor
            btn.swatchColor = data.bgColor
            btn.sfSymbol = data.sfSymbol
            btn.needsDisplay = true
            buttonIndex += 1
        }
    }

    private func layoutButtons() {
        let btnSize = ToolbarButtonView.size
        guard !buttonViews.isEmpty else { frame.size = .zero; return }

        switch orientation {
        case .horizontal:
            var x: CGFloat = padding
            var maxWidth: CGFloat = padding * 2
            var separatorIndex = 0

            for (index, btn) in buttonViews.enumerated() {
                btn.frame = NSRect(x: x, y: padding, width: btnSize, height: btnSize)
                x += btnSize + spacing
                maxWidth += btnSize + spacing

                // 检查是否需要在这个按钮后添加分隔线
                // 分隔线位置：画笔组后(3)、形状组后(7)、标注组后(11)、功能组后(15)
                if [3, 7, 11, 15].contains(index) && separatorIndex < separatorViews.count {
                    let sep = separatorViews[separatorIndex]
                    x += separatorSpacing
                    let sepSize = sep.intrinsicContentSize
                    sep.frame = NSRect(x: x, y: padding + (btnSize - sepSize.height) / 2, width: sepSize.width, height: sepSize.height)
                    x += sepSize.width + separatorSpacing
                    maxWidth += sepSize.width + separatorSpacing * 2
                    separatorIndex += 1
                }
            }
            frame.size = NSSize(width: maxWidth + padding, height: btnSize + padding * 2)

        case .vertical:
            // 计算所需的总高度
            let totalHeight = CGFloat(buttonViews.count) * (btnSize + spacing) - spacing + padding * 2
            frame.size = NSSize(width: btnSize + padding * 2, height: totalHeight)

            // 从顶部向下排列按钮
            var y: CGFloat = totalHeight - padding
            for btn in buttonViews {
                btn.frame = NSRect(x: padding, y: y - btnSize, width: btnSize, height: btnSize)
                y -= btnSize + spacing
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        ToolbarLayout.bgColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    // Consume clicks on gaps between buttons so they don't fall through to OverlayView.
    // In editor mode (passesThrough), let gap clicks pass through so drawing works
    // over the toolbar area.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let result = super.hitTest(point), result !== self { return result }
        if passesThrough { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

// MARK: - Toolbar Separator

/// Gray vertical separator line for toolbar button groups.
class ToolbarSeparatorView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        // 使用更明显的颜色，在暗色背景上可见
        self.layer?.backgroundColor = NSColor(calibratedWhite: 0.3, alpha: 0.3).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 1, height: 24)
    }
}
