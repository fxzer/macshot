import Cocoa
import CoreImage

enum CensorMode: Int, CaseIterable {
    case pixelate = 0
    case blur = 1
    case solid = 2
    case erase = 3
}

enum AnnotationTool: Int {
    case pixelate = 10
    case blur = 11
}

enum BeautifyRenderer {
    static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
}

final class Annotation {
    let tool: AnnotationTool
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var strokeWidth: CGFloat
    var censorMode: CensorMode = .pixelate
    var sourceImage: NSImage?
    var sourceImageBounds: NSRect = .zero
    var bakedBlurNSImage: NSImage?

    init(tool: AnnotationTool, startPoint: NSPoint, endPoint: NSPoint, color: NSColor, strokeWidth: CGFloat) {
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.strokeWidth = strokeWidth
    }

    var boundingRect: NSRect {
        NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    func move(dx: CGFloat, dy: CGFloat) {
        startPoint.x += dx
        startPoint.y += dy
        endPoint.x += dx
        endPoint.y += dy
        bakedBlurNSImage = nil
    }
}

private func makeTestImage(size: NSSize, scale: CGFloat = 2.0, draw: (CGContext) -> Void) -> NSImage {
    let pxW = Int(size.width * scale)
    let pxH = Int(size.height * scale)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pxW, height: pxH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: scale, y: scale)
    draw(ctx)
    let cg = ctx.makeImage()!
    return NSImage(cgImage: cg, size: size)
}

private func renderToBitmap(size: NSSize, scale: CGFloat = 2.0, draw: (NSGraphicsContext) -> Void) -> NSBitmapImageRep {
    let pxW = Int(size.width * scale)
    let pxH = Int(size.height * scale)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pxW, height: pxH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: scale, y: scale)
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    draw(nsCtx)
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}

@main
struct CensorBakingTests {
    @MainActor
    static func main() {
        // 1. Erase mode over pill background (241, 244, 249) with dark text inside
        let canvasSize = NSSize(width: 200, height: 100)
        let source = makeTestImage(size: canvasSize) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 241/255, green: 244/255, blue: 249/255, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            // Simulate dark email text inside target rect (40, 35, 70, 20)
            ctx.setFillColor(CGColor(srgbRed: 20/255, green: 20/255, blue: 25/255, alpha: 1))
            ctx.fill(CGRect(x: 45, y: 40, width: 60, height: 10))
        }

        let eraseAnn = Annotation(
            tool: .pixelate,
            startPoint: NSPoint(x: 40, y: 35),
            endPoint: NSPoint(x: 110, y: 55),
            color: .clear,
            strokeWidth: 0
        )
        eraseAnn.censorMode = .erase
        eraseAnn.sourceImage = source
        eraseAnn.sourceImageBounds = NSRect(origin: .zero, size: canvasSize)
        eraseAnn.bakePixelate()
        assert(eraseAnn.bakedBlurNSImage != nil, "bakeErase must produce baked image")
        assert(eraseAnn.sourceImage == nil, "bakePixelate releases sourceImage")

        let bmp = renderToBitmap(size: canvasSize) { nsCtx in
            source.draw(in: NSRect(origin: .zero, size: canvasSize), from: .zero, operation: .copy, fraction: 1.0)
            eraseAnn.drawCensor(in: nsCtx)
        }
        var centerPx = [0, 0, 0, 0]
        bmp.getPixel(&centerPx, atX: 150, y: 110) // (75, 45) in 2x
        assert(abs(centerPx[0] - 241) <= 2 && abs(centerPx[1] - 244) <= 2 && abs(centerPx[2] - 249) <= 2,
               "Erased region should match pill background, got \(centerPx)")

        // Verify no dashed blue preview border pixels appear
        var borderPx = [0, 0, 0, 0]
        bmp.getPixel(&borderPx, atX: 80, y: 90)
        assert(borderPx[2] - borderPx[0] < 30, "No blue preview border should appear after baking, got \(borderPx)")

        // 2. Non-zero sourceImageBounds origin (e.g. window-snap overlay origin)
        let offsetAnn = Annotation(
            tool: .pixelate,
            startPoint: NSPoint(x: 540, y: 235),
            endPoint: NSPoint(x: 610, y: 255),
            color: .clear,
            strokeWidth: 0
        )
        offsetAnn.censorMode = .erase
        offsetAnn.sourceImage = source
        offsetAnn.sourceImageBounds = NSRect(x: 500, y: 200, width: 200, height: 100)
        offsetAnn.bakePixelate()
        assert(offsetAnn.bakedBlurNSImage != nil, "bakeErase with non-zero sourceImageBounds must succeed")

        let offsetBmp = renderToBitmap(size: canvasSize) { nsCtx in
            source.draw(in: NSRect(origin: .zero, size: canvasSize), from: .zero, operation: .copy, fraction: 1.0)
            nsCtx.cgContext.translateBy(x: -500, y: -200)
            offsetAnn.drawCensor(in: nsCtx)
        }
        var offsetCenter = [0, 0, 0, 0]
        offsetBmp.getPixel(&offsetCenter, atX: 150, y: 110)
        assert(abs(offsetCenter[0] - 241) <= 2 && abs(offsetCenter[1] - 244) <= 2 && abs(offsetCenter[2] - 249) <= 2,
               "Offset sourceImageBounds erase must match background, got \(offsetCenter)")

        // 3. Edge / fully-transparent region must NOT return nil (no dashed preview leak)
        let transparentSource = makeTestImage(size: canvasSize) { _ in }
        let edgeAnn = Annotation(
            tool: .pixelate,
            startPoint: NSPoint(x: 0, y: 0),
            endPoint: NSPoint(x: 50, y: 20),
            color: .clear,
            strokeWidth: 0
        )
        edgeAnn.censorMode = .erase
        edgeAnn.sourceImage = transparentSource
        edgeAnn.sourceImageBounds = NSRect(origin: .zero, size: canvasSize)
        edgeAnn.bakePixelate()
        assert(edgeAnn.bakedBlurNSImage != nil, "Transparent region erase must not return nil")

        // 4. Thin strip (height = 3.5pt) must both bake and draw
        let thinAnn = Annotation(
            tool: .pixelate,
            startPoint: NSPoint(x: 20, y: 20),
            endPoint: NSPoint(x: 80, y: 23.5),
            color: .red,
            strokeWidth: 0
        )
        thinAnn.censorMode = .solid
        thinAnn.sourceImage = source
        thinAnn.sourceImageBounds = NSRect(origin: .zero, size: canvasSize)
        thinAnn.bakePixelate()
        assert(thinAnn.bakedBlurNSImage != nil, "Thin 3.5pt strip must bake")

        let thinBmp = renderToBitmap(size: canvasSize) { nsCtx in
            thinAnn.drawCensor(in: nsCtx)
        }
        var thinPx = [0, 0, 0, 0]
        thinBmp.getPixel(&thinPx, atX: 100, y: 156) // y = 100 - 22 = 78 -> 156px
        assert(thinPx[0] > 200 && thinPx[3] == 255, "Thin 3.5pt strip must draw baked solid color, got \(thinPx)")

        // 5. All other CensorModes + legacy .blur tool must bake cleanly
        for mode in [CensorMode.pixelate, .blur, .solid, .erase] {
            let ann = Annotation(
                tool: .pixelate,
                startPoint: NSPoint(x: 40, y: 35),
                endPoint: NSPoint(x: 110, y: 55),
                color: .black,
                strokeWidth: 0
            )
            ann.censorMode = mode
            ann.sourceImage = source
            ann.sourceImageBounds = NSRect(origin: .zero, size: canvasSize)
            ann.bakePixelate()
            assert(ann.bakedBlurNSImage != nil, "Mode \(mode) must bake")
        }

        let legacyBlur = Annotation(
            tool: .blur,
            startPoint: NSPoint(x: 40, y: 35),
            endPoint: NSPoint(x: 110, y: 55),
            color: .clear,
            strokeWidth: 0
        )
        legacyBlur.sourceImage = source
        legacyBlur.sourceImageBounds = NSRect(origin: .zero, size: canvasSize)
        legacyBlur.bakePixelate()
        assert(legacyBlur.bakedBlurNSImage != nil, "Legacy .blur tool must bake")

        print("CensorBakingTests: all assertions passed")
    }
}
