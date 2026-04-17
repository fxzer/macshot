import Cocoa

/// Real NSView container for a row (horizontal) or column (vertical) of ToolbarButtonViews.
/// Dark rounded background matching the existing toolbar look.
class ToolbarStripView: NSView {

    enum Orientation { case horizontal, vertical }

    let orientation: Orientation
    private(set) var buttonViews: [ToolbarButtonView] = []
    private var separatorViews: [ToolbarSeparatorView] = []  // Separator views
    /// Parallel to `buttonViews`: draw a horizontal separator before this button (vertical strip only).
    private var sectionBreakBeforeForButtonIndex: [Bool] = []
    /// Set to true in editor mode so gap clicks pass through to the image beneath.
    var passesThrough = false

    var onClick: ((ToolbarButtonAction) -> Void)?
    var onRightClick: ((ToolbarButtonAction, NSView) -> Void)?
    var onHover: ((ToolbarButtonAction, Bool) -> Void)?
    var horizontalSeparatorAfterIndices: Set<Int> = []

    private let padding: CGFloat = ToolbarLayout.toolbarPadding
    private let spacing: CGFloat = ToolbarLayout.buttonSpacing
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
        sectionBreakBeforeForButtonIndex = buttons.map(\.sectionBreakBefore)

        // 底栏横向：在指定按钮索引之后插入竖线分隔（与 bottomButtons 分组一致）
        for (index, data) in buttons.enumerated() {
            if orientation == .vertical, data.sectionBreakBefore, index > 0 {
                let separator = ToolbarSeparatorView(kind: .horizontalRule)
                addSubview(separator)
                separatorViews.append(separator)
            }

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

            if orientation == .horizontal,
                horizontalSeparatorAfterIndices.contains(index),
                index < buttons.count - 1
            {
                let separator = ToolbarSeparatorView(kind: .verticalBar)
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
                if horizontalSeparatorAfterIndices.contains(index) && separatorIndex < separatorViews.count {
                    let sep = separatorViews[separatorIndex]
                    x += separatorSpacing
                    let sepSize = sep.intrinsicContentSize
                    sep.frame = NSRect(x: x, y: padding + (btnSize - sepSize.height) / 2, width: sepSize.width, height: sepSize.height)
                    x += sepSize.width + separatorSpacing
                    maxWidth += sepSize.width + separatorSpacing * 2
                    separatorIndex += 1
                }
            }
            frame.size = NSSize(width: maxWidth, height: btnSize + padding * 2)

        case .vertical:
            var sepRun = 0
            var extraForSeparators: CGFloat = 0
            for i in 1..<buttonViews.count {
                guard i < sectionBreakBeforeForButtonIndex.count,
                    sectionBreakBeforeForButtonIndex[i]
                else { continue }
                let sep = separatorViews[sepRun]
                sepRun += 1
                extraForSeparators += separatorSpacing + sep.intrinsicContentSize.height + separatorSpacing
            }

            let buttonsHeight =
                CGFloat(buttonViews.count) * (btnSize + spacing) - spacing + padding * 2
            let totalHeight = buttonsHeight + extraForSeparators
            frame.size = NSSize(width: btnSize + padding * 2, height: totalHeight)

            var y: CGFloat = totalHeight - padding
            sepRun = 0
            for i in buttonViews.indices {
                if i > 0, i < sectionBreakBeforeForButtonIndex.count, sectionBreakBeforeForButtonIndex[i] {
                    y -= separatorSpacing
                    let sep = separatorViews[sepRun]
                    sepRun += 1
                    let sz = sep.intrinsicContentSize
                    let sx = padding + (btnSize - sz.width) / 2
                    sep.frame = NSRect(x: sx, y: y - sz.height, width: sz.width, height: sz.height)
                    y -= sz.height + separatorSpacing
                }
                let btn = buttonViews[i]
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

/// Separator between toolbar button groups: vertical bar in horizontal strips, horizontal rule in vertical strips.
class ToolbarSeparatorView: NSView {

    enum Kind {
        case verticalBar
        case horizontalRule
    }

    let kind: Kind

    init(kind: Kind = .verticalBar) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.3, alpha: 0.3).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        switch kind {
        case .verticalBar:
            return NSSize(width: 1, height: 24)
        case .horizontalRule:
            let w = max(8, ToolbarButtonView.size - 8)
            return NSSize(width: w, height: 1)
        }
    }
}
