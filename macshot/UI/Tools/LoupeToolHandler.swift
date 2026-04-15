import Cocoa

struct MagnifiedCalloutGeometry {
    static let sourceDotRadius: CGFloat = 2.0
    static let magnification: CGFloat = 2.0
    static let minimumCommitDistance: CGFloat = 6.0

    static func connectorFillColor(for accentColor: NSColor) -> NSColor {
        accentColor.withAlphaComponent(0.22)
    }

    static func sourceDotColor(for accentColor: NSColor) -> NSColor {
        accentColor
    }

    static func bubbleRect(center: CGPoint, diameter: CGFloat) -> CGRect {
        CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    static func clampBubbleCenter(_ center: CGPoint, radius: CGFloat, within bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(center.x, bounds.minX + radius), bounds.maxX - radius),
            y: min(max(center.y, bounds.minY + radius), bounds.maxY - radius)
        )
    }

    static func shouldRenderDetachedCallout(
        sourceCenter: CGPoint,
        sourceRadius: CGFloat,
        destinationCenter: CGPoint,
        destinationRadius: CGFloat,
        minimumGap: CGFloat = 1.0
    ) -> Bool {
        let dx = destinationCenter.x - sourceCenter.x
        let dy = destinationCenter.y - sourceCenter.y
        let distance = hypot(dx, dy)
        return distance > max(0.001, sourceRadius + destinationRadius + minimumGap)
    }

    /// 通过两圆圆心连线的法线方向，求出漏斗连接区的四个切点。
    /// `atan2` 给出主连线角度；法线方向为 `angle + π/2`。
    static func funnelPath(
        sourceCenter: CGPoint,
        sourceRadius: CGFloat,
        destinationCenter: CGPoint,
        destinationRadius: CGFloat
    ) -> CGPath? {
        // 当源点已经落在目标圆内部或边缘附近时，梯形会自相交，
        // 最终填充后看起来像多出一块杂色图形。此时应直接不画漏斗。
        guard shouldRenderDetachedCallout(
            sourceCenter: sourceCenter,
            sourceRadius: sourceRadius,
            destinationCenter: destinationCenter,
            destinationRadius: destinationRadius
        ) else { return nil }

        let dx = destinationCenter.x - sourceCenter.x
        let dy = destinationCenter.y - sourceCenter.y

        let angle = atan2(dy, dx)
        let perpendicular = CGPoint(x: -sin(angle), y: cos(angle))

        let sourceLeft = CGPoint(
            x: sourceCenter.x + perpendicular.x * sourceRadius,
            y: sourceCenter.y + perpendicular.y * sourceRadius
        )
        let sourceRight = CGPoint(
            x: sourceCenter.x - perpendicular.x * sourceRadius,
            y: sourceCenter.y - perpendicular.y * sourceRadius
        )
        let destinationLeft = CGPoint(
            x: destinationCenter.x + perpendicular.x * destinationRadius,
            y: destinationCenter.y + perpendicular.y * destinationRadius
        )
        let destinationRight = CGPoint(
            x: destinationCenter.x - perpendicular.x * destinationRadius,
            y: destinationCenter.y - perpendicular.y * destinationRadius
        )

        let path = CGMutablePath()
        path.move(to: sourceLeft)
        path.addLine(to: destinationLeft)
        path.addLine(to: destinationRight)
        path.addLine(to: sourceRight)
        path.closeSubpath()
        return path
    }

    static func croppedImage(
        from image: CGImage,
        sourcePoint: CGPoint,
        bubbleDiameter: CGFloat,
        imageDrawRect: CGRect
    ) -> CGImage? {
        guard bubbleDiameter > 1,
            imageDrawRect.width > 1,
            imageDrawRect.height > 1
        else { return nil }

        let sampleSize = bubbleDiameter / magnification
        let scaleX = CGFloat(image.width) / imageDrawRect.width
        let scaleY = CGFloat(image.height) / imageDrawRect.height

        let centerX = (sourcePoint.x - imageDrawRect.minX) * scaleX
        let centerYFromBottom = (sourcePoint.y - imageDrawRect.minY) * scaleY
        let cropWidth = max(1, sampleSize * scaleX)
        let cropHeight = max(1, sampleSize * scaleY)

        var cropRect = CGRect(
            x: centerX - cropWidth / 2,
            y: CGFloat(image.height) - centerYFromBottom - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        ).integral

        cropRect.origin.x = max(0, min(cropRect.origin.x, CGFloat(image.width) - cropRect.width))
        cropRect.origin.y = max(0, min(cropRect.origin.y, CGFloat(image.height) - cropRect.height))

        guard cropRect.width >= 1,
            cropRect.height >= 1,
            cropRect.maxX <= CGFloat(image.width),
            cropRect.maxY <= CGFloat(image.height)
        else { return nil }

        return image.cropping(to: cropRect)
    }
}

final class MagnifiedCalloutPreviewController {
    private weak var hostView: NSView?
    private let rootLayer = CALayer()
    private let sourceDotLayer = CAShapeLayer()
    private let funnelLayer = CAShapeLayer()
    private let bubbleShadowLayer = CALayer()
    private let bubbleContentLayer = CALayer()
    private let bubbleBorderLayer = CAShapeLayer()

    private(set) var sourcePoint: CGPoint?
    private(set) var destinationPoint: CGPoint?
    private(set) var bubbleDiameter: CGFloat = 0

    init(hostView: NSView) {
        self.hostView = hostView
        configureLayers()
    }

    func begin(at sourcePoint: CGPoint, diameter: CGFloat, color: NSColor) {
        self.sourcePoint = sourcePoint
        destinationPoint = nil
        bubbleDiameter = diameter
        attachIfNeeded()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.frame = hostView?.bounds ?? .zero
        sourceDotLayer.fillColor = MagnifiedCalloutGeometry.sourceDotColor(for: color).cgColor
        sourceDotLayer.path = CGPath(
            ellipseIn: CGRect(
                x: sourcePoint.x - MagnifiedCalloutGeometry.sourceDotRadius,
                y: sourcePoint.y - MagnifiedCalloutGeometry.sourceDotRadius,
                width: MagnifiedCalloutGeometry.sourceDotRadius * 2,
                height: MagnifiedCalloutGeometry.sourceDotRadius * 2
            ),
            transform: nil
        )
        sourceDotLayer.isHidden = false
        funnelLayer.isHidden = true
        bubbleShadowLayer.isHidden = true
        bubbleContentLayer.contents = nil
        CATransaction.commit()
    }

    func update(
        destination proposedDestination: CGPoint,
        constrainedTo drawingBounds: CGRect,
        image: CGImage?,
        imageDrawRect: CGRect,
        color: NSColor,
        backingScale: CGFloat
    ) {
        guard let sourcePoint else { return }
        attachIfNeeded()

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
        sourceDotLayer.fillColor = MagnifiedCalloutGeometry.sourceDotColor(for: color).cgColor
        funnelLayer.fillColor = MagnifiedCalloutGeometry.connectorFillColor(for: color).cgColor
        funnelLayer.path = funnelPath
        funnelLayer.isHidden = funnelPath == nil
        sourceDotLayer.isHidden = !showsDetachedCallout

        bubbleShadowLayer.frame = bubbleRect
        bubbleShadowLayer.shadowPath = CGPath(ellipseIn: bubbleShadowLayer.bounds, transform: nil)
        bubbleShadowLayer.cornerRadius = radius
        bubbleShadowLayer.isHidden = false

        bubbleContentLayer.frame = bubbleShadowLayer.bounds
        bubbleContentLayer.cornerRadius = radius
        bubbleContentLayer.contentsScale = backingScale
        bubbleBorderLayer.frame = bubbleShadowLayer.bounds
        bubbleBorderLayer.path = CGPath(ellipseIn: bubbleBorderLayer.bounds.insetBy(dx: 2, dy: 2), transform: nil)

        if let image {
            bubbleContentLayer.contents = MagnifiedCalloutGeometry.croppedImage(
                from: image,
                sourcePoint: sourcePoint,
                bubbleDiameter: bubbleDiameter,
                imageDrawRect: imageDrawRect
            )
        } else {
            bubbleContentLayer.contents = nil
        }

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
        bubbleContentLayer.contents = nil
        CATransaction.commit()
    }

    private func configureLayers() {
        rootLayer.name = "magnified-callout-preview"
        rootLayer.zPosition = 900
        rootLayer.masksToBounds = false

        sourceDotLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        funnelLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        bubbleShadowLayer.shadowColor = NSColor.black.withAlphaComponent(0.32).cgColor
        bubbleShadowLayer.shadowOpacity = 1
        bubbleShadowLayer.shadowRadius = 16
        bubbleShadowLayer.shadowOffset = CGSize(width: 0, height: -6)
        bubbleShadowLayer.masksToBounds = false
        bubbleShadowLayer.backgroundColor = NSColor.white.cgColor

        bubbleContentLayer.masksToBounds = true
        bubbleContentLayer.contentsGravity = .resizeAspectFill
        bubbleContentLayer.magnificationFilter = .trilinear
        bubbleContentLayer.minificationFilter = .trilinear

        bubbleBorderLayer.fillColor = NSColor.clear.cgColor
        bubbleBorderLayer.strokeColor = NSColor.white.withAlphaComponent(0.96).cgColor
        bubbleBorderLayer.lineWidth = 4

        bubbleShadowLayer.addSublayer(bubbleContentLayer)
        bubbleShadowLayer.addSublayer(bubbleBorderLayer)
        rootLayer.addSublayer(funnelLayer)
        rootLayer.addSublayer(sourceDotLayer)
        rootLayer.addSublayer(bubbleShadowLayer)

        sourceDotLayer.isHidden = true
        funnelLayer.isHidden = true
        bubbleShadowLayer.isHidden = true
    }

    private func attachIfNeeded() {
        guard let hostView else { return }
        if !hostView.wantsLayer {
            hostView.wantsLayer = true
        }
        rootLayer.frame = hostView.bounds
        rootLayer.contentsScale = hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if rootLayer.superlayer == nil {
            hostView.layer?.addSublayer(rootLayer)
        }
    }
}

/// Handles loupe (magnifying glass) tool interaction.
/// Target-first magnified callout: click samples, drag moves the bubble, release commits.
final class LoupeToolHandler: AnnotationToolHandler {

    let tool: AnnotationTool = .loupe
    var requiresDisplayRefreshDuringDrag: Bool { false }

    func start(at point: NSPoint, canvas: AnnotationCanvas) -> Annotation? {
        let annotation = Annotation(
            tool: .loupe,
            startPoint: point,
            endPoint: point,
            color: canvas.currentColor,
            strokeWidth: canvas.currentStrokeWidth
        )
        annotation.loupeSourcePoint = point
        annotation.loupeMagnification = MagnifiedCalloutGeometry.magnification
        annotation.sourceImage = canvas.screenshotImage
        annotation.sourceImageBounds = canvas.captureDrawRect
        canvas.beginMagnifiedCalloutPreview(sourcePoint: point, color: annotation.color)
        return annotation
    }

    func update(to point: NSPoint, shiftHeld: Bool, canvas: AnnotationCanvas) {
        canvas.updateMagnifiedCalloutPreview(destinationPoint: point)
    }

    func finish(canvas: AnnotationCanvas) {
        guard let annotation = canvas.activeAnnotation else {
            canvas.cancelMagnifiedCalloutPreview()
            return
        }

        guard let preview = canvas.finishMagnifiedCalloutPreview() else {
            canvas.activeAnnotation = nil
            canvas.setNeedsDisplay()
            return
        }

        let halfSize = preview.bubbleDiameter / 2
        annotation.startPoint = NSPoint(
            x: preview.destinationPoint.x - halfSize,
            y: preview.destinationPoint.y - halfSize
        )
        annotation.endPoint = NSPoint(
            x: preview.destinationPoint.x + halfSize,
            y: preview.destinationPoint.y + halfSize
        )
        annotation.loupeSourcePoint = preview.sourcePoint
        annotation.loupeMagnification = MagnifiedCalloutGeometry.magnification
        annotation.sourceImage = canvas.screenshotImage
        annotation.sourceImageBounds = canvas.captureDrawRect
        annotation.bakeLoupe()

        commitAnnotation(annotation, canvas: canvas)
    }
}
