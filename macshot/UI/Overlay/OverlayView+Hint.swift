//
//  OverlayView+Hint.swift
//  macshot
//
//  Hint/toast system for showing temporary messages to the user.
//

import AppKit

extension OverlayView {

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
