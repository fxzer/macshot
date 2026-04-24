//
//  ToolOptionsRowView+Builders.swift
//  macshot
//
//  UI builder methods for tool options controls using NSStackView.
//

import Cocoa

private final class ToolOptionToggleView: NSStackView {
    private let button: NSButton
    private let label: NSTextField
    private let handler: ToggleHandler

    init(title: String, isOn: Bool, action: @escaping (Bool) -> Void) {
        self.button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        self.label = NSTextField(labelWithString: title)
        self.handler = ToggleHandler(action: action)
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4

        button.state = isOn ? .on : .off
        button.target = handler
        button.action = #selector(ToggleHandler.toggled(_:))
        objc_setAssociatedObject(button, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
        addArrangedSubview(button)

        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        label.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(labelClicked)))
        addArrangedSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func labelClicked() {
        button.state = button.state == .on ? .off : .on
        handler.toggled(button)
    }
}

extension ToolOptionsRowView {

    // MARK: - Section builders

    func addSeparator(to stack: NSStackView) {
        let sep = NSBox()
        sep.boxType = .custom
        sep.borderType = .noBorder
        sep.fillColor = ToolbarLayout.iconColor.withAlphaComponent(0.2)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 18).isActive = true
        sep.wantsLayer = true
        sep.layer?.backgroundColor = ToolbarLayout.iconColor.withAlphaComponent(0.1).cgColor
        stack.addArrangedSubview(sep)
    }

    func supportsDrawColor(_ tool: AnnotationTool) -> Bool {
        switch tool {
        case .pencil, .line, .arrow, .rectangle, .ellipse, .marker, .number, .measure, .text:
            return true
        default:
            return false
        }
    }

    func addDrawColorControl(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
        let label = NSTextField(labelWithString: L("Color"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(label)

        let swatchSize: CGFloat = 18
        let swatch = NSButton()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: swatchSize).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: swatchSize).isActive = true
        swatch.title = ""
        swatch.isBordered = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = (editingAnnotation?.color ?? ov.currentColor).cgColor
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1.5
        swatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        swatch.tag = ToolOptionTag.drawColorSwatch.rawValue
        swatch.target = self
        swatch.action = #selector(drawColorClicked(_:))
        stack.addArrangedSubview(swatch)
    }

    func addStrokeSlider(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
        let nameLabel = NSTextField(labelWithString: (tool == .loupe || tool == .number) ? L("Size") : L("Stroke"))
        nameLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        nameLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(nameLabel)

        let currentVal = editingAnnotation?.strokeWidth ?? ov.activeStrokeWidthForTool(tool)
        let sliderMin: Double
        let sliderMax: Double
        switch tool {
        case .loupe:
            sliderMin = 40
            sliderMax = 320
        case .marker:
            sliderMin = 6
            sliderMax = 100
        case .number:
            sliderMin = NumberCalloutGeometry.minSize
            sliderMax = NumberCalloutGeometry.maxSize
        default:
            sliderMin = 1
            sliderMax = 30
        }
        let slider = NSSlider(value: Double(currentVal),
                              minValue: sliderMin, maxValue: sliderMax,
                              target: self, action: #selector(strokeSliderChanged(_:)))
        slider.isContinuous = true
        slider.tag = tool.rawValue
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(slider)

        let val = Int(currentVal)
        let valStr = tool == .loupe ? "\(val)" : "\(val)px"
        let labelW: CGFloat = tool == .loupe ? 32 : (tool == .marker ? 38 : 28)
        let label = NSTextField(labelWithString: valStr)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        label.alignment = .right
        label.tag = ToolOptionTag.strokeValueLabel.rawValue
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: labelW).isActive = true
        stack.addArrangedSubview(label)
    }

    func addLineStyleSegment(to stack: NSStackView, ov: OverlayView) {
        let seg = NSSegmentedControl()
        seg.segmentCount = LineStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(lineStyleChanged(_:))
        seg.tag = ToolOptionTag.lineStyleSegment.rawValue
        for (i, style) in LineStyle.allCases.enumerated() {
            seg.setImage(Self.lineStyleImage(style), forSegment: i)
            seg.setWidth(36, forSegment: i)
        }
        let currentStyle = editingAnnotation?.lineStyle ?? ov.currentLineStyle
        seg.selectedSegment = currentStyle.rawValue
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)

        // Disable dashed/dotted for rect/ellipse when outline is enabled
        let isShapeTool = [AnnotationTool.rectangle, .ellipse].contains(editingAnnotation?.tool ?? ov.currentTool)
        let hasOutline = editingAnnotation?.outlineColor != nil
        if isShapeTool && hasOutline {
            for (i, style) in LineStyle.allCases.enumerated() {
                if style != .solid { seg.setEnabled(false, forSegment: i) }
            }
            if currentStyle != .solid {
                seg.selectedSegment = LineStyle.solid.rawValue
                if let ann = editingAnnotation {
                    ann.lineStyle = .solid
                    ov.cachedCompositedImage = nil
                } else {
                    ov.currentLineStyle = .solid
                }
            }
        }
    }

    func addArrowStyleSegment(to stack: NSStackView, ov: OverlayView) {
        let seg = NSSegmentedControl()
        seg.segmentCount = ArrowStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(arrowStyleChanged(_:))
        for (i, style) in ArrowStyle.allCases.enumerated() {
            seg.setImage(Self.arrowStyleImage(style), forSegment: i)
            seg.setWidth(30, forSegment: i)
        }
        seg.selectedSegment = (editingAnnotation?.arrowStyle ?? ov.currentArrowStyle).rawValue
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)
    }

    func addShapeFillSegment(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
        let isOval = tool == .ellipse
        let seg = NSSegmentedControl()
        seg.segmentCount = RectFillStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(shapeFillChanged(_:))
        for (i, style) in RectFillStyle.allCases.enumerated() {
            seg.setImage(Self.shapeFillImage(style, oval: isOval), forSegment: i)
            seg.setWidth(30, forSegment: i)
        }
        seg.selectedSegment = (editingAnnotation?.rectFillStyle ?? ov.currentRectFillStyle).rawValue
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)
    }

    func addCensorModeSegment(to stack: NSStackView, ov: OverlayView) {
        let seg = NSSegmentedControl()
        seg.segmentCount = CensorMode.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(censorModeChanged(_:))
        seg.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        for (i, mode) in CensorMode.allCases.enumerated() {
            seg.setLabel(mode.label, forSegment: i)
        }
        let currentMode = CensorMode(rawValue: UserDefaults.standard.integer(forKey: "censorMode")) ?? .pixelate
        seg.selectedSegment = currentMode.rawValue
        seg.sizeToFit()
        stack.addArrangedSubview(seg)
    }

    func addRedactButton(to stack: NSStackView, title: String, action: Selector,
                         font: NSFont, height: CGFloat, y: CGFloat,
                         dropdownAction: Selector? = nil) {
        let seg = NSSegmentedControl()
        seg.trackingMode = .momentary
        seg.font = font
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect

        if dropdownAction != nil {
            seg.segmentCount = 2
            seg.setLabel(title, forSegment: 0)
            seg.setLabel("▾", forSegment: 1)
            seg.setWidth(18, forSegment: 1)
            seg.target = self
            seg.action = #selector(piiSegmentClicked(_:))
        } else {
            seg.segmentCount = 1
            seg.setLabel(title, forSegment: 0)
            seg.target = self
            seg.action = action
        }
        seg.sizeToFit()
        stack.addArrangedSubview(seg)
    }

    @objc func piiSegmentClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            redactPIIClicked()
        } else {
            redactTypesClicked(sender)
        }
    }

    // MARK: - Segment preview images

    static func lineStyleImage(_ style: LineStyle) -> NSImage {
        let size = NSSize(width: 28, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            style.apply(to: path)
            ToolbarLayout.iconColor.setStroke()
            path.move(to: NSPoint(x: 4, y: size.height / 2))
            path.line(to: NSPoint(x: size.width - 4, y: size.height / 2))
            path.stroke()
            return true
        }
    }

    static func arrowStyleImage(_ style: ArrowStyle) -> NSImage {
        let size = NSSize(width: 24, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let mid = size.height / 2
            let from = NSPoint(x: 3, y: mid)
            let to = NSPoint(x: size.width - 3, y: mid)
            ToolbarLayout.iconColor.setStroke()
            ToolbarLayout.iconColor.setFill()

            switch style {
            case .single:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                head.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                head.close()
                head.fill()
            case .thick:
                let path = NSBezierPath()
                path.lineWidth = 2.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 6, y: mid))
                path.stroke()
                let headHalf: CGFloat = 3.5
                let headBase = NSPoint(x: to.x - 5, y: mid)
                let head = NSBezierPath()
                head.move(to: from)
                head.line(to: NSPoint(x: headBase.x, y: mid - headHalf))
                head.line(to: to)
                head.line(to: NSPoint(x: headBase.x, y: mid + headHalf))
                head.close()
                head.fill()
            case .double:
                let headLen: CGFloat = 4
                let angle: CGFloat = .pi / 6
                let s1 = NSPoint(x: from.x + headLen * cos(angle), y: from.y + headLen * sin(angle))
                let s2 = NSPoint(x: from.x + headLen * cos(-angle), y: from.y + headLen * sin(-angle))
                let sh = NSBezierPath()
                sh.move(to: from)
                sh.line(to: s1)
                sh.line(to: s2)
                sh.close()
                sh.fill()
                let e1 = NSPoint(x: to.x - headLen * cos(angle), y: to.y - headLen * sin(angle))
                let e2 = NSPoint(x: to.x - headLen * cos(-angle), y: to.y - headLen * sin(-angle))
                let eh = NSBezierPath()
                eh.move(to: to)
                eh.line(to: e1)
                eh.line(to: e2)
                eh.close()
                eh.fill()
                let shaft = NSBezierPath()
                shaft.lineWidth = 1.5
                shaft.move(to: from)
                shaft.line(to: to)
                shaft.stroke()
            case .open:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4.5, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.lineWidth = 1.5
                head.lineCapStyle = .round
                head.lineJoinStyle = .round
                head.move(to: NSPoint(x: to.x - 4.5, y: mid + 3))
                head.line(to: to)
                head.line(to: NSPoint(x: to.x - 4.5, y: mid - 3))
                head.stroke()
            case .tail:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                head.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                head.close()
                head.fill()
                let tailR: CGFloat = 2.5
                NSBezierPath(ovalIn: NSRect(x: from.x - tailR, y: mid - tailR, width: tailR * 2, height: tailR * 2)).fill()
            }
            return true
        }
    }

    static func shapeFillImage(_ style: RectFillStyle, oval: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let inset: CGFloat = 2
            let rect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            let path = oval ? NSBezierPath(ovalIn: rect) : NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            ToolbarLayout.iconColor.setStroke()
            path.lineWidth = 1.5
            switch style {
            case .stroke:
                path.stroke()
            case .strokeAndFill:
                path.stroke()
                ToolbarLayout.iconColor.withAlphaComponent(0.25).setFill()
                path.fill()
            case .fill:
                ToolbarLayout.iconColor.setFill()
                path.fill()
            }
            return true
        }
    }

    // MARK: - Tool-specific builders

    func addCornerRadiusSlider(to stack: NSStackView, ov: OverlayView) {
        let label = NSTextField(labelWithString: L("Radius"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(label)

        let radiusVal = editingAnnotation?.rectCornerRadius ?? ov.currentRectCornerRadius
        let slider = NSSlider(value: Double(radiusVal),
                              minValue: 0, maxValue: 30,
                              target: self, action: #selector(cornerRadiusChanged(_:)))
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(slider)

        let valLabel = NSTextField(labelWithString: "\(Int(radiusVal))px")
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        valLabel.alignment = .right
        valLabel.tag = ToolOptionTag.cornerRadiusLabel.rawValue
        valLabel.translatesAutoresizingMaskIntoConstraints = false
        valLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(valLabel)
    }

    func addToggle(to stack: NSStackView, title: String, isOn: Bool, action: @escaping (Bool) -> Void) {
        stack.addArrangedSubview(ToolOptionToggleView(title: title, isOn: isOn, action: action))
    }

    func addNumberOptions(to stack: NSStackView, ov: OverlayView) {
        let formats = ["1", "I", "A", "a"]
        let seg = NSSegmentedControl(labels: formats, trackingMode: .selectOne,
                                     target: self, action: #selector(numberFormatChanged(_:)))
        seg.selectedSegment = ov.currentNumberFormat.rawValue
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)

        addSeparator(to: stack)

        let startLabel = NSTextField(labelWithString: L("Start:"))
        startLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        startLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(startLabel)

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 999
        stepper.integerValue = ov.numberStartAt
        stepper.target = self
        stepper.action = #selector(numberStartChanged(_:))
        stack.addArrangedSubview(stepper)

        let valLabel = NSTextField(labelWithString: ov.currentNumberFormat.format(ov.numberStartAt))
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.85)
        valLabel.tag = ToolOptionTag.numberStartValueLabel.rawValue
        stack.addArrangedSubview(valLabel)
    }

    func addTextOptions(to stack: NSStackView, ov: OverlayView) {
        let displayName = ov.textEditor.fontFamily == "System" ? "System" : ov.textEditor.fontFamily
        let fontBtn = NSButton(title: "\(displayName) ▾", target: self, action: #selector(fontFamilyClicked(_:)))
        fontBtn.bezelStyle = .recessed
        fontBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        fontBtn.attributedTitle = NSAttributedString(string: "\(displayName) ▾", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .baselineOffset: 0.5,
        ])
        fontBtn.sizeToFit()
        fontBtn.translatesAutoresizingMaskIntoConstraints = false
        fontBtn.widthAnchor.constraint(equalToConstant: max(65, fontBtn.frame.width + 8)).isActive = true
        stack.addArrangedSubview(fontBtn)

        let textStyles: [(String, String, Bool, Selector, Int)] = [
            ("bold", "B", ov.textEditor.bold, #selector(boldToggled), 980),
            ("italic", "I", ov.textEditor.italic, #selector(italicToggled), 981),
            ("underline", "U", ov.textEditor.underline, #selector(underlineToggled), 982),
            ("strikethrough", "S", ov.textEditor.strikethrough, #selector(strikethroughToggled), 983),
        ]
        for (_, label, isOn, sel, tag) in textStyles {
            let btn = NSButton(title: label, target: self, action: sel)
            btn.bezelStyle = .smallSquare
            btn.isBordered = false
            btn.wantsLayer = true
            btn.tag = tag
            btn.layer?.cornerRadius = 4
            btn.layer?.backgroundColor = isOn ? ToolbarLayout.accentColor.withAlphaComponent(0.85).cgColor : nil
            btn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            btn.attributedTitle = NSAttributedString(string: label, attributes: [
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(isOn ? 1.0 : 0.6),
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            ])
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 26).isActive = true
            stack.addArrangedSubview(btn)
        }

        addSeparator(to: stack)

        let alignments: [(String, NSTextAlignment)] = [
            ("text.alignleft", .left), ("text.aligncenter", .center), ("text.alignright", .right)
        ]
        for (symbol, alignment) in alignments {
            let btn = NSButton()
            btn.bezelStyle = .recessed
            btn.isBordered = false
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            btn.state = ov.textEditor.alignment == alignment ? .on : .off
            btn.setButtonType(.toggle)
            btn.tag = alignment.rawValue
            btn.target = self
            btn.action = #selector(alignmentChanged(_:))
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 26).isActive = true
            stack.addArrangedSubview(btn)
        }

        addSeparator(to: stack)

        let minusBtn = NSButton(title: "−", target: self, action: #selector(fontSizeDecreased))
        minusBtn.bezelStyle = .recessed
        minusBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        minusBtn.isContinuous = true
        (minusBtn.cell as? NSButtonCell)?.setPeriodicDelay(0.3, interval: 0.05)
        stack.addArrangedSubview(minusBtn)

        let sizeLabel = NSTextField(labelWithString: "\(Int(ov.textEditor.fontSize))")
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.7)
        sizeLabel.alignment = .center
        sizeLabel.tag = ToolOptionTag.textFontSizeLabel.rawValue
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.widthAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(sizeLabel)

        let plusBtn = NSButton(title: "+", target: self, action: #selector(fontSizeIncreased))
        plusBtn.bezelStyle = .recessed
        plusBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        plusBtn.isContinuous = true
        (plusBtn.cell as? NSButtonCell)?.setPeriodicDelay(0.3, interval: 0.05)
        stack.addArrangedSubview(plusBtn)

        addSeparator(to: stack)

        let fillSwatchSize: CGFloat = 18
        let fillLabelBtn = NSButton(title: L("Fill"), target: self, action: #selector(textBgToggled(_:)))
        fillLabelBtn.bezelStyle = .recessed
        fillLabelBtn.setButtonType(.toggle)
        fillLabelBtn.state = ov.textEditor.bgEnabled ? .on : .off
        fillLabelBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        fillLabelBtn.attributedTitle = NSAttributedString(string: L("Fill"), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .baselineOffset: 0.5,
        ])
        fillLabelBtn.sizeToFit()
        stack.addArrangedSubview(fillLabelBtn)

        let fillSwatch = NSButton()
        fillSwatch.translatesAutoresizingMaskIntoConstraints = false
        fillSwatch.widthAnchor.constraint(equalToConstant: fillSwatchSize).isActive = true
        fillSwatch.heightAnchor.constraint(equalToConstant: fillSwatchSize).isActive = true
        fillSwatch.title = ""
        fillSwatch.isBordered = false
        fillSwatch.wantsLayer = true
        fillSwatch.layer?.backgroundColor = ov.textEditor.bgColor.cgColor
        fillSwatch.layer?.cornerRadius = 3
        fillSwatch.layer?.borderWidth = 1.5
        fillSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        fillSwatch.layer?.opacity = ov.textEditor.bgEnabled ? 1.0 : 0.3
        fillSwatch.tag = ToolOptionTag.textBgColorSwatch.rawValue
        fillSwatch.target = self
        fillSwatch.action = #selector(textBgColorClicked(_:))
        stack.addArrangedSubview(fillSwatch)

        let outlineLabelBtn = NSButton(title: L("Outline"), target: self, action: #selector(textOutlineToggled(_:)))
        outlineLabelBtn.bezelStyle = .recessed
        outlineLabelBtn.setButtonType(.toggle)
        outlineLabelBtn.state = ov.textEditor.outlineEnabled ? .on : .off
        outlineLabelBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        outlineLabelBtn.attributedTitle = NSAttributedString(string: L("Outline"), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .baselineOffset: 0.5,
        ])
        outlineLabelBtn.sizeToFit()
        stack.addArrangedSubview(outlineLabelBtn)

        let outlineSwatch = NSButton()
        outlineSwatch.translatesAutoresizingMaskIntoConstraints = false
        outlineSwatch.widthAnchor.constraint(equalToConstant: fillSwatchSize).isActive = true
        outlineSwatch.heightAnchor.constraint(equalToConstant: fillSwatchSize).isActive = true
        outlineSwatch.title = ""
        outlineSwatch.isBordered = false
        outlineSwatch.wantsLayer = true
        outlineSwatch.layer?.backgroundColor = ov.textEditor.outlineColor.cgColor
        outlineSwatch.layer?.cornerRadius = 3
        outlineSwatch.layer?.borderWidth = 1.5
        outlineSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        outlineSwatch.layer?.opacity = ov.textEditor.outlineEnabled ? 1.0 : 0.3
        outlineSwatch.tag = ToolOptionTag.textOutlineColorSwatch.rawValue
        outlineSwatch.target = self
        outlineSwatch.action = #selector(textOutlineColorClicked(_:))
        stack.addArrangedSubview(outlineSwatch)

        if ov.textEditor.isEditing {
            addSeparator(to: stack)
            let cancelBtn = NSButton(title: "✕", target: self, action: #selector(textCancelClicked))
            cancelBtn.bezelStyle = .smallSquare
            cancelBtn.isBordered = false
            cancelBtn.wantsLayer = true
            cancelBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
            cancelBtn.layer?.cornerRadius = 4
            cancelBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            cancelBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 11, weight: .bold)])
            cancelBtn.translatesAutoresizingMaskIntoConstraints = false
            cancelBtn.widthAnchor.constraint(equalToConstant: 28).isActive = true
            cancelBtn.tag = ToolOptionTag.textCancelButton.rawValue
            stack.addArrangedSubview(cancelBtn)

            let confirmBtn = NSButton(title: "✓", target: self, action: #selector(textConfirmClicked))
            confirmBtn.bezelStyle = .smallSquare
            confirmBtn.isBordered = false
            confirmBtn.wantsLayer = true
            confirmBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
            confirmBtn.layer?.cornerRadius = 4
            confirmBtn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            confirmBtn.attributedTitle = NSAttributedString(string: "✓", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .bold)])
            confirmBtn.translatesAutoresizingMaskIntoConstraints = false
            confirmBtn.widthAnchor.constraint(equalToConstant: 28).isActive = true
            confirmBtn.tag = ToolOptionTag.textConfirmButton.rawValue
            stack.addArrangedSubview(confirmBtn)
        }
    }

    func addMeasureToggle(to stack: NSStackView, ov: OverlayView) {
        let seg = NSSegmentedControl(labels: ["px", "pt"], trackingMode: .selectOne,
                                     target: self, action: #selector(measureUnitChanged(_:)))
        seg.selectedSegment = ov.currentMeasureInPoints ? 1 : 0
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)

        addHintLabel(to: stack, text: L("Hold 1 auto-vertical  ·  Hold 2 auto-horizontal"))
    }

    func addStampOptions(to stack: NSStackView, ov: OverlayView) {
        for (groupIndex, group) in StampEmojis.commonGroups.enumerated() {
            for emoji in group {
                let btn = NSButton(title: emoji, target: self, action: #selector(quickEmojiClicked(_:)))
                btn.bezelStyle = .recessed
                btn.isBordered = false
                btn.font = NSFont.systemFont(ofSize: 14)
                stack.addArrangedSubview(btn)
            }
            if groupIndex < StampEmojis.commonGroups.count - 1 {
                addSeparator(to: stack)
            }
        }

        addSeparator(to: stack)

        let moreBtn = NSButton()
        moreBtn.bezelStyle = .recessed
        moreBtn.isBordered = false
        moreBtn.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: L("More Emojis"))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        moreBtn.toolTip = L("More Emojis")
        moreBtn.target = self
        moreBtn.action = #selector(moreEmojisClicked(_:))
        moreBtn.contentTintColor = ToolbarLayout.iconColor
        stack.addArrangedSubview(moreBtn)

        let loadBtn = NSButton()
        loadBtn.bezelStyle = .recessed
        loadBtn.isBordered = false
        loadBtn.image = NSImage(systemSymbolName: "photo", accessibilityDescription: L("Load Image"))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        loadBtn.toolTip = L("Load Image")
        loadBtn.target = self
        loadBtn.action = #selector(loadImageClicked)
        loadBtn.contentTintColor = ToolbarLayout.iconColor
        stack.addArrangedSubview(loadBtn)
    }

    func addRedactOptions(to stack: NSStackView, ov: OverlayView) {
        let drawLabel = NSTextField(labelWithString: L("Draw:"))
        drawLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        drawLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(drawLabel)

        let textOnly = (editingAnnotation?.censorDrawScope == .textOnly)
            || (editingAnnotation == nil && UserDefaults.standard.bool(forKey: "censorTextOnly"))
        let drawSeg = NSSegmentedControl(labels: [L("All"), L("Text Only")], trackingMode: .selectOne,
                                          target: self, action: #selector(drawModeChanged(_:)))
        drawSeg.selectedSegment = textOnly ? 1 : 0
        drawSeg.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        (drawSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        drawSeg.sizeToFit()
        stack.addArrangedSubview(drawSeg)

        addSeparator(to: stack)

        let autoLabel = NSTextField(labelWithString: L("Auto:"))
        autoLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        autoLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(autoLabel)

        let btnH: CGFloat = 22
        let btnFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let btnY: CGFloat = 0 // Position handled by stack view

        addRedactButton(to: stack, title: L("All Text"), action: #selector(redactAllTextClicked),
                        font: btnFont, height: btnH, y: btnY)

        addRedactButton(to: stack, title: L("PII"), action: #selector(redactPIIClicked),
                        font: btnFont, height: btnH, y: btnY,
                        dropdownAction: #selector(redactTypesClicked(_:)))

        addRedactButton(to: stack, title: L("Faces"), action: #selector(redactFacesClicked),
                        font: btnFont, height: btnH, y: btnY)

        addRedactButton(to: stack, title: L("People"), action: #selector(redactPeopleClicked),
                        font: btnFont, height: btnH, y: btnY)
    }

    func addHintLabel(to stack: NSStackView, text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.3)
        stack.addArrangedSubview(label)
    }

    func addOutlineControls(to stack: NSStackView, ov: OverlayView) {
        let outlineEnabled: Bool
        let outlineCol: NSColor
        if let ann = editingAnnotation {
            outlineEnabled = ann.outlineColor != nil
            outlineCol = ann.outlineColor ?? ToolOptionsRowView.savedOutlineColor
        } else {
            outlineEnabled = UserDefaults.standard.bool(forKey: "annotationOutlineEnabled")
            outlineCol = ToolOptionsRowView.savedOutlineColor
        }
        let outlineBtn = NSButton(title: L("Outline"), target: self, action: #selector(annotationOutlineToggled(_:)))
        outlineBtn.bezelStyle = .recessed
        outlineBtn.setButtonType(.toggle)
        outlineBtn.state = outlineEnabled ? .on : .off
        outlineBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        outlineBtn.attributedTitle = NSAttributedString(string: L("Outline"), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .baselineOffset: 0.5,
        ])
        outlineBtn.sizeToFit()
        stack.addArrangedSubview(outlineBtn)

        let swatchSize: CGFloat = 18
        let swatch = NSButton()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: swatchSize).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: swatchSize).isActive = true
        swatch.title = ""
        swatch.isBordered = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = outlineCol.cgColor
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1.5
        swatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        swatch.layer?.opacity = outlineEnabled ? 1.0 : 0.3
        swatch.tag = ToolOptionTag.annotationOutlineColorSwatch.rawValue
        swatch.target = self
        swatch.action = #selector(annotationOutlineColorClicked(_:))
        stack.addArrangedSubview(swatch)
    }
}
