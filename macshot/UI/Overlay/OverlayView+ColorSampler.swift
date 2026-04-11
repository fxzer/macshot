import AppKit

/// Extension for integrating the color sampler magnifier into OverlayView.
extension OverlayView {

    // MARK: - Associated Object Keys

    private static var magnifierViewKey: UInt8 = 0
    private static var wasShiftPressedKey: UInt8 = 0

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

    // MARK: - Public Methods

    /// Show the color sampler magnifier.
    func showColorSamplerMagnifier() {
        guard magnifierView == nil else { return }

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

    /// Hide the color sampler magnifier.
    func hideColorSamplerMagnifier() {
        magnifierView?.removeFromSuperview()
        magnifierView = nil
    }

    /// Update magnifier position and content (call from mouseMoved/mouseDragged).
    func updateMagnifierIfNeeded() {
        guard let magnifier = magnifierView,
              let screenshot = screenshotImage else { return }

        let mouseLoc = convert(window!.mouseLocationOutsideOfEventStream, from: nil)
        let canvasPoint = viewToCanvas(mouseLoc)

        // Sample color using OverlayView's accurate method
        guard let sampled = getSampledColor(at: canvasPoint) else { return }
        let hexColor = sampled.hex

        // Position magnifier at bottom-right of cursor (in view space for positioning)
        let offset: CGFloat = 20
        let magnifierOrigin = NSPoint(x: mouseLoc.x + offset, y: mouseLoc.y + offset)

        // Ensure magnifier stays within bounds
        var finalOrigin = magnifierOrigin
        if finalOrigin.x + magnifier.intrinsicContentSize.width > bounds.width {
            finalOrigin.x = mouseLoc.x - offset - magnifier.intrinsicContentSize.width
        }
        if finalOrigin.y + magnifier.intrinsicContentSize.height > bounds.height {
            finalOrigin.y = mouseLoc.y - offset - magnifier.intrinsicContentSize.height
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
        guard let magnifier = magnifierView else { return }

        let mouseLoc = convert(window!.mouseLocationOutsideOfEventStream, from: nil)
        let offset: CGFloat = 20
        let magnifierOrigin = NSPoint(x: mouseLoc.x + offset, y: mouseLoc.y + offset)

        // Ensure magnifier stays within bounds
        var finalOrigin = magnifierOrigin
        if finalOrigin.x + magnifier.intrinsicContentSize.width > bounds.width {
            finalOrigin.x = mouseLoc.x - offset - magnifier.intrinsicContentSize.width
        }
        if finalOrigin.y + magnifier.intrinsicContentSize.height > bounds.height {
            finalOrigin.y = mouseLoc.y - offset - magnifier.intrinsicContentSize.height
        }

        magnifier.setFrameOrigin(finalOrigin)
    }

    private func showColorCopiedToast(_ colorString: String, format: ColorSamplerMagnifierView.ColorFormat) {
        let formatName = format.displayName
        showOverlayError(String(format: L("Copied %@"), "\(formatName): \(colorString)"))
    }

    // MARK: - Event Handling

    /// Handle flagsChanged event for Shift key detection.
    func overlayViewFlagsChanged(with event: NSEvent) {
        let shiftIsNowPressed = event.modifierFlags.contains(.shift)

        // Detect Shift press edge (false → true)
        if shiftIsNowPressed && !wasShiftPressed {
            toggleColorSamplerFormat()
        }

        wasShiftPressed = shiftIsNowPressed
    }

    /// Handle keyDown event for C key (copy and exit) and WASD for mouse movement.
    func overlayViewKeyDown(with event: NSEvent) -> Bool {
        if event.keyCode == 8 {  // C key
            copyColorAndExit()
            return true
        }

        // WASD for pixel-perfect mouse movement (arrow keys are handled by handleArrowKeys)
        let dx: CGFloat
        let dy: CGFloat

        switch event.keyCode {
        case 0:    // A
            dx = -1; dy = 0
        case 2:    // D
            dx = 1; dy = 0
        case 1:    // S
            dx = 0; dy = -1
        case 13:   // W
            dx = 0; dy = 1
        default:
            return false
        }

        moveMouseBy(dx: dx, dy: dy)
        return true
    }

    func moveMouseBy(dx: CGFloat, dy: CGFloat) {
        let currentPos = NSEvent.mouseLocation
        let newPos = NSPoint(x: currentPos.x + dx, y: currentPos.y + dy)

        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                   mouseCursorPosition: newPos, mouseButton: .left) {
            moveEvent.flags = CGEventFlags(rawValue: 0)
            moveEvent.post(tap: .cghidEventTap)
        }
    }
}
