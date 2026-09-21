import AppKit

/// Rasterizes closure-based (drawing-handler) NSImages into real bitmaps.
///
/// Two failure modes this guards against:
/// 1. **Quality**: `NSImage(size:flipped:)` images rasterize at 72dpi (1x) when
///    extracted via `cgImage(forProposedRect:)` — every encode path uses that
///    API, so closure-based images silently halve resolution on retina.
/// 2. **Memory**: a closure image captures whatever it drew — a 36pt thumbnail
///    closure that drew a full-resolution screenshot pins the whole screenshot
///    in memory for as long as the thumbnail lives.
enum ImageRasterizer {

    /// True for drawing-handler images — they carry no representations.
    static func isClosureBased(_ image: NSImage) -> Bool {
        image.representations.isEmpty
    }

    /// Native pixel scale of a CGImage-backed image (pixels ÷ points).
    static func pixelScale(of image: NSImage) -> CGFloat {
        guard image.size.width > 0,
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            cg.width > 0
        else { return 2.0 }
        let scale = CGFloat(cg.width) / image.size.width
        return scale > 0 ? scale : 2.0
    }

    /// Redraw a closure-based image into a CGImage-backed NSImage at `scale`.
    /// CGImage-backed images pass through unchanged.
    @discardableResult
    static func rasterizeIfClosure(_ image: NSImage, scale: CGFloat) -> NSImage {
        guard isClosureBased(image) else { return image }
        return rasterize(image, scale: scale) ?? image
    }

    /// Downscale to fit `maxDimension` (points) and rasterize into a real
    /// bitmap (2x pixels so the result stays sharp on retina displays).
    /// The returned image holds only its own small bitmap — it never pins the
    /// full-resolution source the way a drawing-handler closure would.
    static func downscale(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0, maxDimension > 0 else { return image }
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        guard ratio < 1.0 else { return image }
        let target = NSSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded()))
        guard let rasterized = render(image, pointSize: target, pixelScale: 2.0) else {
            return image
        }
        return rasterized
    }

    // MARK: - Core

    static func rasterize(_ image: NSImage, scale: CGFloat) -> NSImage? {
        render(image, pointSize: image.size, pixelScale: scale)
    }

    private static func render(_ image: NSImage, pointSize: NSSize, pixelScale: CGFloat) -> NSImage? {
        let pxW = max(1, Int((pointSize.width * pixelScale).rounded()))
        let pxH = max(1, Int((pointSize.height * pixelScale).rounded()))
        let cs = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: pixelScale, y: pixelScale)

        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        image.draw(
            in: NSRect(origin: .zero, size: pointSize), from: .zero,
            operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: pointSize)
    }
}
