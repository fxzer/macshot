//
//  ToolOptionsRowView+AnnotationToolOptions.swift
//  macshot
//
//  点击即落点的标注类工具选项：数字、文字、测量、图章。
//

import Cocoa

extension ToolOptionsRowView {

    // MARK: - 数字格式与起始编号

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

        let startField = NSTextField(string: "\(ov.numberStartAt)")
        startField.formatter = Self.numberStartFormatter
        startField.alignment = .center
        startField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        startField.controlSize = .small
        startField.tag = ToolOptionTag.numberStartValueField.rawValue
        startField.delegate = self
        startField.target = self
        startField.action = #selector(numberStartFieldSubmitted(_:))
        startField.translatesAutoresizingMaskIntoConstraints = false
        startField.widthAnchor.constraint(equalToConstant: 36).isActive = true
        stack.addArrangedSubview(startField)

        let stepper = NSStepper()
        stepper.minValue = Double(NumberToolConfiguration.minStartValue)
        stepper.maxValue = Double(NumberToolConfiguration.maxStartValue)
        stepper.integerValue = ov.numberStartAt
        stepper.tag = ToolOptionTag.numberStartStepper.rawValue
        stepper.target = self
        stepper.action = #selector(numberStartChanged(_:))
        stack.addArrangedSubview(stepper)
    }

    // MARK: - 文字格式

    func addTextOptions(to stack: NSStackView, ov: OverlayView) {
        // 带底色的小方块按钮（B/I/U/S、✕/✓）共用边长。无边框按钮只约束宽度时，高度只跟随字号
        // （实测 26×15 / 28×14，成扁条）；24 是行内 recessed 按钮（字体、−/＋、填充、轮廓）的实测高度，
        // 既保证正方形，又与整行控件上下沿对齐。
        let chipSize: CGFloat = 24
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
            btn.widthAnchor.constraint(equalToConstant: chipSize).isActive = true
            btn.heightAnchor.constraint(equalToConstant: chipSize).isActive = true
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

        let sizeField = NSTextField(string: "\(Int(ov.textEditor.fontSize))")
        sizeField.formatter = Self.textFontSizeFormatter
        sizeField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeField.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.8)
        sizeField.alignment = .center
        sizeField.controlSize = .small
        sizeField.focusRingType = .none
        sizeField.usesSingleLineMode = true
        sizeField.isEditable = true
        sizeField.isSelectable = true
        sizeField.delegate = self
        sizeField.target = self
        sizeField.action = #selector(fontSizeFieldSubmitted(_:))
        sizeField.tag = ToolOptionTag.textFontSizeLabel.rawValue
        sizeField.translatesAutoresizingMaskIntoConstraints = false
        sizeField.widthAnchor.constraint(equalToConstant: 38).isActive = true
        stack.addArrangedSubview(sizeField)

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
            cancelBtn.widthAnchor.constraint(equalToConstant: chipSize).isActive = true
            cancelBtn.heightAnchor.constraint(equalToConstant: chipSize).isActive = true
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
            confirmBtn.widthAnchor.constraint(equalToConstant: chipSize).isActive = true
            confirmBtn.heightAnchor.constraint(equalToConstant: chipSize).isActive = true
            confirmBtn.tag = ToolOptionTag.textConfirmButton.rawValue
            stack.addArrangedSubview(confirmBtn)
        }
    }

    // MARK: - 测量单位

    func addMeasureToggle(to stack: NSStackView, ov: OverlayView) {
        let seg = NSSegmentedControl(labels: ["px", "pt"], trackingMode: .selectOne,
                                     target: self, action: #selector(measureUnitChanged(_:)))
        seg.selectedSegment = ov.currentMeasureInPoints ? 1 : 0
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)

        addHintLabel(to: stack, text: L("Hold 1 auto-vertical  ·  Hold 2 auto-horizontal"))
    }

    // MARK: - 图章与表情

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
}
