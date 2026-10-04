import Cocoa
import UniformTypeIdentifiers
import ImageIO
import WebP

/// Shared image encoding with user-configurable format, quality, and resolution.
enum ImageEncoder {

    enum Format: String {
        case png = "png"
        case jpeg = "jpeg"
        case heic = "heic"
        case webp = "webp"
    }

    static var format: Format {
        if let raw = UserDefaults.standard.string(forKey: "imageFormat"),
           let fmt = Format(rawValue: raw) {
            return fmt
        }
        return .png
    }

    /// Lossy quality 0.0–1.0 (used for JPEG, HEIC, and WebP)
    static var quality: CGFloat {
        if let q = UserDefaults.standard.object(forKey: "imageQuality") as? Double {
            return CGFloat(max(0.1, min(1.0, q)))
        }
        return 0.85
    }

    /// Whether to downscale Retina (2x) screenshots to standard (1x) resolution.
    static var downscaleRetina: Bool {
        UserDefaults.standard.bool(forKey: "downscaleRetina")
    }

    /// Whether to embed the source image's ICC color profile in saved images.
    static var embedColorProfile: Bool {
        let val = UserDefaults.standard.object(forKey: "embedColorProfile") as? Bool
        return val ?? true  // on by default
    }

    static var fileExtension: String {
        switch format {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .webp: return "webp"
        }
    }

    static var utType: UTType {
        switch format {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .webp: return .webP
        }
    }

    // MARK: - Shared bitmap creation

    /// Per-capture bitmap cache. Keyed by image identity + downscaleRetina flag.
    /// Lets the save path and the clipboard path share one `makeBitmap` result
    /// (avoiding a duplicate Lanczos downscale when confirming a capture that
    /// both saves and copies). NSCache is thread-safe by contract — safe to
    /// hit from `encode()` (caller thread) and `copyToClipboard` (background queue).
    private static let bitmapCache: NSCache<BitmapCacheKey, NSBitmapImageRep> = {
        let cache = NSCache<BitmapCacheKey, NSBitmapImageRep>()
        cache.countLimit = 4  // bound to a handful of recent captures
        // Bound the steady-state footprint: each entry pins both the source
        // NSImage (via the key) and the bitmap copy, i.e. up to 2× the pixel
        // bytes per 4K capture. Without a cost limit the last 4 captures stay
        // resident until system memory pressure forces eviction.
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    /// Key holding a strong reference to the source NSImage (keeps the image
    /// alive so its ObjectIdentifier remains stable) plus the downscale flag.
    /// isEqual/hashValue cover both so two lookups for the same image+flag hit.
    private final class BitmapCacheKey: NSObject {
        let image: NSImage
        let downscale: Bool
        init(image: NSImage, downscale: Bool) {
            self.image = image
            self.downscale = downscale
            super.init()
        }
        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? BitmapCacheKey else { return false }
            return other.image === image && other.downscale == downscale
        }
        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(ObjectIdentifier(image))
            hasher.combine(downscale)
            return hasher.finalize()
        }
    }

    /// Create a bitmap representation from an NSImage, optionally downscaling from Retina.
    /// This is the single conversion point — all encode paths go through here.
    /// Uses cgImage(forProposedRect:) instead of tiffRepresentation to preserve
    /// exact pixel data regardless of the current display's backing scale factor.
    /// Result is cached per (image, downscaleRetina) so the save path and the
    /// clipboard path share the Lanczos downscale instead of running it twice.
    private static func makeBitmap(_ image: NSImage) -> NSBitmapImageRep? {
        let downscale = downscaleRetina
        let cacheKey = BitmapCacheKey(image: image, downscale: downscale)
        if let cached = bitmapCache.object(forKey: cacheKey) {
            return cached
        }

        let bitmap = makeBitmapUncached(image, downscale: downscale)

        if let bitmap {
            // Cost = bitmap copy + pinned source image, both counted so the
            // totalCostLimit bounds the real resident footprint.
            let bitmapBytes = bitmap.bytesPerRow * bitmap.pixelsHigh
            let sourceBytes = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                .map { $0.bytesPerRow * $0.height } ?? bitmapBytes
            bitmapCache.setObject(bitmap, forKey: cacheKey, cost: bitmapBytes + sourceBytes)
        }
        return bitmap
    }

    private static func makeBitmapUncached(_ image: NSImage, downscale: Bool) -> NSBitmapImageRep? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Fallback for images without a CGImage backing (e.g. PDF/EPS vectors)
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
            return bitmap
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        if downscale {
            let logicalW = Int(image.size.width)
            let logicalH = Int(image.size.height)
            let pixelW = bitmap.pixelsWide
            let pixelH = bitmap.pixelsHigh

            if pixelW > logicalW && pixelH > logicalH {
                let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                guard let ctx = CGContext(
                    data: nil,
                    width: logicalW, height: logicalH,
                    bitsPerComponent: 8,
                    bytesPerRow: logicalW * 4,
                    space: cs,
                    bitmapInfo: bitmapInfo
                ) else { return bitmap }
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: logicalW, height: logicalH))
                guard let downscaled = ctx.makeImage() else { return bitmap }
                return NSBitmapImageRep(cgImage: downscaled)
            }
        }

        return bitmap
    }

    // MARK: - Encoding

    /// Effective pixel scale of the FINAL bitmap vs the source image's point size.
    /// Drives DPI metadata: a 2x retina capture written at 72dpi displays at twice
    /// its physical size in DPI-respecting viewers (Preview, chat apps, Finder),
    /// upscaled 2x and visibly soft. 72 × scale (144 for retina) matches the system
    /// screenshot convention — natural size = logical points = 1:1 device-pixel
    /// mapping, pixel-sharp.
    static func effectiveScale(source: NSImage, bitmap: NSBitmapImageRep) -> CGFloat {
        guard source.size.width > 0, bitmap.pixelsWide > 0 else { return 1 }
        let scale = CGFloat(bitmap.pixelsWide) / source.size.width
        return scale >= 1 ? scale : 1
    }

    static func encode(_ asset: CaptureImageAsset, source: CaptureImageExportSource = .display) -> Data? {
        encode(asset.image(for: source))
    }

    /// Encode an NSImage to Data in the configured format.
    static func encode(_ image: NSImage) -> Data? {
        guard let bitmap = makeBitmap(image) else { return nil }
        let scale = effectiveScale(source: image, bitmap: bitmap)

        switch format {
        case .png:
            return encodePNG(bitmap: bitmap, scale: scale)
        case .jpeg:
            return encodeJPEG(bitmap: bitmap, quality: quality, scale: scale)
        case .heic:
            return encodeHEIC(bitmap: bitmap, quality: quality, scale: scale)
        case .webp:
            return encodeWebP(bitmap: bitmap, quality: quality)
        }
    }

    /// Encode PNG, optionally embedding the source color profile via CGImageDestination.
    private static func encodePNG(bitmap: NSBitmapImageRep, scale: CGFloat = 1) -> Data? {
        if embedColorProfile, let cgImage = bitmap.cgImage {
            return encodeWithCGImageDestination(cgImage: cgImage, type: "public.png", lossyQuality: nil, scale: scale)
        }
        // Best-effort DPI in the non-destination path: the rep derives pHYs from
        // its point size vs pixel count.
        bitmap.size = NSSize(width: CGFloat(bitmap.pixelsWide) / scale, height: CGFloat(bitmap.pixelsHigh) / scale)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Encode an NSImage directly to PNG Data, bypassing the configured format.
    /// Used by uploaders that must send PNG regardless of the user's default format.
    /// Avoids the NSImage→TIFF→NSBitmapImageRep round-trip by going through
    /// `cgImage(forProposedRect:)` + CGImageDestination.
    static func encodePNG(_ image: NSImage) -> Data? {
        guard let bitmap = makeBitmap(image) else { return nil }
        return encodePNG(bitmap: bitmap, scale: effectiveScale(source: image, bitmap: bitmap))
    }

    /// Encode a CGImage directly to JPEG Data at the given quality.
    /// Used by uploaders/thumbnailers that have a CGImage already and want
    /// JPEG output without the NSImage→TIFF→NSBitmapImageRep round-trip.
    static func encodeJPEG(_ cgImage: CGImage, quality: CGFloat) -> Data? {
        return encodeWithCGImageDestination(cgImage: cgImage, type: "public.jpeg", lossyQuality: quality)
    }

    /// Encode a CGImage directly to PNG Data via CGImageDestination.
    /// Canonical entry point for callers that already have a CGImage and want PNG
    /// output without the NSImage→TIFF→NSBitmapImageRep round-trip. Replaces the
    /// previously duplicated `CGImageDestinationCreateWithData` blocks in
    /// `AnnotationCodable.encodeImage` and `OverlayWindowController.encodeToPNGData`.
    /// Note: does not apply sRGB profile embedding — call sites want raw pixel
    /// fidelity (annotations/history are internal storage paths).
    static func encodePNG(cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Encode JPEG, optionally embedding the source color profile via CGImageDestination.
    private static func encodeJPEG(bitmap: NSBitmapImageRep, quality: CGFloat, scale: CGFloat = 1) -> Data? {
        if embedColorProfile, let cgImage = bitmap.cgImage {
            return encodeWithCGImageDestination(cgImage: cgImage, type: "public.jpeg", lossyQuality: quality, scale: scale)
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Encode HEIC via CGImageDestination (NSBitmapImageRep doesn't support HEIC).
    private static func encodeHEIC(bitmap: NSBitmapImageRep, quality: CGFloat, scale: CGFloat = 1) -> Data? {
        guard let cgImage = bitmap.cgImage else { return nil }
        return encodeWithCGImageDestination(cgImage: cgImage, type: "public.heic", lossyQuality: quality, scale: scale)
    }

    /// Encode WebP via Swift-WebP (libwebp).
    /// Uses the CGImage RGBA path directly — the library's NSImage path has a bug
    /// (assumes RGB stride and logical size instead of pixel size).
    private static func encodeWebP(bitmap: NSBitmapImageRep, quality: CGFloat) -> Data? {
        guard let srcImage = bitmap.cgImage else { return nil }
        let w = srcImage.width
        let h = srcImage.height
        // Re-render into a known premultipliedLast RGBA context
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(srcImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let rgbaImage = ctx.makeImage() else { return nil }

        let encoder = WebPEncoder()
        let config = WebPEncoderConfig.preset(.picture, quality: Float(quality * 100))
        return try? encoder.encode(RGBA: rgbaImage, config: config)
    }

    /// Generic CGImageDestination encoder — color profile handling.
    /// When embedding is enabled the image's native profile is preserved (e.g.
    /// Display P3 captures keep their gamut, matching macOS system screenshots);
    /// images without a color space are converted to sRGB as a fallback.
    /// Writes DPI metadata (72 × scale) so retina captures display at logical
    /// size like system screenshots instead of being upscaled.
    private static func encodeWithCGImageDestination(cgImage: CGImage, type: String, lossyQuality: CGFloat?, scale: CGFloat = 1) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil) else { return nil }

        var properties: [String: Any] = [:]
        if let q = lossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality as String] = q
        }
        if scale > 1.0 {
            let dpi = 72.0 * scale
            properties[kCGImagePropertyDPIWidth as String] = dpi
            properties[kCGImagePropertyDPIHeight as String] = dpi
        }

        var imageToEncode = cgImage
        if embedColorProfile, cgImage.colorSpace == nil, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) {
            let w = cgImage.width, h = cgImage.height
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w * 4, space: sRGB,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let converted = ctx.makeImage() {
                    imageToEncode = converted
                }
            }
        }

        CGImageDestinationAddImage(dest, imageToEncode, properties as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: - Clipboard

    static func copyToClipboard(_ asset: CaptureImageAsset, source: CaptureImageExportSource = .display) {
        copyToClipboard(asset.image(for: source))
    }

    /// Copy image to pasteboard as PNG.
    /// Explicitly sets PNG data so receiving apps (browsers, editors) get
    /// a lossless PNG instead of the TIFF that NSImage.writeObjects provides.
    /// Deliberately image-data only, no fileURL: sandboxed clipboard managers
    /// (Raycast etc.) classify pasteboard items carrying a file URL as *file*
    /// entries — filename + generic icon, never a thumbnail — while image-data
    /// entries get the "Image (WxH)" preview. Finder pastes raw image data by
    /// creating a file anyway, so the URL is not needed for that either.
    static func copyToClipboard(_ image: NSImage) {
        // Clear pasteboard immediately so Cmd+V doesn't paste stale content
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // PNG encode on background thread (the expensive part), then write to pasteboard on main
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pngData = encodePNG(image) else { return }
            DispatchQueue.main.async {
                pasteboard.declareTypes([.png], owner: nil)
                pasteboard.setData(pngData, forType: .png)
            }
        }
    }
}
