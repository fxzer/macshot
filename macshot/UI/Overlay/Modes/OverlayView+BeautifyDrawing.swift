import AppKit

extension OverlayView {
    private static func beautifyShadowBleed(for config: BeautifyConfig) -> CGFloat {
        let shadowOffset = min(config.shadowRadius * 0.4, 10)
        return config.shadowRadius + shadowOffset
    }

    func prepareBeautifyBackgroundCache() {
        guard let background = customBeautifyBackground else { return }
        var config = BeautifyConfig(
            customBackgroundImage: background,
            backgroundBlur: beautifyBackgroundBlur)
        config.prepareBackgroundCache(blurFunction: BeautifyRenderer.applyGaussianBlur)
        cachedBeautifyBgCGImage = config.cachedBackgroundCGImage
    }

    var beautifyConfig: BeautifyConfig {
        if beautifyStyleIndex == -1 && customBeautifyBackground == nil,
            let image = BeautifyBackgroundStore.loadImage()
        {
            customBeautifyBackground = image
            prepareBeautifyBackgroundCache()
        }
        return BeautifyConfig(
            mode: beautifyMode,
            styleIndex: beautifyStyleIndex,
            padding: beautifyPadding,
            cornerRadius: beautifyCornerRadius,
            shadowRadius: beautifyShadowRadius,
            bgRadius: 0,
            isWindowSnap: selectionIsWindowSnap,
            customBackgroundImage: beautifyStyleIndex == -1 ? customBeautifyBackground : nil,
            backgroundBlur: beautifyBackgroundBlur,
            cachedBackgroundCGImage: beautifyStyleIndex == -1 ? cachedBeautifyBgCGImage : nil)
    }

    static func editorLogicalSize(
        for imageSize: NSSize,
        beautifyEnabled: Bool,
        config: BeautifyConfig,
        isWindowSnap: Bool
    ) -> NSSize {
        guard beautifyEnabled else { return imageSize }

        let inset = config.padding + beautifyShadowBleed(for: config)
        let titleBarHeight: CGFloat = (config.mode == .window && !isWindowSnap) ? 28 : 0
        return NSSize(
            width: imageSize.width + inset * 2,
            height: imageSize.height + inset * 2 + titleBarHeight)
    }

    static func editorBeautifyOffset(
        beautifyEnabled: Bool,
        config: BeautifyConfig
    ) -> NSPoint {
        guard beautifyEnabled else { return .zero }
        let inset = config.padding + beautifyShadowBleed(for: config)
        return NSPoint(x: inset, y: inset)
    }

    var logicalSize: NSSize {
        guard let image = screenshotImage else { return .zero }
        let imageSize = image.size
        if isEditorMode && beautifyEnabled {
            return Self.editorLogicalSize(
                for: imageSize,
                beautifyEnabled: true,
                config: beautifyConfig,
                isWindowSnap: selectionIsWindowSnap)
        }
        return imageSize
    }

    func updateEditorFrameForBeautify() {
        guard isEditorMode else { return }

        let targetSize = logicalSize
        if beautifyEnabled {
            beautifyEditorOffset = Self.editorBeautifyOffset(
                beautifyEnabled: true,
                config: beautifyConfig)
        } else {
            beautifyEditorOffset = .zero
        }

        if isInsideScrollView {
            bounds.size = targetSize
        } else {
            frame.size = targetSize
            bounds.size = targetSize
        }

        cachedCompositedImage = nil
        needsDisplay = true
        overlayDelegate?.overlayViewLogicalSizeDidChange(targetSize)
    }

    /// The expanded rect including beautify padding (for live preview).
    func drawBeautifyPreview(context: NSGraphicsContext) {
        let config = beautifyConfig
        let pad = config.padding
        let cornerRadius = config.isWindowSnap ? 10 : config.cornerRadius  // native macOS corner radius for snapped windows
        let shadowRadius = config.shadowRadius
        let shadowOffset = min(shadowRadius * 0.4, 10)

        // Compute the expanded frame around the selection.
        // Shadow extends downward (negative Y in AppKit), so expand the origin down.
        let shadowBleed = shadowRadius + shadowOffset
        let expandedRect: NSRect
        if config.mode == .window && !config.isWindowSnap {
            let titleBarH: CGFloat = 28
            expandedRect = NSRect(
                x: selectionRect.minX - pad - shadowBleed,
                y: selectionRect.minY - pad - shadowBleed,
                width: selectionRect.width + pad * 2 + shadowBleed * 2,
                height: selectionRect.height + titleBarH + pad * 2 + shadowBleed * 2
            )
        } else {
            expandedRect = NSRect(
                x: selectionRect.minX - pad - shadowBleed,
                y: selectionRect.minY - pad - shadowBleed,
                width: selectionRect.width + pad * 2 + shadowBleed * 2,
                height: selectionRect.height + pad * 2 + shadowBleed * 2
            )
        }

        // Clear the dark overlay for the expanded area to make the preview visible
        context.saveGraphicsState()
        if !isEditorMode {
            // Overlay: re-draw the screenshot in the expanded area to erase the dark overlay,
            // then draw the dark overlay back so we have a clean base for the gradient.
            context.cgContext.saveGState()
            NSBezierPath(rect: expandedRect).addClip()
            if let image = screenshotImage {
                image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            }
            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(rect: expandedRect).fill()
            context.cgContext.restoreGState()
        }

        // Position the image/window centered within the expanded rect (not affected by shadow bleed)
        let innerX = selectionRect.minX - pad
        let innerY = selectionRect.minY - pad

        // Draw gradient background (inner rect without shadow bleed)
        let bgRect: NSRect
        if config.mode == .window && !config.isWindowSnap {
            let titleBarH: CGFloat = 28
            bgRect = NSRect(
                x: innerX, y: innerY, width: selectionRect.width + pad * 2,
                height: selectionRect.height + titleBarH + pad * 2)
        } else {
            bgRect = NSRect(
                x: innerX, y: innerY, width: selectionRect.width + pad * 2,
                height: selectionRect.height + pad * 2)
        }
        context.cgContext.saveGState()
        let bgPath = NSBezierPath(
            roundedRect: bgRect, xRadius: config.bgRadius, yRadius: config.bgRadius)
        bgPath.addClip()
        BeautifyRenderer.drawGradientBackground(
            in: bgRect, config: config, context: context.cgContext)
        context.cgContext.restoreGState()

        // Compute the image rect inside the expanded frame
        let imageRect: NSRect
        let windowRect: NSRect

        if config.mode == .window && !config.isWindowSnap {
            let titleBarH: CGFloat = 28
            let windowW = selectionRect.width
            let windowH = selectionRect.height + titleBarH
            windowRect = NSRect(
                x: innerX + pad,
                y: innerY + pad,
                width: windowW,
                height: windowH
            )
            imageRect = NSRect(
                x: windowRect.minX,
                y: windowRect.minY,
                width: windowW,
                height: windowH - titleBarH
            )
        } else {
            imageRect = NSRect(
                x: innerX + pad,
                y: innerY + pad,
                width: selectionRect.width,
                height: selectionRect.height
            )
            windowRect = imageRect
        }

        // Drop shadow (not for snapped windows — handled via transparency layer below)
        if shadowRadius > 0 && !config.isWindowSnap {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = shadowRadius
            shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
            shadow.set()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: windowRect, xRadius: cornerRadius, yRadius: cornerRadius)
                .fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if config.isWindowSnap {
            // Snapped window: use independently captured window image (has real transparent corners).
            // Draw it directly on top of the gradient — transparent corners reveal the gradient.
            context.cgContext.saveGState()

            // Drop shadow from the window shape
            if shadowRadius > 0 {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = shadowRadius
                shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
                shadow.set()
            }

            if let windowImg = snappedWindowImage {
                windowImg.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            } else if let image = screenshotImage {
                // Fallback: crop from screenshot (before window capture completes)
                let drawImage = effectsActive ? effectsProcessedScreenshot(image) : image
                drawImage.draw(
                    in: imageRect, from: selectionRect, operation: .sourceOver, fraction: 1.0)
            }

            // Draw annotations shifted to the preview position
            let dx = imageRect.minX - selectionRect.minX
            let dy = imageRect.minY - selectionRect.minY
            if dx != 0 || dy != 0 {
                context.cgContext.translateBy(x: dx, y: dy)
            }
            for annotation in annotations {
                annotation.draw(in: context)
            }
            drawCurrentAnnotationIfNeeded(in: context)
            if dx != 0 || dy != 0 {
                context.cgContext.translateBy(x: -dx, y: -dy)
            }

            context.cgContext.restoreGState()
        } else if config.mode == .window {
            // Draw window chrome
            let titleBarH: CGFloat = 28

            context.cgContext.saveGState()
            NSBezierPath(roundedRect: windowRect, xRadius: cornerRadius, yRadius: cornerRadius)
                .addClip()

            // Window background
            NSColor(white: 0.97, alpha: 1.0).setFill()
            NSBezierPath(rect: windowRect).fill()

            // Title bar
            let titleBarRect = NSRect(
                x: windowRect.minX, y: windowRect.maxY - titleBarH, width: windowRect.width,
                height: titleBarH)
            NSColor(white: 0.94, alpha: 1.0).setFill()
            NSBezierPath(rect: titleBarRect).fill()

            // Separator
            NSColor(white: 0.82, alpha: 1.0).setFill()
            NSBezierPath(
                rect: NSRect(
                    x: windowRect.minX, y: titleBarRect.minY - 0.5, width: windowRect.width,
                    height: 0.5)
            ).fill()

            // Traffic lights
            let buttonY = titleBarRect.midY
            let buttonRadius: CGFloat = 6
            let buttonStartX = windowRect.minX + 14
            let buttonSpacing: CGFloat = 20
            let trafficLights: [(NSColor, NSColor)] = [
                (
                    NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.35, alpha: 1.0),
                    NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.22, alpha: 1.0)
                ),
                (
                    NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.25, alpha: 1.0),
                    NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.15, alpha: 1.0)
                ),
                (
                    NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.35, alpha: 1.0),
                    NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.25, alpha: 1.0)
                ),
            ]
            for (i, (fill, ring)) in trafficLights.enumerated() {
                let cx = buttonStartX + CGFloat(i) * buttonSpacing
                let circleRect = NSRect(
                    x: cx - buttonRadius, y: buttonY - buttonRadius, width: buttonRadius * 2,
                    height: buttonRadius * 2)
                fill.setFill()
                NSBezierPath(ovalIn: circleRect).fill()
                ring.setStroke()
                let border = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
                border.lineWidth = 0.5
                border.stroke()
            }

            // Draw screenshot in content area (clipped to window shape), with effects if active
            if let image = screenshotImage {
                let drawImage = effectsActive ? effectsProcessedScreenshot(image) : image
                drawImage.draw(
                    in: imageRect, from: selectionRect, operation: .sourceOver, fraction: 1.0)
            }

            // Draw annotations shifted to the preview position (including current live annotation)
            let dx = imageRect.minX - selectionRect.minX
            let dy = imageRect.minY - selectionRect.minY
            if dx != 0 || dy != 0 {
                context.cgContext.translateBy(x: dx, y: dy)
            }
            for annotation in annotations {
                annotation.draw(in: context)
            }
            drawCurrentAnnotationIfNeeded(in: context)
            if dx != 0 || dy != 0 {
                context.cgContext.translateBy(x: -dx, y: -dy)
            }

            context.cgContext.restoreGState()
        } else {
            // Rounded mode — just rounded corners on the image
            context.cgContext.saveGState()
            NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
                .addClip()

            if let image = screenshotImage {
                let drawImage = effectsActive ? effectsProcessedScreenshot(image) : image
                drawImage.draw(in: imageRect, from: selectionRect, operation: .copy, fraction: 1.0)
            }

            // Draw annotations shifted to preview position (including current live annotation)
            let dx = imageRect.minX - selectionRect.minX
            let dy = imageRect.minY - selectionRect.minY
            if dx != 0 || dy != 0 {
                context.cgContext.translateBy(x: dx, y: dy)
            }
            for annotation in annotations {
                annotation.draw(in: context)
            }
            drawCurrentAnnotationIfNeeded(in: context)
            if dx != 0 || dy != 0 {
                context.cgContext.translateBy(x: -dx, y: -dy)
            }

            context.cgContext.restoreGState()
        }

        context.restoreGraphicsState()
    }

    /// Whether the current tool should show the options row.
    var toolHasOptionsRow: Bool {
        // Show options row for a selected annotation's tool even when currentTool is .select
        if selectedAnnotation != nil && toolOptionsRowView?.editingAnnotation != nil {
            return true
        }
        switch currentTool {
        case .pencil, .line, .arrow, .rectangle, .ellipse, .marker, .number, .loupe, .measure,
            .pixelate, .stamp:
            return true
        case .text:
            return true
        default:
            return false
        }
    }

    func startBeautifyToolbarAnimation() {
        beautifyToolbarAnimProgress = 0
        beautifyToolbarAnimTarget = beautifyEnabled
        beautifyToolbarAnimTimer?.invalidate()
        beautifyToolbarAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true)
        { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.beautifyToolbarAnimProgress += 0.08  // ~12 frames = 0.2s
            if self.beautifyToolbarAnimProgress >= 1.0 {
                self.beautifyToolbarAnimProgress = 1.0
                timer.invalidate()
                self.beautifyToolbarAnimTimer = nil
            }
            self.needsDisplay = true
        }
    }

    func startBackgroundRemovalSpinner() {
        backgroundRemovalSpinnerTimer?.invalidate()
        backgroundRemovalSpinnerPhase = 0

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.isRemovingBackground else {
                self.stopBackgroundRemovalSpinner()
                return
            }

            self.backgroundRemovalSpinnerPhase += .pi / 8
            if self.backgroundRemovalSpinnerPhase >= .pi * 2 {
                self.backgroundRemovalSpinnerPhase -= .pi * 2
            }
            self.needsDisplay = true
        }
        backgroundRemovalSpinnerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopBackgroundRemovalSpinner() {
        backgroundRemovalSpinnerTimer?.invalidate()
        backgroundRemovalSpinnerTimer = nil
        backgroundRemovalSpinnerPhase = 0
    }
}
