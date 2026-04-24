//
//  ToolOptionsRowView+Builders.swift
//  macshot
//
//  UI builder methods for tool options controls.
//

import Cocoa

extension ToolOptionsRowView {

    // MARK: - Section builders

    func addSeparator(at x: CGFloat) -> CGFloat {
        let sep = NSView(frame: NSRect(x: x + 6, y: 8, width: 1, height: rowHeight - 16))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = ToolbarLayout.iconColor.withAlphaComponent(0.1).cgColor
        addSubview(sep)
        return x + 13
    }

    func supportsDrawColor(_ tool: AnnotationTool) -> Bool {
        switch tool {
        case .pencil, .line, .arrow, .rectangle, .ellipse, .marker, .number, .measure, .text:
            return true
        default:
            return false
        }
    }

    func addDrawColorControl(at x: CGFloat, tool: AnnotationTool, ov: OverlayView) -> CGFloat {
        var curX = x

        let label = NSTextField(labelWithString: L("Color"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: curX, y: (rowHeight - label.frame.height) / 2)
        addSubview(label)
        curX += label.frame.width + 4

        let swatchSize: CGFloat = 18
        let swatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - swatchSize) / 2, width: swatchSize, height: swatchSize))
        swatch.title = ""
        swatch.isBordered = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = (editingAnnotation?.color ?? ov.currentColor).cgColor
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1.5
        swatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        swatch.tag = 974
        swatch.target = self
        swatch.action = #selector(drawColorClicked(_:))
        addSubview(swatch)
        curX += swatchSize

        return curX
    }

    func addStrokeSlider(at x: CGFloat, tool: AnnotationTool, ov: OverlayView) -> CGFloat {
        var curX = x

        let nameLabel = NSTextField(labelWithString: (tool == .loupe || tool == .number) ? L("Size") : L("Stroke"))
        nameLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        nameLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        nameLabel.sizeToFit()
        nameLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - nameLabel.frame.height) / 2)
        addSubview(nameLabel)
        curX += nameLabel.frame.width + 4

        let currentVal = editingAnnotation?.strokeWidth ?? ov.activeStrokeWidthForTool(tool)
        let sliderW: CGFloat = 100
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
        slider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: sliderW, height: 20)
        slider.isContinuous = true
        slider.tag = tool.rawValue
        addSubview(slider)
        curX += sliderW + 4

        let val = Int(currentVal)
        let valStr = tool == .loupe ? "\(val)" : "\(val)px"
        let labelW: CGFloat = tool == .loupe ? 32 : (tool == .marker ? 38 : 28)
        let label = NSTextField(labelWithString: valStr)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        label.alignment = .right
        label.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: labelW, height: 14)
        label.tag = 997  // stroke value label
        addSubview(label)
        curX += labelW

        return curX
    }

    func addLineStyleSegment(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.segmentCount = LineStyle.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(lineStyleChanged(_:))
        seg.tag = 979  // tag for finding this segment to disable dashed/dotted when outline is on
        for (i, style) in LineStyle.allCases.enumerated() {
            seg.setImage(Self.lineStyleImage(style), forSegment: i)
            seg.setWidth(36, forSegment: i)
        }
        let currentStyle = editingAnnotation?.lineStyle ?? ov.currentLineStyle
        seg.selectedSegment = currentStyle.rawValue
        let segW = CGFloat(LineStyle.allCases.count) * 36
        seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: segW, height: 22)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect

        // Disable dashed/dotted for rect/ellipse when outline is enabled
        let isShapeTool = [AnnotationTool.rectangle, .ellipse].contains(editingAnnotation?.tool ?? ov.currentTool)
        // Only disable if editing an existing annotation that has outline
        let hasOutline = editingAnnotation?.outlineColor != nil
        if isShapeTool && hasOutline {
            for (i, style) in LineStyle.allCases.enumerated() {
                if style != .solid {
                    seg.setEnabled(false, forSegment: i)
                }
            }
            // Force solid if currently dashed/dotted
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

        addSubview(seg)
        curX += segW
        return curX
    }

    func addArrowStyleSegment(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
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
        let segW = CGFloat(ArrowStyle.allCases.count) * 30
        seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: segW, height: 22)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += segW
        return curX
    }

    func addShapeFillSegment(at x: CGFloat, tool: AnnotationTool, ov: OverlayView) -> CGFloat {
        var curX = x
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
        let segW = CGFloat(RectFillStyle.allCases.count) * 30
        seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: segW, height: 22)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += segW
        return curX
    }

    func addCensorModeSegment(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.segmentCount = CensorMode.allCases.count
        seg.trackingMode = .selectOne
        seg.target = self
        seg.action = #selector(censorModeChanged(_:))
        seg.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        for (i, mode) in CensorMode.allCases.enumerated() {
            seg.setLabel(mode.label, forSegment: i)
            seg.setWidth(0, forSegment: i)
        }
        let currentMode = CensorMode(rawValue: UserDefaults.standard.integer(forKey: "censorMode")) ?? .pixelate
        seg.selectedSegment = currentMode.rawValue
        seg.sizeToFit()
        seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: seg.frame.width, height: 22)
        addSubview(seg)
        curX += seg.frame.width
        return curX
    }

    /// Add a uniform redact action button using NSSegmentedControl for consistent sizing.
    /// If `dropdownAction` is provided, adds a second narrow segment with a ▾ arrow.
    func addRedactButton(at x: CGFloat, title: String, action: Selector,
                                  font: NSFont, height: CGFloat, y: CGFloat,
                                  dropdownAction: Selector? = nil) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl()
        seg.trackingMode = .momentary
        seg.font = font
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect

        if dropdownAction != nil {
            seg.segmentCount = 2
            seg.setLabel(title, forSegment: 0)
            seg.setLabel("▾", forSegment: 1)
            seg.setWidth(0, forSegment: 0)
            seg.setWidth(18, forSegment: 1)
            seg.target = self
            seg.action = #selector(piiSegmentClicked(_:))
        } else {
            seg.segmentCount = 1
            seg.setLabel(title, forSegment: 0)
            seg.setWidth(0, forSegment: 0)
            seg.target = self
            seg.action = action
        }

        seg.sizeToFit()
        seg.frame = NSRect(x: curX, y: y, width: seg.frame.width, height: height)
        addSubview(seg)
        curX += seg.frame.width + 4
        return curX
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
                // Thick shaft stops before the head
                let path = NSBezierPath()
                path.lineWidth = 2.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 6, y: mid))
                path.stroke()
                // Head
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
                // Arrowheads at both ends
                let headLen: CGFloat = 4
                let angle: CGFloat = .pi / 6
                // Start head
                let s1 = NSPoint(x: from.x + headLen * cos(angle), y: from.y + headLen * sin(angle))
                let s2 = NSPoint(x: from.x + headLen * cos(-angle), y: from.y + headLen * sin(-angle))
                let sh = NSBezierPath()
                sh.move(to: from)
                sh.line(to: s1)
                sh.line(to: s2)
                sh.close()
                sh.fill()
                // End head
                let e1 = NSPoint(x: to.x - headLen * cos(angle), y: to.y - headLen * sin(angle))
                let e2 = NSPoint(x: to.x - headLen * cos(-angle), y: to.y - headLen * sin(-angle))
                let eh = NSBezierPath()
                eh.move(to: to)
                eh.line(to: e1)
                eh.line(to: e2)
                eh.close()
                eh.fill()
                // Shaft
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
                // Open head (no fill)
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
                // Tail circle
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

    static func censorModeImage(_ mode: CensorMode) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(x: 2, y: 3, width: 16, height: 10)
            NSColor.black.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()
            switch mode {
            case .pixelate:
                let blockSize: CGFloat = 4
                ToolbarLayout.iconColor.setFill()
                for y in stride(from: rect.minY, to: rect.maxY, by: blockSize) {
                    for x in stride(from: rect.minX, to: rect.maxX, by: blockSize) {
                        NSBezierPath(rect: NSRect(x: x, y: y, width: blockSize - 1, height: blockSize - 1)).fill()
                    }
                }
            case .blur:
                ToolbarLayout.iconColor.withAlphaComponent(0.4).setFill()
                path.fill()
                NSColor.white.withAlphaComponent(0.35).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 2)).fill()
            case .solid:
                ToolbarLayout.iconColor.setFill()
                path.fill()
            case .erase:
                NSColor.systemGray.setFill()
                path.fill()
                // Draw diagonal erase symbol
                let erasePath = NSBezierPath()
                erasePath.lineWidth = 1.5
                NSColor.darkGray.setStroke()
                erasePath.move(to: NSPoint(x: rect.minX + 3, y: rect.maxY - 3))
                erasePath.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY + 3))
                erasePath.stroke()
            }
            return true
        }
    }

    static func beautifyStyleImage(_ style: BeautifyStyle) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        return NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(x: 2, y: 2, width: 20, height: 14)
            // Draw the gradient using the style's stops and angle
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: style.stops.map { $0.0.cgColor } as CFArray,
                                     locations: style.stops.map { $0.1 })
            if let gradient = gradient {
                let ctx = NSGraphicsContext.current?.cgContext
                ctx?.saveGState()
                let startPoint = CGPoint(x: rect.midX - cos(style.angle * .pi / 180) * rect.width / 2,
                                           y: rect.midY - sin(style.angle * .pi / 180) * rect.height / 2)
                let endPoint = CGPoint(x: rect.midX + cos(style.angle * .pi / 180) * rect.width / 2,
                                         y: rect.midY + sin(style.angle * .pi / 180) * rect.height / 2)
                ctx?.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
                ctx?.restoreGState()
            }
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.stroke()
            return true
        }
    }

    // MARK: - Tool-specific builders

    func addPencilControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .pencil, ov: ov)
        return curX
    }

    func addMarkerControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .marker, ov: ov)
        return curX
    }

    func addLineControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .line, ov: ov)
        curX += 8
        curX = addLineStyleSegment(at: curX, ov: ov)
        return curX
    }

    func addArrowControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .arrow, ov: ov)
        curX += 8
        curX = addArrowStyleSegment(at: curX, ov: ov)
        curX += 8
        curX = addLineStyleSegment(at: curX, ov: ov)
        return curX
    }

    func addRectangleControls(at x: CGFloat, tool: AnnotationTool, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: tool, ov: ov)
        curX += 8
        curX = addShapeFillSegment(at: curX, tool: tool, ov: ov)
        curX += 8
        curX = addLineStyleSegment(at: curX, ov: ov)
        return curX
    }

    func addEllipseControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .ellipse, ov: ov)
        curX += 8
        curX = addShapeFillSegment(at: curX, tool: .ellipse, ov: ov)
        curX += 8
        curX = addLineStyleSegment(at: curX, ov: ov)
        return curX
    }

    func addTextControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .text, ov: ov)
        return curX
    }

    func addNumberControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .number, ov: ov)
        return curX
    }

    func addLoupeControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .loupe, ov: ov)
        return curX
    }

    func addMeasureControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addStrokeSlider(at: curX, tool: .measure, ov: ov)
        return curX
    }

    func addPixelateControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addCensorModeSegment(at: curX, ov: ov)
        return curX
    }

    func addBlurControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addCensorModeSegment(at: curX, ov: ov)
        return curX
    }

    func addFilledRectangleControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        curX = addCensorModeSegment(at: curX, ov: ov)
        curX += 12
        let btnHeight: CGFloat = 22
        let y = (rowHeight - btnHeight) / 2
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        curX = addRedactButton(at: curX, title: L("Redact PII"), action: #selector(redactPIIClicked),
                               font: font, height: btnHeight, y: y, dropdownAction: #selector(redactTypesClicked(_:)))
        return curX
    }

    func addBeautifyControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        // Mode segment (window / rounded)
        let modeSeg = NSSegmentedControl()
        modeSeg.segmentCount = 2
        modeSeg.trackingMode = .selectOne
        modeSeg.target = self
        modeSeg.action = #selector(beautifyModeChanged(_:))
        modeSeg.setLabel(L("Window"), forSegment: 0)
        modeSeg.setLabel(L("Rounded"), forSegment: 1)
        modeSeg.setWidth(0, forSegment: 0)
        modeSeg.setWidth(0, forSegment: 1)
        modeSeg.selectedSegment = ov.beautifyMode.rawValue
        modeSeg.sizeToFit()
        modeSeg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: modeSeg.frame.width, height: 22)
        (modeSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(modeSeg)
        curX += modeSeg.frame.width + 8

        // Style dropdown button
        let styleBtn = NSPopUpButton(frame: .zero, pullsDown: false)
        styleBtn.target = self
        styleBtn.action = #selector(beautifyGradientClicked(_:))
        for (index, style) in BeautifyRenderer.styles.enumerated() {
            let item = NSMenuItem(title: "Style \(index)", action: nil, keyEquivalent: "")
            item.image = Self.beautifyStyleImage(style)
            styleBtn.menu?.addItem(item)
        }
        let currentStyleIndex = UserDefaults.standard.integer(forKey: "beautifyStyleIndex")
        styleBtn.selectItem(at: max(0, min(currentStyleIndex, BeautifyRenderer.styles.count - 1)))
        styleBtn.sizeToFit()
        styleBtn.frame = NSRect(x: curX, y: (rowHeight - styleBtn.frame.height) / 2, width: styleBtn.frame.width, height: styleBtn.frame.height)
        addSubview(styleBtn)
        curX += styleBtn.frame.width + 8

        // Corner radius slider (only for rounded mode)
        if ov.beautifyMode == .rounded {
            let label = NSTextField(labelWithString: L("Radius"))
            label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
            label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
            label.sizeToFit()
            label.frame.origin = NSPoint(x: curX, y: (rowHeight - label.frame.height) / 2)
            addSubview(label)
            curX += label.frame.width + 4

            let radius = UserDefaults.standard.integer(forKey: "beautifyCornerRadius")
            let slider = NSSlider(value: Double(radius), minValue: 8, maxValue: 80,
                                  target: self, action: #selector(beautifyRadiusChanged(_:)))
            slider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: 80, height: 20)
            slider.isContinuous = true
            addSubview(slider)
            curX += slider.frame.width + 4

            let valLabel = NSTextField(labelWithString: "\(radius)")
            valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
            valLabel.alignment = .right
            valLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
            valLabel.tag = 991
            addSubview(valLabel)
            curX += 32
        }

        // Padding slider
        let padLabel = NSTextField(labelWithString: L("Padding"))
        padLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        padLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        padLabel.sizeToFit()
        padLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - padLabel.frame.height) / 2)
        addSubview(padLabel)
        curX += padLabel.frame.width + 4

        let padding = UserDefaults.standard.integer(forKey: "beautifyPadding")
        let padSlider = NSSlider(value: Double(padding), minValue: 0, maxValue: 200,
                                  target: self, action: #selector(beautifyPaddingChanged(_:)))
        padSlider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: 80, height: 20)
        padSlider.isContinuous = true
        padSlider.tag = 992
        addSubview(padSlider)
        curX += padSlider.frame.width + 4

        let padValLabel = NSTextField(labelWithString: "\(padding)")
        padValLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        padValLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        padValLabel.alignment = .right
        padValLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
        padValLabel.tag = 993
        addSubview(padValLabel)
        curX += 32

        // Shadow slider
        let shadowLabel = NSTextField(labelWithString: L("Shadow"))
        shadowLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        shadowLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        shadowLabel.sizeToFit()
        shadowLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - shadowLabel.frame.height) / 2)
        addSubview(shadowLabel)
        curX += shadowLabel.frame.width + 4

        let shadow = UserDefaults.standard.integer(forKey: "beautifyShadowRadius")
        let shadowSlider = NSSlider(value: Double(shadow), minValue: 0, maxValue: 60,
                                     target: self, action: #selector(beautifyShadowChanged(_:)))
        shadowSlider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: 80, height: 20)
        shadowSlider.isContinuous = true
        shadowSlider.tag = 994
        addSubview(shadowSlider)
        curX += shadowSlider.frame.width + 4

        let shadowValLabel = NSTextField(labelWithString: "\(shadow)")
        shadowValLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        shadowValLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        shadowValLabel.alignment = .right
        shadowValLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
        shadowValLabel.tag = 995
        addSubview(shadowValLabel)
        curX += 32

        return curX
    }

    func addShapeRotationControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        // Info hint
        let hint = NSTextField(labelWithString: L("Drag handle or Shift+drag"))
        hint.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        hint.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: curX, y: (rowHeight - hint.frame.height) / 2)
        addSubview(hint)
        curX += hint.frame.width + 8

        return curX
    }

    func addTextFormattingControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        guard let ann = editingAnnotation, ann.tool == .text else {
            return x
        }

        // Font family picker
        let familyBtn = NSPopUpButton(frame: .zero, pullsDown: false)
        familyBtn.target = self
        familyBtn.action = #selector(fontFamilyClicked(_:))
        let families = getAllFontFamilies()
        for family in families {
            let item = NSMenuItem(title: family, action: nil, keyEquivalent: "")
            familyBtn.menu?.addItem(item)
        }
        if let currentFamily = ann.fontFamilyName, let idx = families.firstIndex(of: currentFamily) {
            familyBtn.selectItem(at: idx)
        } else {
            familyBtn.selectItem(at: 0)
        }
        familyBtn.sizeToFit()
        familyBtn.frame = NSRect(x: curX, y: (rowHeight - familyBtn.frame.height) / 2, width: min(140, familyBtn.frame.width), height: familyBtn.frame.height)
        addSubview(familyBtn)
        curX += familyBtn.frame.width + 8

        // Font size slider
        let sizeLabel = NSTextField(labelWithString: L("Size"))
        sizeLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        sizeLabel.sizeToFit()
        sizeLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - sizeLabel.frame.height) / 2)
        addSubview(sizeLabel)
        curX += sizeLabel.frame.width + 4

        let fontSize = ann.fontSize
        let sizeSlider = NSSlider(value: Double(fontSize), minValue: 8, maxValue: 120,
                                   target: self, action: #selector(fontSizeIncreased))
        sizeSlider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: 100, height: 20)
        sizeSlider.isContinuous = true
        addSubview(sizeSlider)
        curX += sizeSlider.frame.width + 4

        let sizeValLabel = NSTextField(labelWithString: "\(Int(fontSize))")
        sizeValLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        sizeValLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        sizeValLabel.alignment = .right
        sizeValLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
        sizeValLabel.tag = 996
        addSubview(sizeValLabel)
        curX += 32

        // Bold / Italic / Underline / Strikethrough buttons
        let styleConfig: [(title: String, action: Selector, isActive: () -> Bool)] = [
            ("B", #selector(boldToggled), { ann.isBold }),
            ("I", #selector(italicToggled), { ann.isItalic }),
            ("U", #selector(underlineToggled), { ann.isUnderline }),
            ("S", #selector(strikethroughToggled), { ann.isStrikethrough })
        ]

        for config in styleConfig {
            let btn = NSButton(frame: NSRect(x: curX, y: (rowHeight - 20) / 2, width: 26, height: 20))
            btn.title = config.title
            btn.isBordered = true
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            btn.target = self
            btn.action = config.action
            if config.isActive() {
            btn.state = .on
            }
            addSubview(btn)
            curX += 28
        }

        // Alignment buttons
        let alignSeg = NSSegmentedControl()
        alignSeg.segmentCount = 3
        alignSeg.trackingMode = .selectOne
        alignSeg.target = self
        alignSeg.action = #selector(alignmentChanged(_:))
        alignSeg.setImage(Self.alignmentImage(.left), forSegment: 0)
        alignSeg.setImage(Self.alignmentImage(.center), forSegment: 1)
        alignSeg.setImage(Self.alignmentImage(.right), forSegment: 2)
        alignSeg.setWidth(28, forSegment: 0)
        alignSeg.setWidth(28, forSegment: 1)
        alignSeg.setWidth(28, forSegment: 2)
        alignSeg.selectedSegment = ann.textAlignment.rawValue
        alignSeg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 84, height: 22)
        (alignSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(alignSeg)
        curX += 88

        // Color picker button
        let colorBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - 20) / 2, width: 40, height: 20))
        colorBtn.title = L("Color")
        colorBtn.isBordered = true
        colorBtn.bezelStyle = .rounded
        colorBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        colorBtn.target = self
        colorBtn.action = #selector(textBgColorClicked(_:))
        addSubview(colorBtn)
        curX += 44

        // Text background color button
        let bgBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - 20) / 2, width: 50, height: 20))
        bgBtn.title = L("Fill")
        bgBtn.isBordered = true
        bgBtn.bezelStyle = .rounded
        bgBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        bgBtn.target = self
        bgBtn.action = #selector(textBgColorClicked(_:))
        addSubview(bgBtn)
        curX += 54

        // Text outline color button
        let outlineBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - 20) / 2, width: 54, height: 20))
        outlineBtn.title = L("Outline")
        outlineBtn.isBordered = true
        outlineBtn.bezelStyle = .rounded
        outlineBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        outlineBtn.target = self
        outlineBtn.action = #selector(textOutlineColorClicked(_:))
        addSubview(outlineBtn)
        curX += 58

        return curX
    }

    private static func alignmentImage(_ align: NSTextAlignment) -> NSImage {
        let size = NSSize(width: 22, height: 14)
        return NSImage(size: size, flipped: false) { _ in
            ToolbarLayout.iconColor.setFill()
            let lineHeight: CGFloat = 2
            let lineGap: CGFloat = 3
            let lineCount = 3
            let totalH = CGFloat(lineCount) * lineHeight + CGFloat(lineCount - 1) * lineGap
            let startY = (size.height - totalH) / 2

            func drawLine(x: CGFloat) {
                let lineW: CGFloat = 10
                NSBezierPath(rect: NSRect(x: x, y: startY, width: lineW, height: lineHeight)).fill()
                NSBezierPath(rect: NSRect(x: x, y: startY + lineHeight + lineGap, width: lineW * 0.75, height: lineHeight)).fill()
                NSBezierPath(rect: NSRect(x: x, y: startY + (lineHeight + lineGap) * 2, width: lineW * 0.5, height: lineHeight)).fill()
            }

            switch align {
            case .left:
                drawLine(x: 3)
            case .center:
                let centeredX = (size.width - 10) / 2
                drawLine(x: centeredX)
            case .right:
                drawLine(x: size.width - 13)
            default:
                break
            }
            return true
        }
    }

    func getAllFontFamilies() -> [String] {
        let manager = NSFontManager.shared
        var families: [String] = []
        let availableFonts = manager.availableFontFamilies
        for family in availableFonts {
            if !family.hasPrefix(".") {
                families.append(family)
            }
        }
        return families.sorted()
    }

    func addVideoControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        // FPS slider
        let fpsLabel = NSTextField(labelWithString: L("FPS"))
        fpsLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        fpsLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        fpsLabel.sizeToFit()
        fpsLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - fpsLabel.frame.height) / 2)
        addSubview(fpsLabel)
        curX += fpsLabel.frame.width + 4

        let currentFPS = UserDefaults.standard.integer(forKey: "recordingFPS")
        let fpsSlider = NSSlider(value: Double(currentFPS), minValue: 15, maxValue: 120,
                                  target: self, action: #selector(fpsChanged(_:)))
        fpsSlider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: 100, height: 20)
        fpsSlider.isContinuous = true
        fpsSlider.tag = 998
        addSubview(fpsSlider)
        curX += fpsSlider.frame.width + 4

        let fpsValLabel = NSTextField(labelWithString: "\(currentFPS)")
        fpsValLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        fpsValLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        fpsValLabel.alignment = .right
        fpsValLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
        fpsValLabel.tag = 998
        fpsValLabel.tag += 100
        addSubview(fpsValLabel)
        curX += 32

        // Format selector
        let formatLabel = NSTextField(labelWithString: L("Format"))
        formatLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        formatLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        formatLabel.sizeToFit()
        formatLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - formatLabel.frame.height) / 2)
        addSubview(formatLabel)
        curX += formatLabel.frame.width + 4

        let formatSeg = NSSegmentedControl()
        formatSeg.segmentCount = 2
        formatSeg.trackingMode = .selectOne
        formatSeg.target = self
        formatSeg.action = #selector(recordingFormatChanged(_:))
        formatSeg.setLabel("MP4", forSegment: 0)
        formatSeg.setLabel("GIF", forSegment: 1)
        formatSeg.setWidth(0, forSegment: 0)
        formatSeg.setWidth(0, forSegment: 1)
        let currentFormat = UserDefaults.standard.string(forKey: "recordingFormat") ?? "mp4"
        formatSeg.selectedSegment = currentFormat == "mp4" ? 0 : 1
        formatSeg.sizeToFit()
        formatSeg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: formatSeg.frame.width, height: 22)
        (formatSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(formatSeg)
        curX += formatSeg.frame.width + 8

        // Highlight clicks toggle
        let highlightBtn = NSButton(checkboxWithTitle: L("Highlight Clicks"), target: self, action: #selector(highlightClicksToggled(_:)))
        highlightBtn.state = UserDefaults.standard.bool(forKey: "highlightMouseClicks") ? .on : .off
        highlightBtn.sizeToFit()
        highlightBtn.frame = NSRect(x: curX, y: (rowHeight - highlightBtn.frame.height) / 2, width: highlightBtn.frame.width, height: highlightBtn.frame.height)
        addSubview(highlightBtn)
        curX += highlightBtn.frame.width + 8

        return curX
    }

    func addCropControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        let hint = NSTextField(labelWithString: L("Drag corners to crop"))
        hint.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        hint.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: curX, y: (rowHeight - hint.frame.height) / 2)
        addSubview(hint)
        curX += hint.frame.width + 8

        return curX
    }

    func addCornerRadiusSlider(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let label = NSTextField(labelWithString: L("Radius"))
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: curX, y: (rowHeight - label.frame.height) / 2)
        addSubview(label)
        curX += label.frame.width + 4

        let radiusVal = editingAnnotation?.rectCornerRadius ?? ov.currentRectCornerRadius
        let slider = NSSlider(value: Double(radiusVal),
                              minValue: 0, maxValue: 30,
                              target: self, action: #selector(cornerRadiusChanged(_:)))
        slider.frame = NSRect(x: curX, y: (rowHeight - 20) / 2, width: 80, height: 20)
        slider.isContinuous = true
        addSubview(slider)
        curX += 80 + 4

        let valLabel = NSTextField(labelWithString: "\(Int(radiusVal))px")
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        valLabel.alignment = .right
        valLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
        valLabel.tag = 996
        addSubview(valLabel)
        curX += 28

        return curX
    }

    func addToggle(at x: CGFloat, title: String, isOn: Bool, action: @escaping (Bool) -> Void) -> CGFloat {
        var curX = x
        let btn = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        btn.state = isOn ? .on : .off
        btn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        btn.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.7)
        if let cell = btn.cell as? NSButtonCell {
            let attrTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.7),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
            cell.attributedTitle = attrTitle
        }
        btn.sizeToFit()
        btn.frame.origin = NSPoint(x: curX, y: (rowHeight - btn.frame.height) / 2)
        let handler = ToggleHandler(action: action)
        btn.target = handler
        btn.action = #selector(ToggleHandler.toggled(_:))
        objc_setAssociatedObject(btn, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
        addSubview(btn)
        curX += btn.frame.width + 8
        return curX
    }

    func addNumberOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let formats = ["1", "I", "A", "a"]
        let seg = NSSegmentedControl(labels: formats, trackingMode: .selectOne,
                                     target: self, action: #selector(numberFormatChanged(_:)))
        seg.selectedSegment = ov.currentNumberFormat.rawValue
        seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 100, height: 22)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += 100

        curX = addSeparator(at: curX)

        let startLabel = NSTextField(labelWithString: L("Start:"))
        startLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        startLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        startLabel.sizeToFit()
        startLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - startLabel.frame.height) / 2)
        addSubview(startLabel)
        curX += startLabel.frame.width + 4

        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 999
        stepper.integerValue = ov.numberStartAt
        stepper.target = self
        stepper.action = #selector(numberStartChanged(_:))
        stepper.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 19, height: 22)
        addSubview(stepper)

        let valLabel = NSTextField(labelWithString: ov.currentNumberFormat.format(ov.numberStartAt))
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.85)
        valLabel.tag = 999
        valLabel.sizeToFit()
        valLabel.frame.origin = NSPoint(x: curX + 22, y: (rowHeight - valLabel.frame.height) / 2)
        addSubview(valLabel)
        curX += 50

        return curX
    }

    func addTextOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        let displayName = ov.textEditor.fontFamily == "System" ? "System" : ov.textEditor.fontFamily
        let fontBtn = NSButton(title: "\(displayName) ▾", target: self, action: #selector(fontFamilyClicked(_:)))
        fontBtn.bezelStyle = .recessed
        fontBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        fontBtn.attributedTitle = NSAttributedString(string: "\(displayName) ▾", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .baselineOffset: 0.5,
        ])
        fontBtn.sizeToFit()
        fontBtn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: max(65, fontBtn.frame.width + 8), height: 22)
        addSubview(fontBtn)
        curX += fontBtn.frame.width + 6

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
            btn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 26, height: 22)
            addSubview(btn)
            curX += 28
        }

        curX = addSeparator(at: curX)

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
            btn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 26, height: 22)
            addSubview(btn)
            curX += 28
        }

        curX = addSeparator(at: curX)

        let minusBtn = NSButton(title: "−", target: self, action: #selector(fontSizeDecreased))
        minusBtn.bezelStyle = .recessed
        minusBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        minusBtn.isContinuous = true
        (minusBtn.cell as? NSButtonCell)?.setPeriodicDelay(0.3, interval: 0.05)
        minusBtn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 20, height: 22)
        addSubview(minusBtn)
        curX += 20

        let sizeLabel = NSTextField(labelWithString: "\(Int(ov.textEditor.fontSize))")
        sizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        sizeLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.7)
        sizeLabel.alignment = .center
        sizeLabel.tag = 998
        sizeLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 26, height: 14)
        addSubview(sizeLabel)
        curX += 26

        let plusBtn = NSButton(title: "+", target: self, action: #selector(fontSizeIncreased))
        plusBtn.bezelStyle = .recessed
        plusBtn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        plusBtn.isContinuous = true
        (plusBtn.cell as? NSButtonCell)?.setPeriodicDelay(0.3, interval: 0.05)
        plusBtn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 20, height: 22)
        addSubview(plusBtn)
        curX += 24

        curX = addSeparator(at: curX)

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
        fillLabelBtn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: max(30, fillLabelBtn.frame.width), height: 22)
        addSubview(fillLabelBtn)
        curX += fillLabelBtn.frame.width + 2

        let fillSwatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - fillSwatchSize) / 2, width: fillSwatchSize, height: fillSwatchSize))
        fillSwatch.title = ""
        fillSwatch.isBordered = false
        fillSwatch.wantsLayer = true
        fillSwatch.layer?.backgroundColor = ov.textEditor.bgColor.cgColor
        fillSwatch.layer?.cornerRadius = 3
        fillSwatch.layer?.borderWidth = 1.5
        fillSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        fillSwatch.layer?.opacity = ov.textEditor.bgEnabled ? 1.0 : 0.3
        fillSwatch.tag = 975
        fillSwatch.target = self
        fillSwatch.action = #selector(textBgColorClicked(_:))
        addSubview(fillSwatch)
        curX += fillSwatchSize + 6

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
        outlineLabelBtn.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: max(50, outlineLabelBtn.frame.width), height: 22)
        addSubview(outlineLabelBtn)
        curX += outlineLabelBtn.frame.width + 2

        let outlineSwatch = NSButton(frame: NSRect(x: curX, y: (rowHeight - fillSwatchSize) / 2, width: fillSwatchSize, height: fillSwatchSize))
        outlineSwatch.title = ""
        outlineSwatch.isBordered = false
        outlineSwatch.wantsLayer = true
        outlineSwatch.layer?.backgroundColor = ov.textEditor.outlineColor.cgColor
        outlineSwatch.layer?.cornerRadius = 3
        outlineSwatch.layer?.borderWidth = 1.5
        outlineSwatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        outlineSwatch.layer?.opacity = ov.textEditor.outlineEnabled ? 1.0 : 0.3
        outlineSwatch.tag = 976
        outlineSwatch.target = self
        outlineSwatch.action = #selector(textOutlineColorClicked(_:))
        addSubview(outlineSwatch)
        curX += fillSwatchSize

        if ov.textEditor.isEditing {
            curX = addSeparator(at: curX)
            let cancelBtn = NSButton(title: "✕", target: self, action: #selector(textCancelClicked))
            cancelBtn.bezelStyle = .smallSquare
            cancelBtn.isBordered = false
            cancelBtn.wantsLayer = true
            cancelBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
            cancelBtn.layer?.cornerRadius = 4
            cancelBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            cancelBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 11, weight: .bold)])
            cancelBtn.frame = NSRect(x: 0, y: (rowHeight - 22) / 2, width: 28, height: 22)
            cancelBtn.tag = 990
            addSubview(cancelBtn)

            let confirmBtn = NSButton(title: "✓", target: self, action: #selector(textConfirmClicked))
            confirmBtn.bezelStyle = .smallSquare
            confirmBtn.isBordered = false
            confirmBtn.wantsLayer = true
            confirmBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
            confirmBtn.layer?.cornerRadius = 4
            confirmBtn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            confirmBtn.attributedTitle = NSAttributedString(string: "✓", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .bold)])
            confirmBtn.frame = NSRect(x: 0, y: (rowHeight - 22) / 2, width: 28, height: 22)
            confirmBtn.tag = 991
            addSubview(confirmBtn)

            curX += 68
        }
        return curX
    }

    func addMeasureToggle(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let seg = NSSegmentedControl(labels: ["px", "pt"], trackingMode: .selectOne,
                                     target: self, action: #selector(measureUnitChanged(_:)))
        seg.selectedSegment = ov.currentMeasureInPoints ? 1 : 0
        seg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 60, height: 22)
        (seg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        addSubview(seg)
        curX += 72

        curX = addHintLabel(at: curX, text: L("Hold 1 auto-vertical  ·  Hold 2 auto-horizontal"))
        return curX
    }

    func addStampOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        for (groupIndex, group) in StampEmojis.commonGroups.enumerated() {
            for emoji in group {
                let btn = NSButton(title: emoji, target: self, action: #selector(quickEmojiClicked(_:)))
                btn.bezelStyle = .recessed
                btn.isBordered = false
                btn.font = NSFont.systemFont(ofSize: 14)
                btn.frame = NSRect(x: curX, y: (rowHeight - 26) / 2, width: 26, height: 26)
                addSubview(btn)
                curX += 26
            }
            if groupIndex < StampEmojis.commonGroups.count - 1 {
                curX += 2
                curX = addSeparator(at: curX)
            }
        }
        curX += 4

        curX = addSeparator(at: curX)

        let moreBtn = NSButton()
        moreBtn.bezelStyle = .recessed
        moreBtn.isBordered = false
        moreBtn.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: L("More Emojis"))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        moreBtn.toolTip = L("More Emojis")
        moreBtn.target = self
        moreBtn.action = #selector(moreEmojisClicked(_:))
        moreBtn.frame = NSRect(x: curX, y: (rowHeight - 26) / 2, width: 28, height: 26)
        addSubview(moreBtn)
        moreBtn.contentTintColor = ToolbarLayout.iconColor
        curX += 30

        let loadBtn = NSButton()
        loadBtn.bezelStyle = .recessed
        loadBtn.isBordered = false
        loadBtn.image = NSImage(systemSymbolName: "photo", accessibilityDescription: L("Load Image"))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        loadBtn.toolTip = L("Load Image")
        loadBtn.target = self
        loadBtn.action = #selector(loadImageClicked)
        loadBtn.frame = NSRect(x: curX, y: (rowHeight - 26) / 2, width: 28, height: 26)
        addSubview(loadBtn)
        loadBtn.contentTintColor = ToolbarLayout.iconColor
        curX += 30

        return curX
    }

    func addRedactOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x

        let drawLabel = NSTextField(labelWithString: L("Draw:"))
        drawLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        drawLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        drawLabel.sizeToFit()
        drawLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - drawLabel.frame.height) / 2)
        addSubview(drawLabel)
        curX += drawLabel.frame.width + 4

        let textOnly = (editingAnnotation?.censorDrawScope == .textOnly)
            || (editingAnnotation == nil && UserDefaults.standard.bool(forKey: "censorTextOnly"))
        let drawSeg = NSSegmentedControl(labels: [L("All"), L("Text Only")], trackingMode: .selectOne,
                                          target: self, action: #selector(drawModeChanged(_:)))
        drawSeg.selectedSegment = textOnly ? 1 : 0
        drawSeg.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        (drawSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
        drawSeg.sizeToFit()
        drawSeg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: drawSeg.frame.width, height: 22)
        addSubview(drawSeg)
        curX += drawSeg.frame.width + 4

        curX = addSeparator(at: curX)

        let autoLabel = NSTextField(labelWithString: L("Auto:"))
        autoLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        autoLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.4)
        autoLabel.sizeToFit()
        autoLabel.frame.origin = NSPoint(x: curX, y: (rowHeight - autoLabel.frame.height) / 2)
        addSubview(autoLabel)
        curX += autoLabel.frame.width + 4

        let btnH: CGFloat = 22
        let btnFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let btnY = (rowHeight - btnH) / 2

        curX = addRedactButton(at: curX, title: L("All Text"), action: #selector(redactAllTextClicked),
                               font: btnFont, height: btnH, y: btnY)

        curX = addRedactButton(at: curX, title: L("PII"), action: #selector(redactPIIClicked),
                               font: btnFont, height: btnH, y: btnY,
                               dropdownAction: #selector(redactTypesClicked(_:)))

        curX = addRedactButton(at: curX, title: L("Faces"), action: #selector(redactFacesClicked),
                               font: btnFont, height: btnH, y: btnY)

        curX = addRedactButton(at: curX, title: L("People"), action: #selector(redactPeopleClicked),
                               font: btnFont, height: btnH, y: btnY)

        return curX
    }

    func addBeautifyOptions(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
        let isSnap = ov.selectionIsWindowSnap

        if !isSnap {
            let modeSeg = NSSegmentedControl(labels: [L("Window"), L("Rounded")], trackingMode: .selectOne,
                                             target: self, action: #selector(beautifyModeChanged(_:)))
            modeSeg.selectedSegment = ov.beautifyMode == .window ? 0 : 1
            modeSeg.frame = NSRect(x: curX, y: (rowHeight - 22) / 2, width: 90, height: 22)
            (modeSeg.cell as? NSSegmentedCell)?.segmentStyle = .roundRect
            addSubview(modeSeg)
            curX += 90

            curX = addSeparator(at: curX)
        }

        curX = addBeautifySlider(at: curX, label: L("Padding"), value: ov.beautifyPadding, min: 16, max: 96, action: #selector(beautifyPaddingChanged(_:)), tag: 900)

        if !isSnap {
            curX = addBeautifySlider(at: curX, label: L("Radius"), value: ov.beautifyCornerRadius, min: 0, max: 100, action: #selector(beautifyRadiusChanged(_:)), tag: 901)
        }

        curX = addBeautifySlider(at: curX, label: L("Shadow"), value: ov.beautifyShadowRadius, min: 0, max: 100, action: #selector(beautifyShadowChanged(_:)), tag: 902)

        if ov.beautifyStyleIndex == -1 {
            curX = addBeautifySlider(at: curX, label: L("Blur"), value: ov.beautifyBackgroundBlur, min: 0, max: 50, action: #selector(beautifyBlurChanged(_:)), tag: 903)
        }

        curX = addSeparator(at: curX)

        curX += 2
        let swatchSize: CGFloat = 22
        let swatchBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - swatchSize) / 2, width: swatchSize, height: swatchSize))
        swatchBtn.bezelStyle = .recessed
        swatchBtn.isBordered = false
        swatchBtn.image = Self.gradientSwatchImage(styleIndex: ov.beautifyStyleIndex, size: swatchSize)
        swatchBtn.imageScaling = .scaleProportionallyUpOrDown
        swatchBtn.target = self
        swatchBtn.action = #selector(beautifyGradientClicked(_:))
        swatchBtn.toolTip = L("Gradient Style")
        swatchBtn.tag = 995
        addSubview(swatchBtn)
        curX += swatchSize + 2

        let arrowBtn = NSButton(frame: NSRect(x: curX, y: (rowHeight - 16) / 2, width: 14, height: 16))
        arrowBtn.bezelStyle = .recessed
        arrowBtn.isBordered = false
        arrowBtn.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        arrowBtn.target = self
        arrowBtn.action = #selector(beautifyGradientClicked(_:))
        addSubview(arrowBtn)
        arrowBtn.contentTintColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        curX += 18

        curX = addSeparator(at: curX)

        let toggleBtn = NSButton(checkboxWithTitle: L("On"), target: self, action: #selector(beautifyToggleChanged(_:)))
        toggleBtn.state = ov.beautifyEnabled ? .on : .off
        toggleBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        if let cell = toggleBtn.cell as? NSButtonCell {
            cell.attributedTitle = NSAttributedString(string: L("On"), attributes: [
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.7),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
        }
        toggleBtn.sizeToFit()
        toggleBtn.frame.origin = NSPoint(x: curX, y: (rowHeight - toggleBtn.frame.height) / 2)
        addSubview(toggleBtn)
        curX += toggleBtn.frame.width + 4

        return curX
    }

    func addBeautifySlider(at x: CGFloat, label: String, value: CGFloat, min: CGFloat, max: CGFloat, action: Selector, tag: Int) -> CGFloat {
        var curX = x
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        lbl.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.5)
        lbl.sizeToFit()
        lbl.frame.origin = NSPoint(x: curX, y: (rowHeight - lbl.frame.height) / 2)
        addSubview(lbl)
        curX += lbl.frame.width + 3

        let slider = NSSlider(value: Double(value), minValue: Double(min), maxValue: Double(max),
                              target: self, action: action)
        slider.frame = NSRect(x: curX, y: (rowHeight - 18) / 2, width: 60, height: 18)
        slider.isContinuous = true
        slider.tag = tag
        addSubview(slider)
        curX += 64

        let valLabel = NSTextField(labelWithString: "\(Int(value))")
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.6)
        valLabel.alignment = .right
        valLabel.frame = NSRect(x: curX, y: (rowHeight - 14) / 2, width: 28, height: 14)
        valLabel.tag = tag + 100
        addSubview(valLabel)
        curX += 32

        return curX
    }

    func addHintLabel(at x: CGFloat, text: String) -> CGFloat {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        label.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.3)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: x, y: (rowHeight - label.frame.height) / 2)
        addSubview(label)
        return x + label.frame.width + 8
    }

    func addOutlineControls(at x: CGFloat, ov: OverlayView) -> CGFloat {
        var curX = x
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
        let localRowHeight: CGFloat = frame.height > 0 ? frame.height : 30
        outlineBtn.frame = NSRect(x: curX, y: (localRowHeight - 22) / 2, width: max(50, outlineBtn.frame.width), height: 22)
        addSubview(outlineBtn)
        curX += outlineBtn.frame.width + 2

        let swatchSize: CGFloat = 18
        let swatch = NSButton(frame: NSRect(x: curX, y: (localRowHeight - swatchSize) / 2, width: swatchSize, height: swatchSize))
        swatch.title = ""
        swatch.isBordered = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = outlineCol.cgColor
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1.5
        swatch.layer?.borderColor = ToolbarLayout.iconColor.withAlphaComponent(0.4).cgColor
        swatch.layer?.opacity = outlineEnabled ? 1.0 : 0.3
        swatch.tag = 978
        swatch.target = self
        swatch.action = #selector(annotationOutlineColorClicked(_:))
        addSubview(swatch)
        curX += swatchSize
        return curX
    }

    static func gradientSwatchImage(styleIndex: Int, size: CGFloat) -> NSImage {
        if styleIndex == -1 {
            if let data = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData"),
               let img = NSImage(data: data) {
                return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
                    let rect = NSRect(x: 0, y: 0, width: size, height: size)
                    let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                    NSGraphicsContext.restoreGraphicsState()
                    ToolbarLayout.iconColor.withAlphaComponent(0.3).setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                    return true
                }
            }
            return NSImage(size: NSSize(width: size, height: size))
        }

        let styles = BeautifyRenderer.styles
        guard styleIndex >= 0, styleIndex < styles.count else {
            return NSImage(size: NSSize(width: size, height: size))
        }

        let style = styles[styleIndex]
        if #available(macOS 15.0, *), let mesh = style.meshDef,
           let meshImage = BeautifyRenderer.renderMeshSwatch(mesh, size: size) {
            return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
                let rect = NSRect(x: 0, y: 0, width: size, height: size)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                meshImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
                ToolbarLayout.iconColor.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 0.5
                path.stroke()
                return true
            }
        }

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(x: 0, y: 0, width: size, height: size)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            if let gradient = NSGradient(
                colors: style.stops.map { $0.0 },
                atLocations: style.stops.map { $0.1 },
                colorSpace: .deviceRGB)
            {
                gradient.draw(in: path, angle: style.angle - 90)
            }
            ToolbarLayout.iconColor.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}
