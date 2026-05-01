import AppKit
import CoreGraphics

/// Holds the user-visible capture image plus a lazily created standardized image
/// for stable color sampling / numeric color output.
final class CaptureImageAsset {
    let displayCGImage: CGImage
    let displayImage: NSImage

    private let pointSize: NSSize
    private let standardizer: @Sendable (CGImage) -> CGImage?
    private let lock = NSLock()
    private var cachedColorSamplingCGImage: CGImage?

    init(
        displayCGImage: CGImage,
        pointSize: NSSize,
        standardizer: @escaping @Sendable (CGImage) -> CGImage?
    ) {
        self.displayCGImage = displayCGImage
        self.displayImage = NSImage(cgImage: displayCGImage, size: pointSize)
        self.pointSize = pointSize
        self.standardizer = standardizer
        CaptureDiagnostics.log(
            "[macshot-perf][CaptureImageAsset] init cgImage=\(displayCGImage.width)x\(displayCGImage.height) bpp=\(displayCGImage.bitsPerComponent)"
        )
    }

    deinit {
        CaptureDiagnostics.log(
            "[macshot-life][CaptureImageAsset] deinit cgImage=\(displayCGImage.width)x\(displayCGImage.height) cachedColorSampling=\(hasCachedColorSamplingImage) mem=\(MemoryDiagnostics.currentSummary())"
        )
    }

    convenience init?(
        displayImage: NSImage,
        standardizer: @escaping @Sendable (CGImage) -> CGImage?
    ) {
        guard let cgImage = Self.makeCGImage(from: displayImage) else { return nil }
        self.init(
            displayCGImage: cgImage,
            pointSize: displayImage.size,
            standardizer: standardizer
        )
    }

    static func needsStandardizedColorImage(bitsPerComponent: Int) -> Bool {
        bitsPerComponent > 8
    }

    var displaySize: NSSize { pointSize }

    func image(for source: CaptureImageExportSource) -> NSImage {
        switch source {
        case .display:
            return displayImage
        case .standardizedForColor:
            return NSImage(cgImage: colorSamplingCGImage(), size: pointSize)
        }
    }

    func colorSamplingCGImage() -> CGImage {
        lock.lock()
        defer { lock.unlock() }

        if let cachedColorSamplingCGImage {
            return cachedColorSamplingCGImage
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        let resolved = standardizer(displayCGImage) ?? displayCGImage
        CaptureDiagnostics.log(
            "[macshot-perf][CaptureImageAsset] standardizer elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms"
        )
        cachedColorSamplingCGImage = resolved
        return resolved
    }

    func preloadColorSamplingImage(completion: @escaping (CGImage) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.colorSamplingCGImage()
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    func releaseColorSamplingImage() {
        lock.lock()
        let hadCachedColorSampling = cachedColorSamplingCGImage != nil
        cachedColorSamplingCGImage = nil
        lock.unlock()
        if hadCachedColorSampling {
            MemoryDiagnostics.snapshot(
                "CaptureImageAsset.releaseColorSamplingImage",
                cgImages: [("displayCGImage", displayCGImage)],
                metadata: "released standardized color image"
            )
        }
    }

    var hasCachedColorSamplingImage: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedColorSamplingCGImage != nil
    }

    private static func makeCGImage(from image: NSImage) -> CGImage? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage
        }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.cgImage
    }
}
