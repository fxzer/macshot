//
//  OverlayView+OutputRendering.swift
//  macshot
//
//  Output rendering helpers for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Output

    /// Render screenshot + all existing annotations into a full-size image.
    /// Used as source for pixelate/blur so they operate on the composited result.
    /// Rasterized at the screenshot's native pixel scale — censor tools extract
    /// pixels via cgImage(forProposedRect:), which rasterizes closure-based
    /// images at 72dpi (half resolution on retina).
    func compositedImage() -> NSImage? {
        if let cached = cachedCompositedImage { return cached }
        guard let screenshot = screenshotImage else { return nil }
        if annotations.isEmpty { return screenshot }
        var memory = MemoryDiagnostics.makeScope(
            "OverlayView.compositedImage",
            images: [("screenshot", screenshot)],
            metadata: "annotations=\(annotations.count)"
        )

        let drawRect = captureDrawRect
        let annotationsCopy = annotations
        let scale = ImageRasterizer.pixelScale(of: screenshot)
        let pxW = max(1, Int((drawRect.width * scale).rounded()))
        let pxH = max(1, Int((drawRect.height * scale).rounded()))
        let cs = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)?.colorSpace
            ?? CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            memory.finish("context allocation failed")
            return screenshot
        }
        cgCtx.scaleBy(x: scale, y: scale)
        let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        screenshot.draw(
            in: NSRect(origin: .zero, size: drawRect.size), from: .zero, operation: .copy,
            fraction: 1.0)
        cgCtx.translateBy(x: -drawRect.origin.x, y: -drawRect.origin.y)
        drawAnnotationListLive(annotationsCopy, in: nsContext)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else {
            memory.finish("render failed")
            return screenshot
        }
        let image = NSImage(cgImage: cgImage, size: drawRect.size)
        cachedCompositedImage = image
        memory.finish("rendered", images: [("composited", image)], metadata: "drawRect=\(NSStringFromRect(drawRect)) pixels=\(pxW)x\(pxH)")
        return image
    }

    func captureSelectedRegion() -> NSImage? {
        commitTextFieldIfNeeded()
        return renderSelectedRegion(includeAnnotations: true)
    }

    /// Capture the selected region WITHOUT annotations — just the raw screenshot.
    /// Used for editable history: the raw image is stored alongside annotation data.
    func captureSelectedRegionRaw() -> NSImage? {
        renderSelectedRegion(includeAnnotations: false)
    }

    private func renderSelectedRegion(includeAnnotations: Bool) -> NSImage? {
        guard selectionRect.width > 0, selectionRect.height > 0 else { return nil }
        var memory = MemoryDiagnostics.makeScope(
            "OverlayView.renderSelectedRegion",
            images: [("screenshot", screenshotImage)],
            metadata: "includeAnnotations=\(includeAnnotations) selectionRect=\(NSStringFromRect(selectionRect))"
        )

        let scale: CGFloat
        if let screenshot = screenshotImage,
            let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)
        {
            scale = CGFloat(cg.width) / screenshot.size.width
        } else {
            scale = window?.backingScaleFactor ?? 2.0
        }

        let snappedRect = NSRect(
            x: round(selectionRect.origin.x * scale) / scale,
            y: round(selectionRect.origin.y * scale) / scale,
            width: round(selectionRect.width * scale) / scale,
            height: round(selectionRect.height * scale) / scale
        )

        let pixelW = Int(snappedRect.width * scale)
        let pixelH = Int(snappedRect.height * scale)
        guard pixelW > 0, pixelH > 0 else {
            memory.finish("invalid pixel size")
            return nil
        }

        let cs: CGColorSpace
        if let screenshot = screenshotImage,
            let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let srcCS = cg.colorSpace
        {
            cs = srcCS
        } else {
            cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let cgCtx = CGContext(
                data: nil,
                width: pixelW, height: pixelH,
                bitsPerComponent: 8,
                bytesPerRow: pixelW * 4,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        else {
            memory.finish("context allocation failed", metadata: "pixelSize=\(pixelW)x\(pixelH)")
            return nil
        }

        cgCtx.interpolationQuality = .none
        cgCtx.scaleBy(x: scale, y: scale)
        cgCtx.translateBy(x: -snappedRect.origin.x, y: -snappedRect.origin.y)

        let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        if let screenshot = screenshotImage {
            let drawRect = captureDrawRect
            screenshot.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        }

        if includeAnnotations {
            for annotation in annotations {
                annotation.draw(in: nsContext)
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else {
            memory.finish("makeImage failed", metadata: "pixelSize=\(pixelW)x\(pixelH)")
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: snappedRect.size)
        memory.finish(
            "rendered",
            images: [("output", image)],
            cgImages: [("outputCGImage", cgImage)],
            metadata: "pixelSize=\(pixelW)x\(pixelH)"
        )
        return image
    }
}
