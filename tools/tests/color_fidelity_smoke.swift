import Foundation
import CoreGraphics

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func makeSinglePixelImage() -> CGImage {
    CGImage(
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

final class StandardizeCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func currentValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@main
struct ColorFidelitySmokeTest {
    static func main() {
        let sampleScreen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let sampleImage = CGSize(width: 3000, height: 2000)

        expect(
            CaptureImageAsset.needsStandardizedColorImage(bitsPerComponent: 16),
            "16-bit captures should standardize for color sampling")
        expect(
            !CaptureImageAsset.needsStandardizedColorImage(bitsPerComponent: 8),
            "8-bit captures should not require eager standardization")

        let fittedScale = PinWindowSizing.fittedScale(imageSize: sampleImage, visibleFrame: sampleScreen)
        expect(fittedScale < 1.0, "large images should fit inside the visible frame")
        expect(abs(PinWindowSizing.oneToOneScale - 1.0) < 0.0001, "100% mode should use a 1.0 scale")

        let exportSource = CaptureImageExportSource.display
        expect(exportSource == .display, "display export source should exist")

        let standardizeCallCounter = StandardizeCallCounter()
        let fakeAsset = CaptureImageAsset(
            displayCGImage: makeSinglePixelImage(),
            pointSize: CGSize(width: 1, height: 1)
        ) { image in
            standardizeCallCounter.increment()
            return image
        }

        _ = fakeAsset.colorSamplingCGImage()
        _ = fakeAsset.colorSamplingCGImage()
        expect(
            standardizeCallCounter.currentValue() == 1,
            "standardized image should be cached after the first request")

        let fittedSize = PinWindowSizing.windowSize(imageSize: sampleImage, scale: fittedScale)
        expect(fittedSize.width < sampleImage.width, "fitted size should shrink large images")

        let oneToOneSize = PinWindowSizing.windowSize(
            imageSize: sampleImage, scale: PinWindowSizing.oneToOneScale)
        expect(oneToOneSize == sampleImage, "100% size should match the source image exactly")

        expect(
            PinWindowSizing.clampedScale(99) == PinWindowSizing.maxScale,
            "zoom clamping should respect max scale")
        expect(
            PinWindowSizing.clampedScale(0.01) == PinWindowSizing.minScale,
            "zoom clamping should respect min scale")

        expect(
            CaptureImageExportSource.display != .standardizedForColor,
            "display and standardized export sources must remain distinct")

        print("PASS color fidelity smoke tests")
    }
}
