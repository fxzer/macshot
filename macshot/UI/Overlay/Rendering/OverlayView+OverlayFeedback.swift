//
//  OverlayView+OverlayFeedback.swift
//  macshot
//
//  Overlay error and barcode feedback helpers.
//

import AppKit

extension OverlayView {

    // MARK: - Overlay Error

    func showOverlayError(_ message: String) {
        overlayErrorTimer?.invalidate()
        overlayErrorMessage = message
        needsDisplay = true
        overlayErrorTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) {
            [weak self] _ in
            self?.overlayErrorMessage = nil
            self?.needsDisplay = true
        }
        overlayDelegate?.overlayViewDidShowError(message: message)
    }

    func syncOverlayError(message: String) {
        overlayErrorTimer?.invalidate()
        overlayErrorMessage = message
        needsDisplay = true
        overlayErrorTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) {
            [weak self] _ in
            self?.overlayErrorMessage = nil
            self?.needsDisplay = true
        }
    }

    func drawOverlayErrorIfNeeded() {
        guard let errorMessage = overlayErrorMessage, isMouseOnCurrentScreen() else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = errorMessage as NSString
        let size = string.size(withAttributes: attributes)
        let padding: CGFloat = 12
        let messageRect = NSRect(
            x: bounds.midX - (size.width + padding * 2) / 2,
            y: bounds.maxY - (size.height + padding) - 40,
            width: size.width + padding * 2,
            height: size.height + padding)

        NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: messageRect, xRadius: 8, yRadius: 8).fill()
        string.draw(
            at: NSPoint(x: messageRect.minX + padding, y: messageRect.minY + padding / 2),
            withAttributes: attributes)
    }

    func drawBackgroundRemovalProgressIfNeeded() {
        guard isRemovingBackground, (isEditorMode || isMouseOnCurrentScreen()) else { return }

        let message = L("Removing background…")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = message as NSString
        let size = string.size(withAttributes: attributes)
        let padding: CGFloat = 16
        let spinnerSize: CGFloat = 20
        let spacing: CGFloat = 10
        let messageRect = NSRect(
            x: bounds.midX - (size.width + padding * 2 + spinnerSize + spacing) / 2,
            y: bounds.maxY - max(size.height + padding, spinnerSize + padding) - 40,
            width: size.width + padding * 2 + spinnerSize + spacing,
            height: max(size.height + padding, spinnerSize + padding))

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: messageRect, xRadius: 10, yRadius: 10).fill()

        let spinnerCenter = NSPoint(x: messageRect.minX + padding + spinnerSize / 2, y: messageRect.midY)
        let spinnerRadius = spinnerSize / 2 - 1
        let spinnerLineLength: CGFloat = 6
        for i in 0..<8 {
            let angle = backgroundRemovalSpinnerPhase - CGFloat(i) * (.pi / 4)
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            let innerRadius = spinnerRadius - spinnerLineLength / 2
            let startPoint = NSPoint(
                x: spinnerCenter.x + direction.dx * innerRadius,
                y: spinnerCenter.y + direction.dy * innerRadius)
            let endPoint = NSPoint(
                x: spinnerCenter.x + direction.dx * (innerRadius + spinnerLineLength),
                y: spinnerCenter.y + direction.dy * (innerRadius + spinnerLineLength))

            let segmentPath = NSBezierPath()
            segmentPath.move(to: startPoint)
            segmentPath.line(to: endPoint)
            segmentPath.lineCapStyle = .round
            segmentPath.lineWidth = 2.5
            NSColor.white.withAlphaComponent(max(0.2, 1.0 - CGFloat(i) * 0.12)).setStroke()
            segmentPath.stroke()
        }

        string.draw(
            at: NSPoint(
                x: messageRect.minX + padding + spinnerSize + spacing,
                y: messageRect.midY - size.height / 2),
            withAttributes: attributes)
    }

    // MARK: - Barcode / QR Detection

    func scheduleBarcodeDetection() {
        barcodeDetector.cancel()
        needsDisplay = true
        guard state == .selected, let screenshot = screenshotImage else { return }
        barcodeDetector.scan(
            image: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect
        ) { [weak self] in
            self?.needsDisplay = true
        }
    }
}
