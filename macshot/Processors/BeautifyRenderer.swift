import Cocoa
import SwiftUI

class BeautifyRenderer {

    /// Shared CIContext — reused across all blur and rendering operations.
    /// CIContext allocation is expensive (GPU/Metal resource setup); avoid creating per-call.
    /// This is the canonical context used by ImageEffects, Annotation+DrawingCensor,
    /// and OverlayView+AnnotationOutlineGlow to avoid redundant GPU resource allocation.
    static let sharedCIContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB(),
        ])
    }()

    /// Apply Gaussian blur to a CGImage and return the blurred result.
    /// Returns nil if the filter fails.
    static func applyGaussianBlur(to cgImage: CGImage, radius: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        return sharedCIContext.createCGImage(output, from: ci.extent)
    }

    // MARK: - Render

    static func render(image: NSImage, config: BeautifyConfig) -> NSImage {
        // Snapped windows always use the dedicated renderer (no synthetic chrome needed)
        if config.isWindowSnap {
            return renderSnappedWindow(image: image, config: config)
        }
        switch config.mode {
        case .window:
            return renderWindow(image: image, config: config)
        case .rounded:
            return renderRounded(image: image, config: config)
        }
    }

    /// Pre-render the mesh gradient for a given size (call before entering NSImage drawing handlers
    /// to avoid calling @MainActor-isolated SwiftUI ImageRenderer from a non-isolated closure).
    static func prerenderBackground(config: BeautifyConfig, width: Int, height: Int) -> CGImage? {
        if config.isCustomBackground { return nil }
        let style = config.style
        if #available(macOS 15.0, *), let mesh = style.meshDef {
            return renderMeshGradient(mesh, width: width, height: height)
        }
        return nil
    }

    /// Draw just the background gradient (or custom image) into a rect (for live overlay preview).
    /// Pass `prerenderedMesh` from `prerenderBackground()` when calling from inside an NSImage drawing handler.
    static func drawGradientBackground(in rect: NSRect, config: BeautifyConfig, context: CGContext, prerenderedMesh: CGImage? = nil) {
        // Custom image background
        if config.isCustomBackground {
            // Use pre-rendered CGImage if available (fast path for live preview)
            if let cached = config.cachedBackgroundCGImage {
                let imgW = CGFloat(cached.width)
                let imgH = CGFloat(cached.height)
                let scaleX = rect.width / imgW
                let scaleY = rect.height / imgH
                let fillScale = max(scaleX, scaleY)
                let drawW = imgW * fillScale
                let drawH = imgH * fillScale
                let drawRect = CGRect(
                    x: rect.minX + (rect.width - drawW) / 2,
                    y: rect.minY + (rect.height - drawH) / 2,
                    width: drawW, height: drawH)
                context.saveGState()
                context.clip(to: rect)
                context.draw(cached, in: drawRect)
                context.restoreGState()
                return
            }
            // Fallback: no cache (e.g. final render), process from NSImage
            if let bgImage = config.customBackgroundImage {
                var imageToDraw = bgImage
                if config.backgroundBlur > 0,
                   let cgImg = bgImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let blurredCG = applyGaussianBlur(to: cgImg, radius: config.backgroundBlur) {
                    imageToDraw = NSImage(cgImage: blurredCG, size: bgImage.size)
                }
                let imgSize = imageToDraw.size
                let scaleX = rect.width / imgSize.width
                let scaleY = rect.height / imgSize.height
                let fillScale = max(scaleX, scaleY)
                let drawW = imgSize.width * fillScale
                let drawH = imgSize.height * fillScale
                let drawRect = NSRect(
                    x: rect.minX + (rect.width - drawW) / 2,
                    y: rect.minY + (rect.height - drawH) / 2,
                    width: drawW, height: drawH)
                context.saveGState()
                context.clip(to: rect)
                imageToDraw.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
                context.restoreGState()
                return
            }
        }

        // Use pre-rendered mesh gradient if provided
        if let meshImage = prerenderedMesh {
            context.draw(meshImage, in: rect)
            return
        }

        let style = config.style

        // Mesh gradient path (macOS 15+) — only reached from callers that don't pre-render (e.g. overlay preview)
        if #available(macOS 15.0, *), let mesh = style.meshDef {
            if let cgImage = renderMeshGradient(mesh, width: Int(rect.width), height: Int(rect.height)) {
                context.draw(cgImage, in: rect)
                return
            }
        }

        // Linear gradient fallback
        let colors = style.stops.map { $0.0.cgColor } as CFArray
        var locations = style.stops.map { $0.1 }
        let cs = CGColorSpaceCreateDeviceRGB()

        guard let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: &locations) else { return }

        // Convert angle (degrees) to start/end points within the rect
        let radians = style.angle * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        let cx = rect.midX
        let cy = rect.midY
        // Project to rect edges
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        let scale = max(abs(dx) > 0.001 ? halfW / abs(dx) : .greatestFiniteMagnitude,
                        abs(dy) > 0.001 ? halfH / abs(dy) : .greatestFiniteMagnitude)
        let len = min(scale, hypot(halfW, halfH))
        let start = CGPoint(x: cx - dx * len, y: cy - dy * len)
        let end = CGPoint(x: cx + dx * len, y: cy + dy * len)

        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Cached mesh gradient renders keyed by "\(colorsHash)_\(width)x\(height)".
    /// Only accessed from @MainActor (renderMeshGradient requires main thread).
    private static var meshCache: [String: CGImage] = [:]
    /// Insertion order for bounded eviction — every entry is a full-size
    /// bitmap, so without a cap the cache grows with each new output size.
    private static var meshCacheOrder: [String] = []
    private static let meshCacheLimit = 4

    /// Clear the mesh gradient cache (call when user changes beautify style or custom background).
    static func clearMeshCache() {
        meshCache.removeAll()
        meshCacheOrder.removeAll()
    }

    /// Render a SwiftUI MeshGradient offscreen into a CGImage (macOS 15+).
    /// Must be called from the main thread (uses SwiftUI ImageRenderer).
    /// Results are cached — repeated calls with the same mesh + size return immediately.
    @available(macOS 15.0, *)
    static func renderMeshGradient(_ mesh: MeshGradientDef, width: Int, height: Int) -> CGImage? {
        let w = max(width, 1)
        let h = max(height, 1)

        // Build cache key from mesh identity (colors hash) + render dimensions
        var hasher = Hasher()
        for c in mesh.colors { hasher.combine(c) }
        let colorsHash = hasher.finalize()
        let cacheKey = "\(colorsHash)_\(w)x\(h)"

        if let cached = meshCache[cacheKey] {
            return cached
        }

        let swiftUIColors = mesh.colors.map { Color(nsColor: $0) }
        let view = MeshGradient(
            width: mesh.width,
            height: mesh.height,
            points: mesh.points,
            colors: swiftUIColors
        )
        .frame(width: CGFloat(w), height: CGFloat(h))

        let result: CGImage? = MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0
            return renderer.cgImage
        }

        if let result = result {
            meshCache[cacheKey] = result
            meshCacheOrder.append(cacheKey)
            while meshCacheOrder.count > meshCacheLimit {
                let oldest = meshCacheOrder.removeFirst()
                meshCache.removeValue(forKey: oldest)
            }
        }
        return result
    }

    /// Render a mesh gradient swatch for the picker (cached-friendly small size)
    @available(macOS 15.0, *)
    static func renderMeshSwatch(_ mesh: MeshGradientDef, size: CGFloat) -> NSImage? {
        guard let cgImage = renderMeshGradient(mesh, width: Int(size * 2), height: Int(size * 2)) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }

    // MARK: - Bitmap rasterization helpers

    /// Snap a point-space length to whole device pixels at the raster scale.
    /// The padding slider stores continuous values (e.g. 24.316pt); using them
    /// raw places the screenshot at a subpixel offset inside the output context,
    /// so CoreGraphics bilinear-resamples the entire capture — a uniform ~1px
    /// smear on every text edge. Snapped, the content draw is pixel-exact.
    static func pixelSnapped(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }

    /// Native pixel scale of an image (backing CGImage width ÷ point width).
    /// Closure-based NSImages rasterize at 72dpi, so this reads 1x for them —
    /// callers wrapping such images should rasterize them first.
    static func pixelScale(of image: NSImage) -> CGFloat {
        guard image.size.width > 0,
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            cg.width > 0
        else { return 2.0 }
        let scale = CGFloat(cg.width) / image.size.width
        return scale > 0 ? scale : 2.0
    }

    /// Rasterize a point-space drawing closure into a CGImage-backed NSImage at
    /// the source capture's native pixel scale.
    /// Closure-based NSImages (`NSImage(size:flipped:)`) rasterize at 72dpi (1x)
    /// when extracted via `cgImage(forProposedRect:)` — every encoding path
    /// (clipboard PNG, file save, upload, history) extracts that way, which
    /// silently halved beautified output resolution on retina displays.
    static func renderIntoBitmap(
        pointSize: NSSize,
        sourceScale: CGFloat,
        config: BeautifyConfig,
        draw: (_ prerenderedMesh: CGImage?) -> Bool
    ) -> NSImage? {
        let scale = max(1.0, sourceScale)
        let pxW = max(1, Int((pointSize.width * scale).rounded()))
        let pxH = max(1, Int((pointSize.height * scale).rounded()))

        // Mesh prerender runs at pixel dims so the background isn't upscaled.
        let prerenderedMesh = prerenderBackground(config: config, width: pxW, height: pxH)
        return rasterize(pointSize: pointSize, sourceScale: sourceScale) {
            draw(prerenderedMesh)
        }
    }

    /// Core rasterizer without beautify-specific preparation.
    static func rasterize(pointSize: NSSize, sourceScale: CGFloat, draw: () -> Bool) -> NSImage? {
        let scale = max(1.0, sourceScale)
        let pxW = max(1, Int((pointSize.width * scale).rounded()))
        let pxH = max(1, Int((pointSize.height * scale).rounded()))

        let cs = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)

        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let success = draw()
        NSGraphicsContext.restoreGraphicsState()

        guard success, let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: pointSize)
    }

    // MARK: - Window mode (macOS title bar chrome)

    private static func renderWindow(image: NSImage, config: BeautifyConfig) -> NSImage {
        let imgSize = image.size
        let scale = pixelScale(of: image)
        let padding = pixelSnapped(config.padding, scale: scale)
        let windowCornerRadius = config.cornerRadius
        let shadowRadius = config.shadowRadius
        let shadowOffset = min(shadowRadius * 0.3, 8)
        let titleBarHeight: CGFloat = 28

        let windowWidth = imgSize.width
        let windowHeight = imgSize.height + titleBarHeight

        let totalWidth = windowWidth + padding * 2
        let totalHeight = windowHeight + padding * 2

        let result = renderIntoBitmap(
            pointSize: NSSize(width: totalWidth, height: totalHeight),
            sourceScale: scale,
            config: config
        ) { prerenderedMesh in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            // Gradient background — fill entire canvas, no outer rounding
            let bgRect = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
            context.saveGState()
            drawGradientBackground(in: bgRect, config: config, context: context, prerenderedMesh: prerenderedMesh)
            context.restoreGState()

            // Window frame position
            let windowX = padding
            let windowY = padding

            // Drop shadow
            if shadowRadius > 0 {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = shadowRadius
                shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
                NSBezierPath(roundedRect: windowRect, xRadius: windowCornerRadius, yRadius: windowCornerRadius).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            // Draw window background clipped
            let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
            context.saveGState()
            let clipPath = NSBezierPath(roundedRect: windowRect, xRadius: windowCornerRadius, yRadius: windowCornerRadius)
            clipPath.addClip()

            NSColor(white: 0.97, alpha: 1.0).setFill()
            NSBezierPath(rect: windowRect).fill()

            // Title bar
            let titleBarRect = NSRect(x: windowX, y: windowY + windowHeight - titleBarHeight, width: windowWidth, height: titleBarHeight)
            NSColor(white: 0.94, alpha: 1.0).setFill()
            NSBezierPath(rect: titleBarRect).fill()

            // Separator
            NSColor(white: 0.82, alpha: 1.0).setFill()
            NSBezierPath(rect: NSRect(x: windowX, y: titleBarRect.minY - 0.5, width: windowWidth, height: 0.5)).fill()

            // Traffic lights
            let buttonY = titleBarRect.midY
            let buttonRadius: CGFloat = 6
            let buttonStartX = windowX + 14
            let buttonSpacing: CGFloat = 20

            let trafficLights: [(NSColor, NSColor)] = [
                (NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.35, alpha: 1.0),
                 NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.22, alpha: 1.0)),
                (NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.25, alpha: 1.0),
                 NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.15, alpha: 1.0)),
                (NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.35, alpha: 1.0),
                 NSColor(calibratedRed: 0.20, green: 0.65, blue: 0.25, alpha: 1.0)),
            ]

            for (i, (fill, ring)) in trafficLights.enumerated() {
                let cx = buttonStartX + CGFloat(i) * buttonSpacing
                let circleRect = NSRect(x: cx - buttonRadius, y: buttonY - buttonRadius, width: buttonRadius * 2, height: buttonRadius * 2)
                fill.setFill()
                NSBezierPath(ovalIn: circleRect).fill()
                ring.setStroke()
                let border = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.5, dy: 0.5))
                border.lineWidth = 0.5
                border.stroke()
            }

            // Screenshot image
            let contentRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight - titleBarHeight)
            image.draw(in: contentRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            context.restoreGState()

            return true
        }
        return result ?? image
    }

    // MARK: - Snapped window mode (native window chrome, no synthetic title bar)

    /// Renders a snapped window: the image already contains the native window chrome
    /// (title bar, traffic lights, rounded corners). We just place it on the gradient
    /// background with a drop shadow — no synthetic elements needed.
    private static func renderSnappedWindow(image: NSImage, config: BeautifyConfig) -> NSImage {
        let imgSize = image.size
        let scale = pixelScale(of: image)
        let padding = pixelSnapped(config.padding, scale: scale)
        let shadowRadius = config.shadowRadius
        let shadowOffset = min(shadowRadius * 0.3, 8)
        // macOS window corner radius is 10pt (not used in rendering, informational)

        let totalWidth = imgSize.width + padding * 2
        let totalHeight = imgSize.height + padding * 2

        let result = renderIntoBitmap(
            pointSize: NSSize(width: totalWidth, height: totalHeight),
            sourceScale: scale,
            config: config
        ) { prerenderedMesh in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            // Gradient background
            let bgRect = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
            context.saveGState()
            drawGradientBackground(in: bgRect, config: config, context: context, prerenderedMesh: prerenderedMesh)
            context.restoreGState()

            let imageRect = NSRect(x: padding, y: padding, width: imgSize.width, height: imgSize.height)

            // Draw the window image with shadow on top of the gradient.
            // The image has transparent corners, so the gradient shows through naturally.
            if shadowRadius > 0 {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = shadowRadius
                shadow.shadowOffset = NSSize(width: 0, height: -shadowOffset)
                shadow.set()
            }
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            return true
        }
        return result ?? image
    }

    // MARK: - Rounded mode (just rounded corners, no title bar)

    private static func renderRounded(image: NSImage, config: BeautifyConfig) -> NSImage {
        let imgSize = image.size
        let scale = pixelScale(of: image)
        let padding = pixelSnapped(config.padding, scale: scale)
        let cornerRadius = config.cornerRadius
        let shadowRadius = config.shadowRadius
        let shadowOffset = min(shadowRadius * 0.3, 8)

        let totalWidth = imgSize.width + padding * 2
        let totalHeight = imgSize.height + padding * 2

        let result = renderIntoBitmap(
            pointSize: NSSize(width: totalWidth, height: totalHeight),
            sourceScale: scale,
            config: config
        ) { prerenderedMesh in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            // Gradient background — fill entire canvas, no outer rounding
            let bgRect = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
            context.saveGState()
            drawGradientBackground(in: bgRect, config: config, context: context, prerenderedMesh: prerenderedMesh)
            context.restoreGState()

            let imageRect = NSRect(x: padding, y: padding, width: imgSize.width, height: imgSize.height)

            // Draw image with rounded corners + shadow in one pass
            context.saveGState()
            if shadowRadius > 0 {
                context.setShadow(offset: CGSize(width: 0, height: -shadowOffset),
                                  blur: shadowRadius,
                                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
            }
            // Begin a transparency layer so the shadow is cast by the clipped image shape
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.endTransparencyLayer()
            context.restoreGState()

            return true
        }
        return result ?? image
    }
}
