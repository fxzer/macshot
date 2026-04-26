//
//  OverlayView+LoupePreview.swift
//  macshot
//
//  Loupe preview drawing for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Loupe Preview

    func drawLoupePreview(at center: NSPoint) {
        guard let screenshot = screenshotImage, let context = NSGraphicsContext.current else {
            return
        }
        let size = currentLoupeSize
        let squareRect = NSRect(
            x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        let magnification: CGFloat = 2.0

        context.saveGraphicsState()
        context.cgContext.setAlpha(0.75)

        let path = NSBezierPath(ovalIn: squareRect)
        path.addClip()

        let srcSize = size / magnification
        let srcRect = NSRect(
            x: center.x - srcSize / 2, y: center.y - srcSize / 2, width: srcSize, height: srcSize)
        let imgSize = screenshot.size
        let drawRect = captureDrawRect
        let scaleX = imgSize.width / drawRect.width
        let scaleY = imgSize.height / drawRect.height
        let fromRect = NSRect(
            x: (srcRect.origin.x - drawRect.origin.x) * scaleX,
            y: (srcRect.origin.y - drawRect.origin.y) * scaleY,
            width: srcRect.width * scaleX, height: srcRect.height * scaleY)
        screenshot.draw(in: squareRect, from: fromRect, operation: .copy, fraction: 1.0)

        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 4
        path.stroke()

        NSColor.white.withAlphaComponent(0.82).setStroke()
        path.lineWidth = 2
        path.stroke()

        context.restoreGraphicsState()
    }
}
