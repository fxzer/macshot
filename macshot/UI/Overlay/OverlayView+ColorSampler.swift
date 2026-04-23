import AppKit

/// Extension for integrating the color sampler magnifier into OverlayView.
extension OverlayView {

    // MARK: - Associated Object Keys

    private static var magnifierViewKey: UInt8 = 0
    private static var wasShiftPressedKey: UInt8 = 0
    private static var keyboardSamplePointKey: UInt8 = 0

    // MARK: - Computed Properties

    /// The color sampler magnifier view (lazy-loaded).
    private var magnifierView: ColorSamplerMagnifierView? {
        get {
            return objc_getAssociatedObject(self, &Self.magnifierViewKey) as? ColorSamplerMagnifierView
        }
        set {
            objc_setAssociatedObject(self, &Self.magnifierViewKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Track Shift key state for detecting press edges.
    private var wasShiftPressed: Bool {
        get {
            return (objc_getAssociatedObject(self, &Self.wasShiftPressedKey) as? Bool) ?? false
        }
        set {
            objc_setAssociatedObject(self, &Self.wasShiftPressedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var keyboardSamplePoint: NSPoint? {
        get {
            (objc_getAssociatedObject(self, &Self.keyboardSamplePointKey) as? NSValue)?.pointValue
        }
        set {
            let value = newValue.map { NSValue(point: $0) }
            objc_setAssociatedObject(self, &Self.keyboardSamplePointKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: - Public Methods

    /// Show the color sampler magnifier.
    func showColorSamplerMagnifier() {
        guard magnifierView == nil else { return }
        keyboardSamplePoint = nil

        let magnifier = ColorSamplerMagnifierView()

        // Set exitAfterCopy based on state:
        // - selecting/idle: exit after copy (user is selecting region)
        // - selected: stay in tool after copy (user is annotating)
        magnifier.exitAfterCopy = (state == .selecting || state == .idle)

        // Don't block mouse events — allow selection dragging
        magnifier.onColorCopied = { [weak self] colorString, format in
            self?.showColorCopiedToast(colorString, format: format)
        }
        magnifier.onExitRequested = { [weak self] in
            self?.hideColorSamplerMagnifier()
            self?.overlayDelegate?.overlayViewDidCancel()
        }

        addSubview(magnifier)
        self.magnifierView = magnifier

        updateMagnifierPosition()
    }

    /// Whether the color sampler magnifier is currently visible.
    var isColorSamplerMagnifierVisible: Bool { magnifierView != nil }

    /// Hide the color sampler magnifier.
    func hideColorSamplerMagnifier() {
        magnifierView?.removeFromSuperview()
        magnifierView = nil
        keyboardSamplePoint = nil
    }

    /// Update magnifier position and content (call from mouseMoved/mouseDragged).
    func updateMagnifierIfNeeded() {
        guard let magnifier = magnifierView,
              let screenshot = screenshotImage,
              let samplePoint = currentColorSamplerViewPoint() else { return }

        let canvasPoint = viewToCanvas(samplePoint)

        // Get color gamut setting from UserDefaults
        let gamutRaw = UserDefaults.standard.integer(forKey: "colorSamplerGamut")
        let gamut = ColorGamut(rawValue: gamutRaw) ?? .srgb

        // Sample color using OverlayView's accurate method with gamut setting
        guard let sampled = getSampledColor(at: canvasPoint, gamut: gamut) else { return }
        let hexColor = sampled.hex

        // Position magnifier at bottom-right of cursor (in view space for positioning)
        let offset: CGFloat = 20
        let magnifierOrigin = NSPoint(x: samplePoint.x + offset, y: samplePoint.y + offset)

        // Ensure magnifier stays within bounds
        var finalOrigin = magnifierOrigin
        if finalOrigin.x + magnifier.intrinsicContentSize.width > bounds.width {
            finalOrigin.x = samplePoint.x - offset - magnifier.intrinsicContentSize.width
        }
        if finalOrigin.y + magnifier.intrinsicContentSize.height > bounds.height {
            finalOrigin.y = samplePoint.y - offset - magnifier.intrinsicContentSize.height
        }

        magnifier.setFrameOrigin(finalOrigin)
        // Pass canvasPoint for magnification source (matches what we sample)
        magnifier.update(at: canvasPoint, screenImage: screenshot, hexColor: hexColor)
    }

    /// Toggle color format (triggered by Shift key press).
    func toggleColorSamplerFormat() {
        magnifierView?.toggleFormat()
    }

    /// Copy color and exit (triggered by C key).
    func copyColorAndExit() {
        magnifierView?.copyColorAndExit()
    }

    // MARK: - Private Methods

    private func updateMagnifierPosition() {
        guard let magnifier = magnifierView,
              let samplePoint = currentColorSamplerViewPoint() else { return }

        let offset: CGFloat = 20
        let magnifierOrigin = NSPoint(x: samplePoint.x + offset, y: samplePoint.y + offset)

        // Ensure magnifier stays within bounds
        var finalOrigin = magnifierOrigin
        if finalOrigin.x + magnifier.intrinsicContentSize.width > bounds.width {
            finalOrigin.x = samplePoint.x - offset - magnifier.intrinsicContentSize.width
        }
        if finalOrigin.y + magnifier.intrinsicContentSize.height > bounds.height {
            finalOrigin.y = samplePoint.y - offset - magnifier.intrinsicContentSize.height
        }

        magnifier.setFrameOrigin(finalOrigin)
    }

    private func currentColorSamplerViewPoint() -> NSPoint? {
        if let keyboardSamplePoint { return keyboardSamplePoint }
        guard let window else { return nil }
        return convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }

    func clearKeyboardColorSamplerPoint() {
        keyboardSamplePoint = nil
    }

    @discardableResult
    func moveColorSamplerPointBy(dx: CGFloat, dy: CGFloat) -> Bool {
        guard currentTool == .colorSampler || state == .selecting || magnifierView != nil,
              let currentPoint = currentColorSamplerViewPoint() else { return false }

        let sampleBounds = captureDrawRect.isEmpty ? bounds : captureDrawRect
        let newPoint = NSPoint(
            x: min(max(currentPoint.x + dx, sampleBounds.minX), sampleBounds.maxX),
            y: min(max(currentPoint.y + dy, sampleBounds.minY), sampleBounds.maxY)
        )
        keyboardSamplePoint = newPoint

        if state == .selecting {
            updateSelectionRectForCurrentSelectionDrag(to: newPoint, shiftHeld: NSEvent.modifierFlags.contains(.shift))
        } else {
            updateMagnifierIfNeeded()
            needsDisplay = true
        }

        return true
    }

    @discardableResult
    func copySampledColor(at canvasPoint: NSPoint) -> Bool {
        let gamutRaw = UserDefaults.standard.integer(forKey: "colorSamplerGamut")
        let gamut = ColorGamut(rawValue: gamutRaw) ?? .srgb
        guard let result = getSampledColor(at: canvasPoint, gamut: gamut) else { return false }

        let formatRaw = UserDefaults.standard.integer(forKey: "colorSamplerFormat")
        let format = ColorSamplerMagnifierView.ColorFormat(rawValue: formatRaw) ?? .hex
        let colorString = formatSampledColor(result, as: format)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(colorString, forType: .string)
        showColorCopiedToast(colorString, format: format)
        needsDisplay = true
        return true
    }

    private func showColorCopiedToast(_ colorString: String, format: ColorSamplerMagnifierView.ColorFormat) {
        let formatName = format.displayName
        let message = String(format: L("Copied %@"), "\(formatName): \(colorString)")
        showColorCopiedHint(message, colorString: colorString)
    }

    private func formatSampledColor(_ sampled: (color: NSColor, hex: String), as format: ColorSamplerMagnifierView.ColorFormat) -> String {
        guard let rgbColor = sampled.color.usingColorSpace(.sRGB) else { return sampled.hex }

        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))

        switch format {
        case .hex:
            return sampled.hex
        case .rgb:
            return "RGB(\(r), \(g), \(b))"
        }
    }

    // MARK: - Event Handling

    /// Handle flagsChanged event for Shift key detection.
    func overlayViewFlagsChanged(with event: NSEvent) {
        let shiftIsNowPressed = event.modifierFlags.contains(.shift)

        guard magnifierView != nil else {
            wasShiftPressed = shiftIsNowPressed
            return
        }

        // Detect Shift press edge (false → true)
        if shiftIsNowPressed && !wasShiftPressed {
            toggleColorSamplerFormat()
        }

        wasShiftPressed = shiftIsNowPressed
    }

    /// Handle keyDown event for C key (copy color) when the color sampler magnifier is active.
    /// Pixel movement is handled by handleArrowKeys (arrow keys) in OverlayView.
    func overlayViewKeyDown(with event: NSEvent) -> Bool {
        guard magnifierView != nil else { return false }

        if event.keyCode == 8 {  // C key — copy sampled color and exit
            copyColorAndExit()
            return true
        }

        return false
    }
}
