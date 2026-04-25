import Cocoa

// MARK: - Loupe (Magnifying Glass) Drawing

extension Annotation {

    // MARK: - Loupe (Magnifying Glass)

    func bakeLoupe() {
        guard tool == .loupe else { return }
        if let live = generateLoupeImage() {
            bakedBlurNSImage = live
        }
        // Do NOT set self.sourceImage = nil so that if the user moves it later, it can still magnify!
    }

    fileprivate func generateLoupeImage() -> NSImage? {
        guard tool == .loupe,
            let image = sourceImage,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let rect = boundingRect
        let size = min(rect.width, rect.height)
        guard size > 10 else { return nil }

        let samplePoint = loupeSourcePoint ?? NSPoint(x: rect.midX, y: rect.midY)
        guard let cropped = MagnifiedCalloutGeometry.croppedImage(
            from: cgImage,
            sourcePoint: samplePoint,
            bubbleDiameter: size,
            imageDrawRect: sourceImageBounds
        ) else { return nil }

        return NSImage(cgImage: cropped, size: NSSize(width: size, height: size))
    }

    // Cached loupe chrome objects (shared across all loupe annotations)
    static let loupeOuterShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.22)
        s.shadowOffset = NSSize(width: 0, height: -4)
        s.shadowBlurRadius = 10
        return s
    }()
    static let loupeGradient: CGGradient? = {
        let colors = [
            NSColor.white.withAlphaComponent(0.95).cgColor,
            NSColor(white: 0.7, alpha: 0.85).cgColor,
        ] as CFArray
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])
    }()

    func drawLoupe(in context: NSGraphicsContext) {
        let rect = boundingRect
        guard rect.width > 10, rect.height > 10 else { return }

        let size = min(rect.width, rect.height)
        let squareRect = NSRect(
            x: rect.origin.x + (rect.width - size) / 2,
            y: rect.origin.y + (rect.height - size) / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: squareRect)
        let bubbleCenter = NSPoint(x: squareRect.midX, y: squareRect.midY)
        let samplePoint = loupeSourcePoint ?? bubbleCenter
        let showsDetachedCallout = MagnifiedCalloutGeometry.shouldRenderDetachedCallout(
            sourceCenter: samplePoint,
            sourceRadius: MagnifiedCalloutGeometry.sourceDotRadius,
            destinationCenter: bubbleCenter,
            destinationRadius: size / 2
        )
        let connectorPath = MagnifiedCalloutGeometry.funnelPath(
            sourceCenter: samplePoint,
            sourceRadius: MagnifiedCalloutGeometry.sourceDotRadius,
            destinationCenter: bubbleCenter,
            destinationRadius: size / 2
        )

        if let connectorPath {
            context.saveGraphicsState()
            MagnifiedCalloutGeometry.connectorFillColor(for: color).setFill()
            context.cgContext.addPath(connectorPath)
            context.cgContext.fillPath()
            context.restoreGraphicsState()
        }

        if showsDetachedCallout {
            let sourceDotRect = NSRect(
                x: samplePoint.x - MagnifiedCalloutGeometry.sourceDotRadius,
                y: samplePoint.y - MagnifiedCalloutGeometry.sourceDotRadius,
                width: MagnifiedCalloutGeometry.sourceDotRadius * 2,
                height: MagnifiedCalloutGeometry.sourceDotRadius * 2
            )
            let sourceDot = NSBezierPath(ovalIn: sourceDotRect)
            MagnifiedCalloutGeometry.sourceDotColor(for: color).setFill()
            sourceDot.fill()
        }

        // 1. Outer drop shadow
        context.saveGraphicsState()
        Self.loupeOuterShadow.set()
        NSColor.white.setFill()
        path.fill()
        context.restoreGraphicsState()

        // 2. Magnified content clipped to circle
        context.saveGraphicsState()
        path.addClip()

        if let baked = bakedBlurNSImage {
            baked.draw(in: squareRect, from: NSRect(origin: .zero, size: baked.size),
                       operation: .sourceOver, fraction: 1.0)
        } else if let image = sourceImage {
            let imgSize = image.size
            let scaleX = imgSize.width / sourceImageBounds.width
            let scaleY = imgSize.height / sourceImageBounds.height
            let srcSize = size / loupeMagnification
            let fromRect = NSRect(
                x: (samplePoint.x - srcSize / 2 - sourceImageBounds.minX) * scaleX,
                y: (samplePoint.y - srcSize / 2 - sourceImageBounds.minY) * scaleY,
                width: srcSize * scaleX,
                height: srcSize * scaleY
            )
            context.imageInterpolation = .high
            image.draw(in: squareRect, from: fromRect, operation: .copy, fraction: 1.0)
        }
        context.restoreGraphicsState()

        // 3. Gradient border ring
        let cgCtx = context.cgContext
        let borderWidth: CGFloat = 4.0
        let innerPath = NSBezierPath(ovalIn: squareRect.insetBy(dx: borderWidth, dy: borderWidth))
        let ringPath = NSBezierPath()
        ringPath.append(path)
        ringPath.append(innerPath.reversed)
        cgCtx.saveGState()
        ringPath.addClip()
        if let gradient = Self.loupeGradient {
            cgCtx.drawLinearGradient(
                gradient,
                start: CGPoint(x: squareRect.midX, y: squareRect.maxY),
                end:   CGPoint(x: squareRect.midX, y: squareRect.minY),
                options: []
            )
        }
        cgCtx.restoreGState()
    }
}

// MARK: - Translate Overlay

extension Annotation {

    func drawTranslateOverlay() {
        guard let translatedText = text, !translatedText.isEmpty else { return }

        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return }

        // Background: use `color` (sampled avg color stored at creation time)
        // with a slight blur-like fill behind text
        let bgColor = color
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        bgColor.setFill()
        bgPath.fill()

        // Determine contrasting text color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bgColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        let textColor: NSColor = luminance > 0.55 ? .black : .white

        // Fit text into the rect — start at stored fontSize, shrink if needed
        let hPad: CGFloat = 3
        let vPad: CGFloat = 2
        let availW = rect.width - hPad * 2
        let availH = rect.height - vPad * 2

        var fs = max(8, fontSize)
        var attrStr: NSAttributedString
        repeat {
            let font = NSFont.systemFont(ofSize: fs, weight: .medium)
            attrStr = NSAttributedString(string: translatedText, attributes: [
                .font: font,
                .foregroundColor: textColor,
            ])
            let needed = attrStr.boundingRect(
                with: NSSize(width: availW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            if needed.height <= availH || fs <= 8 { break }
            fs -= 1
        } while fs > 8

        // Draw text top-aligned within the block
        let textRect = NSRect(
            x: rect.minX + hPad,
            y: rect.minY + vPad,
            width: availW,
            height: availH
        )
        attrStr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
