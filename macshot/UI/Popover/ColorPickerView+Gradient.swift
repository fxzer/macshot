import Cocoa

// MARK: - Gradient Tab Drawing & Interaction for ColorPickerView

extension ColorPickerView {

    static let modeSwitchHeight: CGFloat = 24
    static let gradientCardHeight: CGFloat = 38
    static let gradientSwatchCols = 4
    static let gradientSwatchHeight: CGFloat = 28
    static let gradientSwatchGap: CGFloat = 6
    static let gradientAngleRowHeight: CGFloat = 24

    static let gradientAngles: [(label: String, angle: CGFloat)] = [
        ("→", 0),
        ("↘", -45),
        ("↓", -90),
        ("↗", 45),
    ]

    func drawModeSwitch(in rect: NSRect) {
        NSColor(white: 0.2, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let halfW = (rect.width - 4) / 2
        let solidRect = NSRect(x: rect.minX + 2, y: rect.minY + 2, width: halfW, height: rect.height - 4)
        let gradRect = NSRect(x: solidRect.maxX, y: rect.minY + 2, width: halfW, height: rect.height - 4)
        solidTabRect = solidRect
        gradientTabRect = gradRect

        let activeRect = activeTab == .solid ? solidRect : gradRect
        ToolbarLayout.accentColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: activeRect, xRadius: 4.5, yRadius: 4.5).fill()

        drawTabTitle(L("Solid"), in: solidRect, active: activeTab == .solid)
        drawTabTitle(L("Gradient"), in: gradRect, active: activeTab == .gradient)
    }

    private func drawTabTitle(_ title: String, in rect: NSRect, active: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: active ? .semibold : .medium),
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(active ? 1.0 : 0.65),
        ]
        let ns = title as NSString
        let size = ns.size(withAttributes: attrs)
        ns.draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    func drawGradientTab(startingAt cursorYStart: CGFloat) {
        let pickerWidth = bounds.width
        let contentW = pickerWidth - padding * 2
        var cursorY = cursorYStart

        // --- 1. Random gradient toggle card ---
        cursorY -= padding
        let cardRect = NSRect(
            x: padding,
            y: cursorY - Self.gradientCardHeight,
            width: contentW,
            height: Self.gradientCardHeight
        )
        randomCardRect = cardRect
        drawRandomGradientCard(in: cardRect)
        cursorY -= Self.gradientCardHeight

        // --- 2. Curated gradient swatches (4 x 4) ---
        cursorY -= padding + 2
        let presets = AnnotationGradient.presets
        let cols = Self.gradientSwatchCols
        let gap = Self.gradientSwatchGap
        let swatchW = (contentW - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let swatchH = Self.gradientSwatchHeight
        gradientSwatchRects = []

        for (i, preset) in presets.enumerated() {
            let col = i % cols
            let row = i / cols
            let sx = padding + CGFloat(col) * (swatchW + gap)
            let sy = cursorY - swatchH - CGFloat(row) * (swatchH + gap)
            let sr = NSRect(x: sx, y: sy, width: swatchW, height: swatchH)
            gradientSwatchRects.append(sr)

            let path = NSBezierPath(roundedRect: sr, xRadius: 5, yRadius: 5)
            Annotation.drawGradientFill(preset, in: path)

            let isSelected = !isRandomGradient && gradientsMatchPalette(selectedGradient, preset)
            if isSelected {
                ToolbarLayout.iconColor.setStroke()
                let border = NSBezierPath(roundedRect: sr.insetBy(dx: -1.5, dy: -1.5), xRadius: 6, yRadius: 6)
                border.lineWidth = 2
                border.stroke()
            } else {
                ToolbarLayout.iconColor.withAlphaComponent(0.18).setStroke()
                let border = NSBezierPath(roundedRect: sr, xRadius: 5, yRadius: 5)
                border.lineWidth = 0.75
                border.stroke()
            }
        }
        let rows = (presets.count + cols - 1) / cols
        cursorY -= CGFloat(rows) * swatchH + CGFloat(max(0, rows - 1)) * gap

        // --- 3. Angle direction chips ---
        cursorY -= padding + 4
        let angles = Self.gradientAngles
        let chipGap: CGFloat = 6
        let chipW = (contentW - CGFloat(angles.count - 1) * chipGap) / CGFloat(angles.count)
        let chipH = Self.gradientAngleRowHeight
        angleChipRects = []

        for (i, item) in angles.enumerated() {
            let cx = padding + CGFloat(i) * (chipW + chipGap)
            let cr = NSRect(x: cx, y: cursorY - chipH, width: chipW, height: chipH)
            angleChipRects.append(cr)

            let isSelected = !isRandomGradient && abs(selectedGradient.angle - item.angle) < 1.0
            let bg = isSelected
                ? ToolbarLayout.accentColor.withAlphaComponent(0.85)
                : NSColor(white: 0.2, alpha: 0.85)
            bg.setFill()
            NSBezierPath(roundedRect: cr, xRadius: 5, yRadius: 5).fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(isSelected ? 1.0 : 0.75),
            ]
            let label = item.label as NSString
            let sz = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: cr.midX - sz.width / 2, y: cr.midY - sz.height / 2), withAttributes: attrs)
        }
        cursorY -= chipH

        // --- 4. Opacity slider ---
        cursorY -= padding + 4
        let oRect = NSRect(x: padding, y: cursorY - opacityBarHeight, width: contentW, height: opacityBarHeight)
        opacitySliderRect = oRect
        drawOpacitySlider(in: oRect)
    }

    private func drawRandomGradientCard(in rect: NSRect) {
        let cardPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor(white: 0.2, alpha: 0.9).setFill()
        cardPath.fill()

        if isRandomGradient {
            ToolbarLayout.accentColor.setStroke()
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: 6.5, yRadius: 6.5)
            ring.lineWidth = 2
            ring.stroke()
        } else {
            ToolbarLayout.iconColor.withAlphaComponent(0.18).setStroke()
            let border = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            border.lineWidth = 0.75
            border.stroke()
        }

        // Left rainbow icon badge
        let badgeSize: CGFloat = 24
        let badgeRect = NSRect(x: rect.minX + 7, y: rect.midY - badgeSize / 2, width: badgeSize, height: badgeSize)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
        Annotation.drawGradientFill(AnnotationGradient.randomPreviewSwatch, in: badgePath)

        if let sym = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        {
            let tinted = tintedSymbol(sym, color: .white)
            let sz = tinted.size
            tinted.draw(
                in: NSRect(x: badgeRect.midX - sz.width / 2, y: badgeRect.midY - sz.height / 2, width: sz.width, height: sz.height),
                from: .zero, operation: .sourceOver, fraction: 1.0
            )
        }

        let textX = badgeRect.maxX + 8
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.95),
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.55),
        ]
        let title = L("Random Gradient") as NSString
        let sub = L("New gradient on every stroke") as NSString
        let titleSz = title.size(withAttributes: titleAttrs)
        let subSz = sub.size(withAttributes: subAttrs)
        let totalTextH = titleSz.height + subSz.height + 1
        let topTextY = rect.midY + totalTextH / 2 - titleSz.height
        title.draw(at: NSPoint(x: textX, y: topTextY), withAttributes: titleAttrs)
        sub.draw(at: NSPoint(x: textX, y: topTextY - subSz.height - 1), withAttributes: subAttrs)

        if isRandomGradient,
           let check = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        {
            let tinted = tintedSymbol(check, color: ToolbarLayout.accentColor)
            let sz = tinted.size
            tinted.draw(
                in: NSRect(x: rect.maxX - sz.width - 8, y: rect.midY - sz.height / 2, width: sz.width, height: sz.height),
                from: .zero, operation: .sourceOver, fraction: 1.0
            )
        }
    }

    private func tintedSymbol(_ image: NSImage, color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.setFill()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    private func gradientsMatchPalette(_ a: AnnotationGradient, _ b: AnnotationGradient) -> Bool {
        a.colors.count == b.colors.count && zip(a.colors, b.colors).allSatisfy {
            ColorWheelRenderer.colorsMatch($0, $1, tolerance: 0.03)
        }
    }

    func handleGradientMouseDown(at point: NSPoint) -> Bool {
        if randomCardRect.contains(point) {
            isRandomGradient = true
            onRandomGradientSelected?()
            needsDisplay = true
            return true
        }

        for (i, rect) in gradientSwatchRects.enumerated() where rect.contains(point) {
            let preset = AnnotationGradient.presets[i]
            isRandomGradient = false
            selectedGradient = preset
            onGradientSelected?(preset)
            needsDisplay = true
            return true
        }

        for (i, rect) in angleChipRects.enumerated() where rect.contains(point) {
            let angle = Self.gradientAngles[i].angle
            isRandomGradient = false
            selectedGradient = selectedGradient.withAngle(angle)
            onGradientSelected?(selectedGradient)
            needsDisplay = true
            return true
        }

        return false
    }
}
