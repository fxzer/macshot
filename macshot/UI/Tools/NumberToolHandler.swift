import Cocoa
import CoreText

enum NumberCalloutGeometry {
    static let minSize: CGFloat = 1
    static let maxSize: CGFloat = 30
    static let bubbleBaseRadius: CGFloat = 8
    static let bubbleScale: CGFloat = 3

    static func bubbleRadius(for size: CGFloat) -> CGFloat {
        bubbleBaseRadius + size * bubbleScale
    }

    static func clampSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minSize), maxSize)
    }
}

enum NumberCalloutTextLayout {
    private static let textPadding: CGFloat = 2

    struct RenderedText {
        let cgImage: CGImage
        let size: CGSize
    }

    struct Metrics {
        let line: CTLine
        let opticalBounds: CGRect
        let size: CGSize
        let attributes: [NSAttributedString.Key: Any]
    }

    static func textColor(for fillColor: NSColor) -> NSColor {
        guard let rgb = fillColor.usingColorSpace(.sRGB) else { return .white }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black : .white
    }

    static func metrics(for text: String, font: NSFont, fillColor: NSColor) -> Metrics {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor(for: fillColor)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let opticalBounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        let size = CGSize(
            width: ceil(opticalBounds.width + textPadding * 2),
            height: ceil(opticalBounds.height + textPadding * 2)
        )
        return Metrics(
            line: line,
            opticalBounds: opticalBounds,
            size: size,
            attributes: attributes
        )
    }

    static func centeredOrigin(for metrics: Metrics, in rect: CGRect) -> CGPoint {
        let optical = metrics.opticalBounds
        return CGPoint(
            x: floor(rect.midX - optical.midX),
            y: floor(rect.midY - optical.midY)
        )
    }

    static func renderedText(
        for text: String,
        font: NSFont,
        fillColor: NSColor,
        backingScale: CGFloat
    ) -> RenderedText? {
        let metrics = metrics(for: text, font: font, fillColor: fillColor)
        let textSize = metrics.size
        guard textSize.width > 0, textSize.height > 0 else { return nil }

        let pixelWidth = max(1, Int(ceil(textSize.width * backingScale)))
        let pixelHeight = max(1, Int(ceil(textSize.height * backingScale)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: textSize.width, height: textSize.height)
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let drawRect = CGRect(origin: .zero, size: textSize)
        draw(text: text, metrics: metrics, in: drawRect, cgContext: context.cgContext)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = rep.cgImage else { return nil }
        return RenderedText(cgImage: cgImage, size: textSize)
    }

    static func draw(
        text: String,
        font: NSFont,
        fillColor: NSColor,
        in rect: CGRect,
        cgContext: CGContext
    ) {
        let metrics = metrics(for: text, font: font, fillColor: fillColor)
        draw(text: text, metrics: metrics, in: rect, cgContext: cgContext)
    }

    private static func draw(
        text: String,
        metrics: Metrics,
        in rect: CGRect,
        cgContext: CGContext
    ) {
        guard !text.isEmpty else { return }
        cgContext.saveGState()
        cgContext.textMatrix = .identity
        cgContext.setAllowsFontSmoothing(true)
        cgContext.setShouldSmoothFonts(true)
        let origin = centeredOrigin(for: metrics, in: rect)
        cgContext.textPosition = origin
        CTLineDraw(metrics.line, cgContext)
        cgContext.restoreGState()
    }
}

final class NumberedCalloutPreviewController {
    private weak var hostView: NSView?
    private let rootLayer = CALayer()
    private let sourceDotLayer = CAShapeLayer()
    private let funnelLayer = CAShapeLayer()
    private let bubbleShadowLayer = CALayer()
    private let bubbleFillLayer = CAShapeLayer()
    private let bubbleBorderLayer = CAShapeLayer()
    private let textLayer = CALayer()
    private var textLayerSize: CGSize = .zero

    private(set) var sourcePoint: CGPoint?
    private(set) var destinationPoint: CGPoint?
    private(set) var bubbleDiameter: CGFloat = 0

    init(hostView: NSView) {
        self.hostView = hostView
        configureLayers()
    }

    func begin(at sourcePoint: CGPoint, diameter: CGFloat, numberText: String, color: NSColor, backingScale: CGFloat) {
        self.sourcePoint = sourcePoint
        destinationPoint = nil
        bubbleDiameter = diameter
        attachIfNeeded(backingScale: backingScale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.frame = hostView?.bounds ?? .zero
        sourceDotLayer.fillColor = color.cgColor
        sourceDotLayer.path = CGPath(
            ellipseIn: CGRect(
                x: sourcePoint.x - MagnifiedCalloutGeometry.sourceDotRadius,
                y: sourcePoint.y - MagnifiedCalloutGeometry.sourceDotRadius,
                width: MagnifiedCalloutGeometry.sourceDotRadius * 2,
                height: MagnifiedCalloutGeometry.sourceDotRadius * 2
            ),
            transform: nil
        )
        updateText(numberText, fillColor: color, backingScale: backingScale)
        sourceDotLayer.isHidden = false
        funnelLayer.isHidden = true
        bubbleShadowLayer.isHidden = true
        CATransaction.commit()
    }

    func update(destination proposedDestination: CGPoint, constrainedTo drawingBounds: CGRect, color: NSColor, backingScale: CGFloat) {
        guard let sourcePoint else { return }
        attachIfNeeded(backingScale: backingScale)

        let radius = bubbleDiameter / 2
        let destination = MagnifiedCalloutGeometry.clampBubbleCenter(
            proposedDestination,
            radius: radius,
            within: drawingBounds
        )
        destinationPoint = destination

        let bubbleRect = MagnifiedCalloutGeometry.bubbleRect(center: destination, diameter: bubbleDiameter)
        let funnelPath = MagnifiedCalloutGeometry.funnelPath(
            sourceCenter: sourcePoint,
            sourceRadius: MagnifiedCalloutGeometry.sourceDotRadius,
            destinationCenter: destination,
            destinationRadius: radius
        )
        let showsDetachedCallout = MagnifiedCalloutGeometry.shouldRenderDetachedCallout(
            sourceCenter: sourcePoint,
            sourceRadius: MagnifiedCalloutGeometry.sourceDotRadius,
            destinationCenter: destination,
            destinationRadius: radius
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.frame = hostView?.bounds ?? .zero
        funnelLayer.fillColor = color.withAlphaComponent(0.22).cgColor
        funnelLayer.path = funnelPath
        funnelLayer.isHidden = funnelPath == nil
        sourceDotLayer.isHidden = !showsDetachedCallout

        bubbleShadowLayer.frame = bubbleRect
        bubbleShadowLayer.cornerRadius = radius
        bubbleShadowLayer.shadowPath = CGPath(ellipseIn: bubbleShadowLayer.bounds, transform: nil)
        bubbleShadowLayer.isHidden = false

        bubbleFillLayer.frame = bubbleShadowLayer.bounds
        bubbleFillLayer.path = CGPath(ellipseIn: bubbleFillLayer.bounds, transform: nil)
        bubbleFillLayer.fillColor = color.cgColor

        bubbleBorderLayer.frame = bubbleShadowLayer.bounds
        bubbleBorderLayer.path = CGPath(ellipseIn: bubbleBorderLayer.bounds.insetBy(dx: 2, dy: 2), transform: nil)

        textLayer.contentsScale = backingScale
        textLayer.frame = CGRect(
            x: floor((bubbleShadowLayer.bounds.width - textLayerSize.width) / 2),
            y: floor((bubbleShadowLayer.bounds.height - textLayerSize.height) / 2),
            width: textLayerSize.width,
            height: textLayerSize.height
        )
        CATransaction.commit()
    }

    func finish() -> LoupeCalloutPreviewSnapshot? {
        defer { hide() }
        guard let sourcePoint else { return nil }
        let resolvedDestination: CGPoint
        if let destinationPoint,
            hypot(destinationPoint.x - sourcePoint.x, destinationPoint.y - sourcePoint.y)
                >= MagnifiedCalloutGeometry.minimumCommitDistance
        {
            resolvedDestination = destinationPoint
        } else {
            resolvedDestination = sourcePoint
        }

        return LoupeCalloutPreviewSnapshot(
            sourcePoint: sourcePoint,
            destinationPoint: resolvedDestination,
            bubbleDiameter: bubbleDiameter
        )
    }

    func hide() {
        sourcePoint = nil
        destinationPoint = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sourceDotLayer.isHidden = true
        funnelLayer.isHidden = true
        bubbleShadowLayer.isHidden = true
        CATransaction.commit()
    }

    private func configureLayers() {
        rootLayer.name = "numbered-callout-preview"
        rootLayer.zPosition = 901
        rootLayer.masksToBounds = false

        bubbleShadowLayer.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        bubbleShadowLayer.shadowOpacity = 1
        bubbleShadowLayer.shadowRadius = 12
        bubbleShadowLayer.shadowOffset = CGSize(width: 0, height: -4)

        bubbleBorderLayer.fillColor = NSColor.clear.cgColor
        bubbleBorderLayer.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        bubbleBorderLayer.lineWidth = 2.5

        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.contentsGravity = .center

        bubbleShadowLayer.addSublayer(bubbleFillLayer)
        bubbleShadowLayer.addSublayer(bubbleBorderLayer)
        bubbleShadowLayer.addSublayer(textLayer)
        rootLayer.addSublayer(funnelLayer)
        rootLayer.addSublayer(sourceDotLayer)
        rootLayer.addSublayer(bubbleShadowLayer)

        sourceDotLayer.isHidden = true
        funnelLayer.isHidden = true
        bubbleShadowLayer.isHidden = true
    }

    private func attachIfNeeded(backingScale: CGFloat) {
        guard let hostView else { return }
        if !hostView.wantsLayer {
            hostView.wantsLayer = true
        }
        rootLayer.frame = hostView.bounds
        rootLayer.contentsScale = backingScale
        if rootLayer.superlayer == nil {
            hostView.layer?.addSublayer(rootLayer)
        }
    }

    private func updateText(_ numberText: String, fillColor: NSColor, backingScale: CGFloat) {
        let fontSize = max(16, bubbleDiameter * 0.42)
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        textLayer.contentsScale = backingScale
        if let rendered = NumberCalloutTextLayout.renderedText(
            for: numberText,
            font: font,
            fillColor: fillColor,
            backingScale: backingScale
        ) {
            textLayer.contents = rendered.cgImage
            textLayerSize = rendered.size
        } else {
            textLayer.contents = nil
            textLayerSize = .zero
        }
    }
}

/// Handles number (auto-incrementing circle) tool interaction.
/// Target-first numbered bubble callout: mouseDown records the target, drag places the bubble.
final class NumberToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .number
    var requiresDisplayRefreshDuringDrag: Bool { false }

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        canvas.numberCounter += 1
        let annotation = Annotation(
            tool: .number,
            startPoint: point,
            endPoint: point,
            color: canvas.opacityAppliedColor(for: .number),
            strokeWidth: canvas.currentNumberSize
        )
        annotation.number = canvas.numberCounter + (canvas.numberStartAt - 1)
        annotation.numberFormat = canvas.currentNumberFormat
        applyDefaultOutlineIfNeeded(to: annotation, canvas: canvas)
        let bubbleRadius = NumberCalloutGeometry.bubbleRadius(for: annotation.strokeWidth)
        let bubbleDiameter = bubbleRadius * 2
        canvas.beginNumberedCalloutPreview(
            sourcePoint: point,
            bubbleDiameter: bubbleDiameter,
            numberText: annotation.numberFormat.format(annotation.number ?? 0),
            color: annotation.color
        )
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        var clampedPoint = point

        if shiftHeld {
            canvas.snapGuideX = nil
            canvas.snapGuideY = nil
        } else {
            clampedPoint = canvas.snapPoint(point, excluding: canvas.activeAnnotation)
        }

        canvas.updateNumberedCalloutPreview(destinationPoint: clampedPoint)
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else { return }
        guard let preview = canvas.finishNumberedCalloutPreview() else { return }

        annotation.startPoint = preview.destinationPoint
        annotation.endPoint = preview.sourcePoint
        commitAnnotation(annotation, canvas: canvas)
    }
}
