//
//  ToolOptionsRowView+Builders.swift
//  macshot
//
//  选项行的共用构件与绘图类工具选项（基于 NSStackView）。
//  文字、数字、测量、图章见 ToolOptionsRowView+AnnotationToolOptions.swift；
//  打码与自动脱敏见 ToolOptionsRowView+CensorOptions.swift；分段控件预览图见 ToolOptionsRowView+SegmentImages.swift。
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

final class PaintSwatchButton: NSButton {
    var solidColor: NSColor = .systemRed { didSet { needsDisplay = true } }
    var gradient: AnnotationGradient? { didSet { needsDisplay = true } }
    var isRandomGradient: Bool = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)

        if isRandomGradient {
            Annotation.drawGradientFill(AnnotationGradient.randomPreviewSwatch, in: path)
            if let sym = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
            {
                let tinted = NSImage(size: sym.size, flipped: false) { imgRect in
                    sym.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    NSColor.white.setFill()
                    imgRect.fill(using: .sourceAtop)
                    return true
                }
                let sz = tinted.size
                tinted.draw(
                    in: NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height),
                    from: .zero, operation: .sourceOver, fraction: 1.0
                )
            }
        } else if let grad = gradient {
            Annotation.drawGradientFill(grad, in: path)
        } else {
            solidColor.setFill()
            path.fill()
        }

        ToolbarLayout.iconColor.withAlphaComponent(0.4).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

extension ToolOptionsRowView {

    // MARK: - 共用构件

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

    func supportsDrawColor(_ tool: AnnotationTool, censorMode: CensorMode? = nil) -> Bool {
        switch tool {
        case .pencil, .line, .arrow, .rectangle, .filledRectangle, .ellipse, .marker, .number, .measure, .text:
            return true
        case .pixelate:
            return censorMode == .solid
        default:
            return false
        }
    }

    func addHintLabel(to stack: NSStackView, text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.3)
        stack.addArrangedSubview(label)
    }

    func addToggle(to stack: NSStackView, title: String, isOn: Bool, action: @escaping (Bool) -> Void) {
        stack.addArrangedSubview(ToolOptionToggleView(title: title, isOn: isOn, action: action))
    }

    // MARK: - 绘图类工具

    func addDrawColorControl(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
        let label = NSTextField(labelWithString: L("Color"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(label)

        let swatchSize: CGFloat = 18
        let swatch = PaintSwatchButton()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: swatchSize).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: swatchSize).isActive = true
        swatch.title = ""
        swatch.isBordered = false
        applyPaintState(to: swatch, tool: tool, ov: ov)
        swatch.tag = ToolOptionTag.drawColorSwatch.rawValue
        swatch.target = self
        swatch.action = #selector(drawColorClicked(_:))
        stack.addArrangedSubview(swatch)
    }

    func applyPaintState(to swatch: PaintSwatchButton, tool: AnnotationTool?, ov: OverlayView) {
        if let ann = editingAnnotation {
            swatch.solidColor = ann.color
            swatch.gradient = ann.strokeGradient
            swatch.isRandomGradient = false
            return
        }
        let supportsGradient = (tool ?? ov.currentTool) != .text
        swatch.solidColor = ov.currentColor
        guard supportsGradient else {
            swatch.gradient = nil
            swatch.isRandomGradient = false
            return
        }
        switch ov.drawPaintMode {
        case .solid:
            swatch.gradient = nil
            swatch.isRandomGradient = false
        case .gradient(let grad):
            swatch.gradient = grad
            swatch.isRandomGradient = false
        case .randomGradient:
            swatch.gradient = nil
            swatch.isRandomGradient = true
        }
    }

    func addStrokeSlider(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
        let nameLabel = NSTextField(labelWithString: (tool == .loupe || tool == .number) ? L("Size") : L("Stroke"))
        nameLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        nameLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(nameLabel)

        let currentVal: CGFloat
        if let ann = editingAnnotation, ann.tool == .loupe {
            currentVal = ann.boundingRect.width
        } else {
            currentVal = editingAnnotation?.strokeWidth ?? ov.activeStrokeWidthForTool(tool)
        }
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

    func addLoupeZoomControls(to stack: NSStackView, ov: OverlayView) {
        let label = NSTextField(labelWithString: L("Zoom"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(label)

        let currentMag = editingAnnotation?.loupeMagnification
            ?? MagnifiedCalloutGeometry.defaultMagnification(for: ov.currentLoupeSize)
        let slider = NSSlider(value: Double(currentMag),
                              minValue: Double(MagnifiedCalloutGeometry.minMagnification),
                              maxValue: Double(MagnifiedCalloutGeometry.maxMagnification),
                              target: self, action: #selector(loupeZoomSliderChanged(_:)))
        slider.isContinuous = true
        slider.tag = ToolOptionTag.loupeZoomSlider.rawValue
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(slider)

        let magStr = String(format: "%.1f×", currentMag).replacingOccurrences(of: ".0×", with: "×")
        let valLabel = NSTextField(labelWithString: magStr)
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        valLabel.alignment = .right
        valLabel.tag = ToolOptionTag.loupeZoomValueLabel.rawValue
        valLabel.translatesAutoresizingMaskIntoConstraints = false
        valLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(valLabel)
    }

    func addLineStyleSegment(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
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
        let currentStyle = editingAnnotation?.lineStyle ?? ov.lineStyle(for: tool)
        seg.selectedSegment = currentStyle.rawValue
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)

        // Disable unsupported non-solid styles when the current arrow style is thick,
        // and for rect/ellipse when outline is enabled.
        let activeTool = editingAnnotation?.tool ?? tool
        let isShapeTool = [AnnotationTool.rectangle, .ellipse].contains(activeTool)
        let hasOutline = editingAnnotation?.outlineColor != nil || ov.outlineEnabled(for: activeTool)
        let activeArrowStyle =
            activeTool == .arrow
            ? (editingAnnotation?.arrowStyle ?? ov.arrowStyle(for: activeTool))
            : nil
        let disallowNonSolid =
            (isShapeTool && hasOutline)
            || (activeTool == .arrow && activeArrowStyle == .thick)
        if disallowNonSolid {
            for (i, style) in LineStyle.allCases.enumerated() {
                if style != .solid { seg.setEnabled(false, forSegment: i) }
            }
            if currentStyle != .solid {
                seg.selectedSegment = LineStyle.solid.rawValue
                if let ann = editingAnnotation {
                    ann.lineStyle = .solid
                    ov.invalidateCommittedAnnotationRendering()
                }
                ov.setLineStyle(.solid, for: activeTool)
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
        seg.selectedSegment = (editingAnnotation?.arrowStyle ?? ov.arrowStyle(for: .arrow)).rawValue
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
        seg.selectedSegment = (editingAnnotation?.rectFillStyle ?? ov.rectFillStyle(for: tool)).rawValue
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        stack.addArrangedSubview(seg)
    }

    func addCornerRadiusSlider(to stack: NSStackView, ov: OverlayView) {
        let label = NSTextField(labelWithString: L("Radius"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        stack.addArrangedSubview(label)

        let radiusVal = editingAnnotation?.rectCornerRadius ?? ov.rectCornerRadius(for: .rectangle)
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

    func addOutlineControls(to stack: NSStackView, tool: AnnotationTool, ov: OverlayView) {
        let outlineEnabled: Bool
        let outlineCol: NSColor
        if let ann = editingAnnotation {
            outlineEnabled = ann.outlineColor != nil
            outlineCol = ann.outlineColor ?? ToolOptionsRowView.savedOutlineColor
        } else {
            outlineEnabled = ov.outlineEnabled(for: tool)
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
