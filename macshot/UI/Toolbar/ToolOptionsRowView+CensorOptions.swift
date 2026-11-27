//
//  ToolOptionsRowView+CensorOptions.swift
//  macshot
//
//  打码工具的模式选择与自动脱敏（PII、人物、类型）按钮。
//

import Cocoa

extension ToolOptionsRowView {

    // MARK: - 打码模式

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

    // MARK: - 自动脱敏

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
}
