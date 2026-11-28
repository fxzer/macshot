//
//  OverlayView+OutputRendering.swift
//  macshot
//
//  Output rendering helpers for OverlayView.
//

import AppKit

extension OverlayView {

    // MARK: - Output

    /// Ensure all committed censor/loupe annotations (not in `excluded`) have baked images.
    /// Prevents leaking raw underlying content with the dashed live-preview border on export or redraw.
    func ensureCensorAndLoupeAnnotationsBaked(excluding excluded: Set<ObjectIdentifier> = []) {
        guard let screenshot = screenshotImage else { return }
        let drawBounds = captureDrawRect

        // 1. Bake any unbaked loupes first (loupes sample the raw screenshot).
        for ann in annotations where ann.tool == .loupe && ann.bakedBlurNSImage == nil {
            guard !excluded.contains(ObjectIdentifier(ann)) else { continue }
            if ann.sourceImage == nil {
                ann.sourceImage = screenshot
                ann.sourceImageBounds = drawBounds
            }
            ann.bakeLoupe()
        }

        // 2. Collect unbaked censor annotations that need baking.
        let unbakedCensors = annotations.filter { ann in
            guard (ann.tool == .pixelate || ann.tool == .blur),
                  ann.bakedBlurNSImage == nil,
                  !excluded.contains(ObjectIdentifier(ann))
            else { return false }
            let r = ann.boundingRect
            return r.width > 2 && r.height > 2
        }
        guard !unbakedCensors.isEmpty else { return }

        var sharedCompositedSource: NSImage?
        let needsComposited = unbakedCensors.contains { $0.sourceImage == nil && $0.censorMode != .solid }
        if needsComposited {
            let censorExcluded = excluded.union(unbakedCensors.map { ObjectIdentifier($0) })
            let backgroundList = annotations.filter { !censorExcluded.contains(ObjectIdentifier($0)) }
            sharedCompositedSource = backgroundList.isEmpty ? screenshot : (renderCompositedImage(annotations: backgroundList) ?? screenshot)
        }

        for ann in unbakedCensors {
            if ann.sourceImage == nil {
                ann.sourceImage = (ann.censorMode == .solid) ? screenshot : (sharedCompositedSource ?? screenshot)
                ann.sourceImageBounds = drawBounds
            }
            ann.bakePixelate()
        }
    }

    func compositedImage() -> NSImage? {
        compositedImage(excluding: [])
    }

    /// Render screenshot + existing annotations into a full-size image.
    /// Used as source for pixelate/blur so they operate on the composited result.
    /// Rasterized at the screenshot's native pixel scale — censor tools extract
    /// pixels via cgImage(forProposedRect:), which rasterizes closure-based
    /// images at 72dpi (half resolution on retina).
    func compositedImage(excluding excluded: Set<ObjectIdentifier>) -> NSImage? {
        if excluded.isEmpty, let cached = cachedCompositedImage { return cached }
        guard let screenshot = screenshotImage else { return nil }
        ensureCensorAndLoupeAnnotationsBaked(excluding: excluded)
        let filtered = excluded.isEmpty
            ? annotations
            : annotations.filter { !excluded.contains(ObjectIdentifier($0)) }
        if filtered.isEmpty { return screenshot }
        guard let image = renderCompositedImage(annotations: filtered) else { return screenshot }
        if excluded.isEmpty {
            cachedCompositedImage = image
        }
        return image
    }

    private func renderCompositedImage(annotations annotationsCopy: [Annotation]) -> NSImage? {
        guard let screenshot = screenshotImage else { return nil }
        var memory = MemoryDiagnostics.makeScope(
            "OverlayView.compositedImage",
            images: [("screenshot", screenshot)],
            metadata: "annotations=\(annotationsCopy.count)"
        )

        let drawRect = captureDrawRect
        let scale = ImageRasterizer.pixelScale(of: screenshot)
        let pxW = max(1, Int((drawRect.width * scale).rounded()))
        let pxH = max(1, Int((drawRect.height * scale).rounded()))
        let cs = ImageRasterizer.safeRGBOutputColorSpace(
            for: screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)?.colorSpace
        )
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            memory.finish("context allocation failed")
            return nil
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
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: drawRect.size)
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

        let pixelW = max(1, Int((snappedRect.width * scale).rounded()))
        let pixelH = max(1, Int((snappedRect.height * scale).rounded()))
        guard pixelW > 0, pixelH > 0 else {
            memory.finish("invalid pixel size")
            return nil
        }

        let cs = ImageRasterizer.safeRGBOutputColorSpace(
            for: screenshotImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.colorSpace
        )
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

        // Restore high-quality interpolation for vector annotations, text, arrows, and smoothed paths
        cgCtx.interpolationQuality = .high

        if includeAnnotations {
            ensureCensorAndLoupeAnnotationsBaked()
            drawAnnotationListLive(annotations, in: nsContext)
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
