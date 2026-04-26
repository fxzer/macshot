//
//  OverlayView+RenderCache.swift
//  macshot
//
//  Annotation bitmap cache helpers for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Annotation Layer Cache

    /// Render all committed annotations into a transparent bitmap (canvas-space, no zoom).
    /// Reused across frames until annotations change, avoiding per-frame iteration.
    func annotationLayerImage() -> NSImage {
        if let cached = cachedAnnotationLayer { return cached }
        let image = renderAnnotationBitmap(annotations: annotations)
        setCachedAnnotationLayer(image)
        return image
    }

    var annotationLayerCache: NSImage? { cachedAnnotationLayer }

    /// Incrementally add a newly committed annotation onto a previous cache snapshot.
    /// Avoids a full rebuild which can cause a visible lag (cursor disappears for a frame).
    func appendToAnnotationCache(_ annotation: Annotation, previousCache: NSImage) {
        let monitor = PerfMonitor(enabled: annotation.tool == .marker)
        guard let existingCG = previousCache.cgImage(
            forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2.0
        let pxW = Int(ceil(size.width * scale))
        let pxH = Int(ceil(size.height * scale))
        let colorSpace =
            window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        cgCtx.scaleBy(x: scale, y: scale)

        cgCtx.draw(existingCG, in: CGRect(origin: .zero, size: size))

        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        annotation.draw(in: nsCtx)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return }
        let newImage = NSImage(cgImage: cgImage, size: size)
        setCachedAnnotationLayer(newImage)
        monitor.finish(
            tool: "Marker",
            context: "append cache",
            metadata: "points=\(annotation.points?.count ?? 0) strokeWidth=\(String(format: "%.1f", annotation.strokeWidth))"
        )
    }

    /// Build annotation layer excluding specific annotations (used during drag/resize).
    func buildAnnotationLayer(excluding: Set<ObjectIdentifier>) -> NSImage {
        let filtered = annotations.filter { !excluding.contains(ObjectIdentifier($0)) }
        return renderAnnotationBitmap(annotations: filtered)
    }

    /// Render annotations into a fixed bitmap at the current backing scale.
    /// Uses CGBitmapContext with the window's color space so colors match exactly.
    /// Returns an NSImage backed by a CGImage so AppKit never re-invokes a
    /// drawing handler when the image is drawn into a zoomed context.
    private func renderAnnotationBitmap(annotations: [Annotation]) -> NSImage {
        let size = bounds.size
        let scale = window?.backingScaleFactor ?? 2.0
        let pxW = Int(ceil(size.width * scale))
        let pxH = Int(ceil(size.height * scale))
        let colorSpace =
            window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(size: size) }
        cgCtx.scaleBy(x: scale, y: scale)

        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        drawAnnotationListLive(annotations, in: nsCtx)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: cgImage, size: size)
    }
}
