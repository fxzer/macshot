import Cocoa

// MARK: - Text, Stamp, Measure Drawing

extension Annotation {

    func drawText() {
        guard textDrawRect != .zero else { return }
        let pad: CGFloat = 4
        let pillRect = textDrawRect.insetBy(dx: -pad, dy: -pad)
        let cornerR: CGFloat = 4

        // Background pill
        if let bg = textBgColor {
            bg.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: cornerR, yRadius: cornerR).fill()
        }

        // Outline
        if let outline = textOutlineColor {
            outline.setStroke()
            let outlinePath = NSBezierPath(roundedRect: pillRect, xRadius: cornerR, yRadius: cornerR)
            outlinePath.lineWidth = 2
            outlinePath.stroke()
        }

        if let image = textImage {
            image.draw(in: textDrawRect)
        } else if let attrText = attributedText {
            drawAttributedTextLive(attrText, in: textDrawRect)
        } else if let attrText = styledAttributedTextForCurrentAppearance() {
            drawAttributedTextLive(attrText, in: textDrawRect)
        }
    }

    /// Re-render the text image from attributedText with current formatting properties.
    /// Call after changing fontSize, bold, italic, font family, alignment, etc. on a committed text annotation.
    func reRenderTextImage() {
        guard tool == .text, textDrawRect != .zero,
              let mutable = styledAttributedTextForCurrentAppearance()
        else { return }
        attributedText = mutable

        // Calculate new size using the current textDrawRect width
        let inset: CGFloat = 4
        let drawWidth = textDrawRect.width - inset * 2
        let boundingRect = mutable.boundingRect(
            with: NSSize(width: drawWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let newHeight = max(textDrawRect.height, ceil(boundingRect.height) + inset * 2)
        let imgSize = NSSize(width: textDrawRect.width, height: newHeight)

        // Re-render image
        let img = NSImage(size: imgSize, flipped: true) { _ in
            self.drawAttributedTextLive(
                mutable,
                in: NSRect(
                    x: 0,
                    y: 0,
                    width: imgSize.width,
                    height: imgSize.height)
            )
            return true
        }
        textImage = img

        // Update draw rect height (keep top edge fixed in AppKit coords: maxY stays the same)
        let heightDelta = newHeight - textDrawRect.height
        if heightDelta != 0 {
            textDrawRect = NSRect(
                x: textDrawRect.minX, y: textDrawRect.minY - heightDelta,
                width: textDrawRect.width, height: newHeight)
            startPoint = textDrawRect.origin
            endPoint = NSPoint(x: textDrawRect.maxX, y: textDrawRect.maxY)
        }

        outlineGlowImage = nil
    }

    func styledAttributedTextForCurrentAppearance() -> NSMutableAttributedString? {
        guard let attrText = attributedText else { return nil }
        let mutable = NSMutableAttributedString(attributedString: attrText)
        let range = NSRange(location: 0, length: mutable.length)
        guard range.length > 0 else { return mutable }

        var font: NSFont
        if let familyName = fontFamilyName, familyName != "System",
           let familyFont = NSFont(name: familyName, size: fontSize) {
            font = familyFont
        } else {
            font = NSFont.systemFont(ofSize: fontSize)
        }
        if isBold && isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
        } else if isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        } else if isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        mutable.addAttribute(.font, value: font, range: range)

        if isUnderline {
            mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            mutable.removeAttribute(.underlineStyle, range: range)
        }
        if isStrikethrough {
            mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            mutable.removeAttribute(.strikethroughStyle, range: range)
        }
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = textAlignment
        mutable.addAttribute(.paragraphStyle, value: paraStyle, range: range)
        return mutable
    }

    func drawAttributedTextLive(_ attrText: NSAttributedString, in drawRect: NSRect) {
        let inset: CGFloat = 4
        attrText.draw(in: NSRect(
            x: drawRect.minX + inset,
            y: drawRect.minY + inset,
            width: drawRect.width - inset * 2,
            height: drawRect.height - inset * 2
        ))
    }

    func drawNumber() {
        guard let number = number else { return }
        let radius = NumberCalloutGeometry.bubbleRadius(for: strokeWidth)
        let center = startPoint
        let targetPoint = endPoint
        let showsDetachedCallout = MagnifiedCalloutGeometry.shouldRenderDetachedCallout(
            sourceCenter: targetPoint,
            sourceRadius: MagnifiedCalloutGeometry.sourceDotRadius,
            destinationCenter: center,
            destinationRadius: radius
        )

        if showsDetachedCallout {
            if let funnelPath = MagnifiedCalloutGeometry.funnelPath(
                sourceCenter: targetPoint,
                sourceRadius: MagnifiedCalloutGeometry.sourceDotRadius,
                destinationCenter: center,
                destinationRadius: radius
            ) {
                color.withAlphaComponent(0.22).setFill()
                NSGraphicsContext.current?.cgContext.addPath(funnelPath)
                NSGraphicsContext.current?.cgContext.fillPath()
            }

            let sourceDotRect = NSRect(
                x: targetPoint.x - MagnifiedCalloutGeometry.sourceDotRadius,
                y: targetPoint.y - MagnifiedCalloutGeometry.sourceDotRadius,
                width: MagnifiedCalloutGeometry.sourceDotRadius * 2,
                height: MagnifiedCalloutGeometry.sourceDotRadius * 2
            )
            color.setFill()
            NSBezierPath(ovalIn: sourceDotRect).fill()
        }

        // Draw the circle on top of the cone
        let circleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        // Outline behind circle
        if let oc = outlineColor {
            let outlineCircle = NSBezierPath(ovalIn: circleRect.insetBy(dx: -2, dy: -2))
            outlineCircle.lineWidth = 3
            oc.setStroke()
            outlineCircle.stroke()
        }
        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        // Choose contrasting text color: black for light backgrounds, white for dark
        let textColor: NSColor = {
            guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            return luminance > 0.6 ? .black : .white
        }()
        let fontSize = radius * 1.1
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let numberText = numberFormat.format(number)
        if let cgContext = NSGraphicsContext.current?.cgContext {
            NumberCalloutTextLayout.draw(
                text: numberText,
                font: font,
                fillColor: color,
                in: circleRect,
                cgContext: cgContext
            )
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let measured = (numberText as NSString).size(withAttributes: attrs)
            let origin = CGPoint(
                x: floor(circleRect.midX - measured.width / 2),
                y: floor(circleRect.midY - measured.height / 2)
            )
            (numberText as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    func drawStamp() {
        guard let image = stampImage else { return }
        let rect = boundingRect
        guard rect.width > 0, rect.height > 0 else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
    }

    func drawMeasure() {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let distance = hypot(dx, dy)
        guard distance > 1 else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        // Main measurement line
        let lineColor = color
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        lineColor.setStroke()
        path.move(to: startPoint)
        path.line(to: endPoint)
        path.stroke()

        // Perpendicular end caps (small ticks at each end)
        let angle = atan2(dy, dx)
        let perpAngle = angle + .pi / 2
        let capLength: CGFloat = 6
        let capDx = capLength * cos(perpAngle)
        let capDy = capLength * sin(perpAngle)

        let capPath = NSBezierPath()
        capPath.lineWidth = 1.5
        capPath.lineCapStyle = .round
        lineColor.setStroke()
        // Start cap
        capPath.move(to: NSPoint(x: startPoint.x - capDx, y: startPoint.y - capDy))
        capPath.line(to: NSPoint(x: startPoint.x + capDx, y: startPoint.y + capDy))
        // End cap
        capPath.move(to: NSPoint(x: endPoint.x - capDx, y: endPoint.y - capDy))
        capPath.line(to: NSPoint(x: endPoint.x + capDx, y: endPoint.y + capDy))
        capPath.stroke()

        // Dimension label
        let unit = measureInPoints ? "pt" : "px"
        let s = measureInPoints ? 1.0 : scale
        let dispDistance = Int(distance * s)
        let dispWidth = Int(abs(dx) * s)
        let dispHeight = Int(abs(dy) * s)
        let labelText: String
        if dispWidth < 3 {
            labelText = "\(dispHeight)\(unit)"
        } else if dispHeight < 3 {
            labelText = "\(dispWidth)\(unit)"
        } else {
            labelText = "\(dispDistance)\(unit) (\(dispWidth) × \(dispHeight))"
        }

        let fontSize: CGFloat = 11
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = labelText as NSString
        let strSize = str.size(withAttributes: attrs)

        // Position label at midpoint, offset perpendicular to the line
        let midX = (startPoint.x + endPoint.x) / 2
        let midY = (startPoint.y + endPoint.y) / 2
        let offsetDist: CGFloat = 12
        let labelX = midX + offsetDist * cos(perpAngle) - strSize.width / 2
        let labelY = midY + offsetDist * sin(perpAngle) - strSize.height / 2

        // Background pill for readability
        let padding: CGFloat = 4
        let bgRect = NSRect(
            x: labelX - padding,
            y: labelY - padding / 2,
            width: strSize.width + padding * 2,
            height: strSize.height + padding
        )
        NSColor(white: 0.0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

        str.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }
}
