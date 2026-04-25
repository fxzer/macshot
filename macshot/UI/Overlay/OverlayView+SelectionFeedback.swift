import AppKit

extension OverlayView {
    private static let helperFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let helperSmallFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    private static let helperSmallBoldFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let helperDimColor = NSColor.white.withAlphaComponent(0.7)

    func drawIdleHelperText() {
        // Only draw helper text on the monitor where the mouse is located
        guard isMouseOnCurrentScreen() else { return }

        let snapOn = windowSnapEnabled
        let snapText = snapOn ? L("ON") : L("OFF")
        let snapColor = snapOn ? NSColor.systemGreen : NSColor.systemOrange

        // Fonts
        let baseFont = Self.helperSmallFont
        let keyFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let labelColor = NSColor.white.withAlphaComponent(0.75)
        let keyBgColor = NSColor.white.withAlphaComponent(0.12)
        let keyBorderColor = NSColor.white.withAlphaComponent(0.25)

        // Key box dimensions - match text height
        let keyPadding: CGFloat = 4
        let keyCornerRadius: CGFloat = 4
        let keySpacing: CGFloat = 3

        // Helper to draw a key box
        func drawKey(_ text: String, at origin: NSPoint, highlight: Bool = false) -> NSRect {
            let color = highlight ? NSColor.systemGreen : NSColor.white
            let attrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: color]
            let size = (text as NSString).size(withAttributes: attrs)
            // Match text height exactly
            let rect = NSRect(
                x: origin.x,
                y: origin.y,
                width: size.width + keyPadding * 2,
                height: size.height
            )

            // Draw key background
            keyBgColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: keyCornerRadius, yRadius: keyCornerRadius).fill()

            // Draw key border
            keyBorderColor.setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: keyCornerRadius, yRadius: keyCornerRadius)
            border.lineWidth = 0.5
            border.stroke()

            // Draw key text
            let textPoint = NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.minY
            )
            (text as NSString).draw(at: textPoint, withAttributes: attrs)

            return rect
        }

        // Helper to draw label text
        func drawLabel(_ text: String, at origin: NSPoint) -> NSRect {
            let attrs: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: labelColor]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: origin, withAttributes: attrs)
            return NSRect(origin: origin, size: size)
        }

        // Layout parameters
        let margin: CGFloat = 20
        let lineSpacing: CGFloat = 8

        // Calculate content
        var lines: [(elements: [(type: String, text: String, width: CGFloat)], height: CGFloat)] = []

        var line1Elements: [(type: String, text: String, width: CGFloat)] = []
        let modeText = (windowSnapEnabled ? L("Click window") : L("Drag to select")) + " · "
        let modeSize = (modeText as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor])
        line1Elements.append(("label", modeText, modeSize.width))

        let snapLabel = L("Window snap:") + " "
        line1Elements.append(("label", snapLabel, (snapLabel as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width))
        line1Elements.append(("state", snapText, (snapText as NSString).size(withAttributes: [.font: keyFont, .foregroundColor: snapColor]).width))
        // Don't insert an empty label here — keep Tab close to the switch state.
        line1Elements.append(("key", "Tab", ("Tab" as NSString).size(withAttributes: [.font: keyFont]).width))

        lines.append((line1Elements, 14))

        // Line 2: F 全屏 & C 取色 & ESC 关闭
        var fullscreenElements: [(type: String, text: String, width: CGFloat)] = []
        fullscreenElements.append(("key", "F", ("F" as NSString).size(withAttributes: [.font: keyFont]).width))
        fullscreenElements.append(("label", L("Fullscreen"), (L("Fullscreen") as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width))

        let spacer = "  "
        fullscreenElements.append(("label", spacer, (spacer as NSString).size(withAttributes: [.font: baseFont]).width))

        fullscreenElements.append(("key", "C", ("C" as NSString).size(withAttributes: [.font: keyFont]).width))
        fullscreenElements.append(("label", L("Copy Color"), (L("Copy Color") as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width))

        fullscreenElements.append(("label", spacer, (spacer as NSString).size(withAttributes: [.font: baseFont]).width))

        fullscreenElements.append(("key", "Esc", ("Esc" as NSString).size(withAttributes: [.font: keyFont]).width))
        fullscreenElements.append(("label", L("Close"), (L("Close") as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width))

        lines.append((fullscreenElements, 14))

        // Divider 1
        lines.append(([(type: "divider", text: "", width: 0)], 0))

        // Line 3: 比例锁定标题
        let ratioHeaderLabel = L("Press number keys to lock selection ratio")
        lines.append((
            [(type: "label", text: ratioHeaderLabel, width: (ratioHeaderLabel as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width)],
            14
        ))

        // Line 3+: 比例锁定快捷键（完全按网格对齐）
        let ratioItems = aspectRatioShortcutItems(includeInvert: true)
        let ratioChunks = stride(from: 0, to: ratioItems.count, by: 3).map { start in
            Array(ratioItems[start..<min(start + 3, ratioItems.count)])
        }

        let fixedLabelWidth: CGFloat = 40.0

        for chunk in ratioChunks {
            var ratioLineElements: [(type: String, text: String, width: CGFloat)] = []

            for (idx, item) in chunk.enumerated() {
                ratioLineElements.append((
                    "key",
                    item.key,
                    (item.key as NSString).size(withAttributes: [.font: keyFont]).width
                ))

                let isLastInChunk = idx == chunk.count - 1
                let labelW: CGFloat = isLastInChunk ? (item.label as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width : fixedLabelWidth

                ratioLineElements.append((
                    isLastInChunk ? "label" : "fixed_label",
                    item.label,
                    labelW
                ))
            }

            lines.append((ratioLineElements, 14))
        }

        // Divider 2
        lines.append(([(type: "divider", text: "", width: 0)], 0))

        // Line 5: 选区记忆提示
        var line5Elements: [(type: String, text: String, width: CGFloat)] = []
        let rememberPrefix = L("After selection, press")
        line5Elements.append((
            "label",
            rememberPrefix,
            (rememberPrefix as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width
        ))
        let rememberSelectionEnabled = UserDefaults.standard.bool(forKey: "rememberLastSelection")
        let memoryKeyType = rememberSelectionEnabled ? "active_key" : "key"
        line5Elements.append((memoryKeyType, "`", ("`" as NSString).size(withAttributes: [.font: keyFont]).width))
        let rememberSuffix = L("remember this area")
        line5Elements.append((
            "label",
            rememberSuffix,
            (rememberSuffix as NSString).size(withAttributes: [.font: baseFont, .foregroundColor: labelColor]).width
        ))
        lines.append((line5Elements, 14))

        // Calculate total size
        var maxWidth: CGFloat = 0
        for line in lines {
            var lineWidth: CGFloat = 0
            for (i, elem) in line.elements.enumerated() {
                if elem.type == "key" || elem.type == "active_key" {
                    lineWidth += elem.width + keyPadding * 2 + keySpacing
                } else if elem.type == "state" {
                    lineWidth += elem.width + keySpacing
                } else {
                    lineWidth += elem.width
                }
                if i < line.elements.count - 1 {
                    lineWidth += keySpacing
                }
            }
            maxWidth = max(maxWidth, lineWidth)
        }

        let totalHeight: CGFloat = lines.enumerated().reduce(0) { result, item in
            let (index, line) = item
            let isLast = index == lines.count - 1
            return result + line.height + (isLast ? 0 : lineSpacing)
        }
        let bgPadding: CGFloat = 10
        let bgWidth = maxWidth + bgPadding * 2
        let bgHeight = totalHeight + bgPadding * 2

        // Position in bottom-left
        let bgX = margin
        let bgY = margin
        let bgRect = NSRect(x: bgX, y: bgY, width: bgWidth, height: bgHeight)

        // Draw background
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

        // Draw content
        var currentY = bgY + bgHeight - bgPadding - 13

        for line in lines {
            var currentX = bgX + bgPadding

            for (i, elem) in line.elements.enumerated() {
                switch elem.type {
                case "divider":
                    NSColor.white.withAlphaComponent(0.15).set()
                    let dividerRect = NSRect(x: bgX + bgPadding, y: currentY + 14, width: maxWidth, height: 1)
                    NSBezierPath(rect: dividerRect).fill()
                case "active_key":
                    let keyRect = drawKey(elem.text, at: NSPoint(x: currentX, y: currentY), highlight: true)
                    currentX += keyRect.width + keySpacing
                case "key":
                    let keyRect = drawKey(elem.text, at: NSPoint(x: currentX, y: currentY))
                    currentX += keyRect.width + keySpacing
                case "state":
                    let stateAttrs: [NSAttributedString.Key: Any] = [
                        .font: keyFont,
                        .foregroundColor: snapColor
                    ]
                    let stateSize = (elem.text as NSString).size(withAttributes: stateAttrs)
                    (elem.text as NSString).draw(at: NSPoint(x: currentX, y: currentY), withAttributes: stateAttrs)
                    currentX += stateSize.width + keySpacing
                case "fixed_label":
                    _ = drawLabel(elem.text, at: NSPoint(x: currentX, y: currentY))
                    currentX += elem.width + (i < line.elements.count - 1 ? keySpacing : 0)
                default:
                    let labelRect = drawLabel(elem.text, at: NSPoint(x: currentX, y: currentY))
                    currentX += labelRect.width + (i < line.elements.count - 1 ? keySpacing : 0)
                }
            }

            currentY -= line.height + lineSpacing
        }
    }

    private static let helperTextAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    func drawSelectingHelperText() {
        guard selectionRect.width >= 1, selectionRect.height >= 1 else { return }

        let text = L("Release to annotate and edit")
        let attrs = Self.helperTextAttrs
        let size = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 10
        let bgWidth = size.width + padding * 2
        let bgHeight = size.height + padding

        // Position below the selection, centered
        var labelX = selectionRect.midX - bgWidth / 2
        var labelY = selectionRect.minY - bgHeight - 8

        // If below screen, put above
        if labelY < bounds.minY + 4 {
            labelY = selectionRect.maxY + 8
        }
        // Clamp horizontal
        labelX = max(bounds.minX + 4, min(labelX, bounds.maxX - bgWidth - 4))

        let bgRect = NSRect(x: labelX, y: labelY, width: bgWidth, height: bgHeight)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

        (text as NSString).draw(
            at: NSPoint(x: bgRect.minX + padding, y: bgRect.minY + padding / 2),
            withAttributes: attrs)
    }

    private static let sizeLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static var sharedSizeLabelFont: NSFont { sizeLabelFont }

    private var sizeLabelAttrs: [NSAttributedString.Key: Any] {
        [.font: Self.sizeLabelFont, .foregroundColor: ToolbarLayout.iconColor]
    }

    func drawSizeLabel() {
        // Get pixel dimensions (account for Retina)
        let scale = window?.backingScaleFactor ?? 2.0
        let pixelW = Int(selectionRect.width * scale)
        let pixelH = Int(selectionRect.height * scale)

        let attrs = sizeLabelAttrs
        let widthAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.sizeLabelFont,
            .foregroundColor: selectionSizeSnapWidthActive ? NSColor.controlAccentColor : ToolbarLayout.iconColor
        ]
        let heightAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.sizeLabelFont,
            .foregroundColor: selectionSizeSnapHeightActive ? NSColor.controlAccentColor : ToolbarLayout.iconColor
        ]
        let padding: CGFloat = 6
        let gap: CGFloat = 8  // space between width and height labels

        // Calculate individual label sizes
        let widthText = "\(pixelW)"
        let heightText = "\(pixelH)"
        let widthTextSize = (widthText as NSString).size(withAttributes: widthAttrs)
        let heightTextSize = (heightText as NSString).size(withAttributes: heightAttrs)
        let timesText = "\u{00D7}"
        let timesTextSize = (timesText as NSString).size(withAttributes: attrs)

        let widthLabelW = widthTextSize.width + padding * 2
        let heightLabelW = heightTextSize.width + padding * 2
        let labelH = widthTextSize.height + padding

        // Total width including the × symbol
        let totalW = widthLabelW + gap + timesTextSize.width + gap + heightLabelW

        let screenMargin: CGFloat = 4
        let outsideGap: CGFloat = 4
        let insideGap: CGFloat = 4

        // Vertical: prefer outside above, then outside below, then inside selection (Snipaste-style).
        let outsideAboveY = selectionRect.maxY + outsideGap
        let fitsAboveOutside = outsideAboveY + labelH <= bounds.maxY - screenMargin
        let outsideBelowY = selectionRect.minY - outsideGap - labelH
        let fitsBelowOutside = outsideBelowY >= bounds.minY + screenMargin

        let insideTopY = selectionRect.maxY - insideGap - labelH
        let fitsInsideTop = insideTopY >= selectionRect.minY + screenMargin
        let insideBottomY = selectionRect.minY + insideGap
        let fitsInsideBottom = insideBottomY + labelH <= selectionRect.maxY - screenMargin

        let baseY: CGFloat
        let labelInsideSelection: Bool
        if fitsAboveOutside {
            baseY = outsideAboveY
            labelInsideSelection = false
        } else if fitsBelowOutside {
            baseY = outsideBelowY
            labelInsideSelection = false
        } else if fitsInsideTop {
            baseY = insideTopY
            labelInsideSelection = true
        } else if fitsInsideBottom {
            baseY = insideBottomY
            labelInsideSelection = true
        } else {
            // Very flat selection: center vertically in selection (best effort).
            baseY = selectionRect.midY - labelH / 2
            labelInsideSelection = true
        }

        // Horizontal: keep strip on-screen; when drawn inside selection, keep within selection width too.
        var baseX = selectionRect.midX - totalW / 2
        if labelInsideSelection {
            let innerMinX = selectionRect.minX + screenMargin
            let innerMaxX = selectionRect.maxX - screenMargin - totalW
            if innerMaxX >= innerMinX {
                baseX = min(max(baseX, innerMinX), innerMaxX)
            } else {
                baseX = selectionRect.midX - totalW / 2
            }
        }
        let outerMinX = bounds.minX + screenMargin
        let outerMaxX = bounds.maxX - screenMargin - totalW
        if outerMaxX >= outerMinX {
            baseX = min(max(baseX, outerMinX), outerMaxX)
        }

        let widthRect = NSRect(x: baseX, y: baseY, width: widthLabelW, height: labelH)
        widthLabelRect = widthRect
        ToolbarLayout.bgColor.setFill()
        NSBezierPath(roundedRect: widthRect, xRadius: 4, yRadius: 4).fill()

        let timesX = baseX + widthLabelW + gap
        (timesText as NSString).draw(
            at: NSPoint(x: timesX, y: baseY + padding / 2), withAttributes: attrs)

        let heightX = timesX + timesTextSize.width + gap
        let heightRect = NSRect(x: heightX, y: baseY, width: heightLabelW, height: labelH)
        heightLabelRect = heightRect
        ToolbarLayout.bgColor.setFill()
        NSBezierPath(roundedRect: heightRect, xRadius: 4, yRadius: 4).fill()

        (widthText as NSString).draw(
            at: NSPoint(x: widthRect.minX + padding, y: widthRect.minY + padding / 2),
            withAttributes: widthAttrs
        )
        (heightText as NSString).draw(
            at: NSPoint(x: heightRect.minX + padding, y: heightRect.minY + padding / 2),
            withAttributes: heightAttrs
        )

        sizeLabelRect = NSRect(x: baseX, y: baseY, width: totalW, height: labelH)
    }

    func drawResizeHandles() {
        for (_, rect) in allHandleRects() {
            ToolbarLayout.handleColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}
