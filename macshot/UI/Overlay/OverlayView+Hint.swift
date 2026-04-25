//
//  OverlayView+Hint.swift
//  macshot
//
//  Hint/toast system for showing temporary messages to the user.
//

import AppKit

extension OverlayView {

    func hintSwatchColor(from colorString: String) -> NSColor? {
        if let color = NSColor(hex: colorString) {
            return color
        }

        let trimmed = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(?i)^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges == 4 else { return nil }

        func component(at index: Int) -> CGFloat? {
            guard let range = Range(match.range(at: index), in: trimmed),
                  let value = Int(trimmed[range]), (0...255).contains(value) else { return nil }
            return CGFloat(value) / 255.0
        }

        guard let r = component(at: 1),
              let g = component(at: 2),
              let b = component(at: 3) else { return nil }

        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    // MARK: - Hint Types

    enum HintState {
        case enabled    // Green - feature enabled
        case disabled   // Orange - feature disabled
        case info       // White - default info
    }

    // MARK: - Hint State Properties

    var overlayHintMessage: String? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.overlayHintMessage) as? String }
        set { objc_setAssociatedObject(self, &AssociatedKeys.overlayHintMessage, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var overlayHintOpacity: CGFloat {
        get { objc_getAssociatedObject(self, &AssociatedKeys.overlayHintOpacity) as? CGFloat ?? 0.0 }
        set { objc_setAssociatedObject(self, &AssociatedKeys.overlayHintOpacity, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var overlayHintColorString: String? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.overlayHintColorString) as? String }
        set { objc_setAssociatedObject(self, &AssociatedKeys.overlayHintColorString, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var overlayHintAttributedString: NSAttributedString? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.overlayHintAttributedString) as? NSAttributedString }
        set { objc_setAssociatedObject(self, &AssociatedKeys.overlayHintAttributedString, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var overlayHintFadeTimer: Timer? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.overlayHintFadeTimer) as? Timer }
        set { objc_setAssociatedObject(self, &AssociatedKeys.overlayHintFadeTimer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - Public API

    func showOverlayHint(_ message: String) {
        overlayHintFadeTimer?.invalidate()
        overlayHintMessage = message
        overlayHintAttributedString = nil
        overlayHintColorString = nil
        overlayHintOpacity = 1.0
        needsDisplay = true
        overlayHintFadeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) {
            [weak self] _ in
            self?.fadeOutOverlayHint()
        }
        overlayDelegate?.overlayViewDidShowHint(
            message: message,
            opacity: 1.0,
            colorString: nil,
            attributedString: nil
        )
    }

    func showColorCopiedHint(_ message: String, colorString: String) {
        overlayHintFadeTimer?.invalidate()
        overlayHintMessage = message
        overlayHintAttributedString = nil
        overlayHintColorString = colorString
        overlayHintOpacity = 1.0
        needsDisplay = true
        overlayHintFadeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) {
            [weak self] _ in
            self?.fadeOutOverlayHint()
        }
        overlayDelegate?.overlayViewDidShowHint(
            message: message,
            opacity: 1.0,
            colorString: colorString,
            attributedString: nil
        )
    }

    func syncOverlayHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {
        overlayHintFadeTimer?.invalidate()
        overlayHintMessage = message
        overlayHintColorString = colorString
        overlayHintAttributedString = attributedString
        overlayHintOpacity = opacity
        needsDisplay = true
        if opacity > 0.01 {
            overlayHintFadeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.fadeOutOverlayHint()
            }
        }
    }

    func showStateHint(message: String, statusText: String, state: HintState) {
        let color: NSColor
        switch state {
        case .enabled: color = NSColor.systemGreen
        case .disabled: color = NSColor.systemOrange
        case .info: color = NSColor.white
        }

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]

        let attrString = NSMutableAttributedString()
        attrString.append(NSAttributedString(
            string: message,
            attributes: baseAttrs.merging([.foregroundColor: NSColor.white]) { $1 }
        ))
        attrString.append(NSAttributedString(
            string: statusText,
            attributes: baseAttrs.merging([.foregroundColor: color]) { $1 }
        ))

        showAttributedHint(attrString)
    }

    // MARK: - Private

    private func showAttributedHint(_ attrString: NSAttributedString) {
        overlayHintFadeTimer?.invalidate()
        overlayHintMessage = attrString.string
        overlayHintAttributedString = attrString
        overlayHintColorString = nil
        overlayHintOpacity = 1.0
        needsDisplay = true
        overlayHintFadeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.fadeOutOverlayHint()
        }
        overlayDelegate?.overlayViewDidShowHint(
            message: attrString.string,
            opacity: 1.0,
            colorString: nil,
            attributedString: attrString
        )
    }

    private func fadeOutOverlayHint() {
        overlayHintOpacity = 0.0
        overlayHintMessage = nil
        overlayHintColorString = nil
        overlayHintAttributedString = nil
        needsDisplay = true
    }

    func resetHintState() {
        overlayHintFadeTimer?.invalidate()
        overlayHintFadeTimer = nil
        overlayHintOpacity = 0.0
        overlayHintMessage = nil
        overlayHintColorString = nil
        overlayHintAttributedString = nil
    }

    func drawOverlayHintIfNeeded() {
        guard overlayHintOpacity > 0.01, isMouseOnCurrentScreen() else { return }

        let attributedHint: NSAttributedString?
        let plainHint: String?

        if let cached = overlayHintAttributedString {
            attributedHint = cached
            plainHint = nil
        } else if let message = overlayHintMessage {
            attributedHint = nil
            plainHint = message
        } else {
            attributedHint = nil
            plainHint = nil
        }

        guard attributedHint != nil || plainHint != nil else { return }

        let displayString: NSAttributedString
        if let attributedHint {
            displayString = attributedHint
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(overlayHintOpacity),
            ]
            displayString = NSAttributedString(string: plainHint!, attributes: attributes)
        }

        let stringSize = displayString.size()
        let colorSwatchSize: CGFloat = 20
        let colorSwatchPadding: CGFloat = 8
        let hasColorSwatch = overlayHintColorString != nil
        let padding: CGFloat = 12
        let hintWidth = stringSize.width + padding * 2
            + (hasColorSwatch ? colorSwatchSize + colorSwatchPadding : 0)
        let hintHeight = max(stringSize.height + padding, colorSwatchSize + padding)
        let layoutBounds = isEditorMode ? visibleRect : bounds
        let topMargin: CGFloat = isEditorMode ? 12 : 40
        let hintRect = NSRect(
            x: layoutBounds.midX - hintWidth / 2,
            y: layoutBounds.maxY - hintHeight - topMargin,
            width: hintWidth,
            height: hintHeight)

        NSColor.black.withAlphaComponent(overlayHintOpacity * 0.7).setFill()
        NSBezierPath(roundedRect: hintRect, xRadius: 8, yRadius: 8).fill()

        let textY = hintRect.minY + (hintHeight - stringSize.height) / 2
        displayString.draw(at: NSPoint(x: hintRect.minX + padding, y: textY))

        if let colorString = overlayHintColorString, let color = hintSwatchColor(from: colorString) {
            let swatchRect = NSRect(
                x: hintRect.minX + padding + stringSize.width + colorSwatchPadding,
                y: hintRect.minY + (hintHeight - colorSwatchSize) / 2,
                width: colorSwatchSize,
                height: colorSwatchSize)
            color.setFill()
            NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).fill()
            NSColor.white.withAlphaComponent(0.3 * overlayHintOpacity).setStroke()
            NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4).stroke()
        }
    }
}

// MARK: - Associated Keys

private struct AssociatedKeys {
    static var overlayHintMessage = "overlayHintMessage"
    static var overlayHintOpacity = "overlayHintOpacity"
    static var overlayHintColorString = "overlayHintColorString"
    static var overlayHintAttributedString = "overlayHintAttributedString"
    static var overlayHintFadeTimer = "overlayHintFadeTimer"
}
