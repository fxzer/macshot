import AppKit

/// Extension for integrating the color sampler magnifier into OverlayView.
extension OverlayView {

    // MARK: - Color Persistence and Sampling

    /// Compare two colors by RGB components (ignoring minor floating point differences).
    private func colorToHexString(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    func saveCustomColors() {
        let hexArray = customColors.map { color -> String in
            guard let c = color else { return "" }
            return colorToHexString(c)
        }
        UserDefaults.standard.set(hexArray, forKey: "customColors")
    }

    /// Sample a pixel color from the screenshot at the given canvas-space point.
    /// Returns (NSColor for display, hex string with values in the specified color gamut).
    func sampleColor(from image: NSImage, at canvasPoint: NSPoint, gamut: ColorGamut = .srgb) -> (
        color: NSColor, hex: String
    )? {
        // Use original CGImage if available for accurate color sampling
        // Falls back to NSImage's cgImage(forProposedRect:) if not set
        let cgImage: CGImage
        if let original = originalCGImage {
            cgImage = original
        } else {
            guard let img = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            cgImage = img
        }

        let imgSize = image.size
        let drawRect = captureDrawRect

        let px = (canvasPoint.x - drawRect.origin.x) * imgSize.width / drawRect.width
        let py = (canvasPoint.y - drawRect.origin.y) * imgSize.height / drawRect.height
        guard px >= 0, py >= 0, px < imgSize.width, py < imgSize.height else { return nil }

        // Map to CGImage pixel coordinates.
        let scaleX = CGFloat(cgImage.width) / imgSize.width
        let scaleY = CGFloat(cgImage.height) / imgSize.height
        let cgX = Int(px * scaleX)
        let cgY = Int(CGFloat(cgImage.height) - 1 - py * scaleY)  // flip Y for CGImage (top-left origin)
        guard cgX >= 0, cgX < cgImage.width, cgY >= 0, cgY < cgImage.height else { return nil }

        // First, always sample in sRGB to get the base color values
        // (screenshots are captured in sRGB color space)
        let srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let ctx = CGContext(
                data: nil, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: srgbColorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.draw(
            cgImage,
            in: CGRect(
                x: -CGFloat(cgX), y: -(CGFloat(cgImage.height) - 1 - CGFloat(cgY)),
                width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        guard let data = ctx.data else { return nil }
        let ptr = data.assumingMemoryBound(to: UInt8.self)

        // Read sRGB values
        let srgbR = ptr[0]
        let srgbG = ptr[1]
        let srgbB = ptr[2]

        // Convert to target color space based on gamut setting
        let (r, g, b) = gamut.convertFromSRGB(srgbR, srgbG, srgbB)

        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let color = NSColor(
            srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        return (color, hex)
    }

    /// Public method to sample color at a canvas point (for color sampler magnifier).
    func getSampledColor(at canvasPoint: NSPoint, gamut: ColorGamut = .srgb) -> (color: NSColor, hex: String)? {
        guard let screenshot = screenshotImage else { return nil }
        return sampleColor(from: screenshot, at: canvasPoint, gamut: gamut)
    }

    /// Get the current color gamut setting from UserDefaults.
    var currentColorGamut: ColorGamut {
        let gamutRaw = UserDefaults.standard.integer(forKey: "colorSamplerGamut")
        return ColorGamut(rawValue: gamutRaw) ?? .srgb
    }

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
        // Seed Shift state from the current modifier flags so the capture hotkey's
        // Shift key doesn't get treated as a fresh format-toggle press.
        wasShiftPressed = NSEvent.modifierFlags.contains(.shift)

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
        wasShiftPressed = false
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
