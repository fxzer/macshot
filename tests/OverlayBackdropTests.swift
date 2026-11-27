import Cocoa

final class OverlayView: NSView {
    enum State { case idle, selected }
    var isEditorMode = false
    var isScrollCapturing = false
    var suppressBackdropUntilCapture = false
    var screenshotImage: NSImage?
    var displayCGImage: CGImage?
    var state = State.selected
    var selectionRect = NSRect.zero
    var remoteSelectionRect = NSRect.zero
    var zoomLevel: CGFloat = 1
    var zoomAnchorCanvas = NSPoint.zero
    var zoomAnchorView = NSPoint.zero
    func drawEditorBackground(context: NSGraphicsContext) {}
    func paint(in context: NSGraphicsContext) { drawOverlayBackdrop(in: context) }
}

@main
struct OverlayBackdropTests {
    @MainActor
    static func main() {
        for colorSpace in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            for scale in [1, 2] {
                let space = CGColorSpace(name: colorSpace)!
                let source = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                       bytesPerRow: 16, space: space,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                for (index, rgb) in [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0],
                                     [0.0, 0.0, 1.0], [0.2, 0.4, 0.6]].enumerated() {
                    source.setFillColor(CGColor(colorSpace: space, components: (rgb + [1]).map { CGFloat($0) })!)
                    source.fill(CGRect(x: (index % 2) * 2, y: (index / 2) * 2, width: 2, height: 2))
                }
                let image = source.makeImage()!
                let view = OverlayView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
                view.selectionRect = view.bounds
                view.displayCGImage = image
                view.screenshotImage = NSImage(cgImage: image, size: view.bounds.size)
                var results: [[UInt8]] = []
                for direct in [false, true] {
                    let pixels = 4 * scale
                    let target = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                           bytesPerRow: pixels * 4, space: space,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    target.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                    target.interpolationQuality = .none
                    let context = NSGraphicsContext(cgContext: target, flipped: false)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    if direct {
                        view.paint(in: context)
                    } else {
                        view.screenshotImage!.draw(in: view.bounds, from: .zero, operation: .copy, fraction: 1)
                    }
                    results.append(Array(UnsafeBufferPointer(
                        start: target.data!.assumingMemoryBound(to: UInt8.self), count: pixels * pixels * 4
                    )))
                    NSGraphicsContext.restoreGraphicsState()
                }
                precondition(results[0] == results[1], "背景颜色、方向或 Retina 比例发生变化")
            }
        }
        print("PASS: sRGB、Display P3 在 1x 和 2x 下与原绘制结果逐字节一致")
    }
}
