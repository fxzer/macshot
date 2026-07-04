import Cocoa
import Vision

enum AnnotationTool: Int, CaseIterable {
    case pencil          // freeform draw
    case line            // straight line
    case arrow           // arrow
    case rectangle       // outlined rect
    case filledRectangle // filled rect (opaque/redact)
    case ellipse         // outlined ellipse
    case marker          // highlighter (semi-transparent wide)
    case text            // text annotation
    case number          // auto-incrementing numbered circle
    case pixelate        // pixelate/blur region
    case blur            // gaussian blur region
    case measure         // pixel ruler / measurement line
    case loupe           // magnifying glass
    case select          // select & move existing annotations
    case translateOverlay // translated text painted over original
    case crop            // crop image (detached editor only)
    case colorSampler    // pick color from screen
    case stamp           // emoji or image stamp
}

enum LineStyle: Int, CaseIterable {
    case solid = 0
    case dashed = 1
    case dotted = 2

    func apply(to path: NSBezierPath) {
        switch self {
        case .solid: break
        case .dashed:
            let pattern: [CGFloat] = [path.lineWidth * 3, path.lineWidth * 2]
            path.setLineDash(pattern, count: 2, phase: 0)
        case .dotted:
            // Zero-length dash + round cap = perfect circles
            path.lineCapStyle = .round
            let gap = max(path.lineWidth * 2, 6)
            let pattern: [CGFloat] = [0, gap]
            path.setLineDash(pattern, count: 2, phase: 0)
        }
    }

    /// Apply with evenly-spaced segments adjusted to fit a known path length.
    func applyFitted(to path: NSBezierPath, pathLength: CGFloat) {
        guard pathLength > 0 else { apply(to: path); return }
        switch self {
        case .solid: break
        case .dashed:
            let dashLen = path.lineWidth * 3
            let gapLen = path.lineWidth * 2
            let cycle = dashLen + gapLen
            let count = max(1, round(pathLength / cycle))
            let adjustedCycle = pathLength / count
            let ratio = dashLen / cycle
            let adjDash = adjustedCycle * ratio
            let adjGap = adjustedCycle * (1 - ratio)
            let pattern: [CGFloat] = [adjDash, adjGap]
            // Center dashes on the path start so the pattern wraps symmetrically
            path.setLineDash(pattern, count: 2, phase: adjDash / 2)
        case .dotted:
            path.lineCapStyle = .round
            let gap = max(path.lineWidth * 2, 6)
            let count = max(1, round(pathLength / gap))
            let adjustedGap = pathLength / count
            let pattern: [CGFloat] = [0, adjustedGap]
            // Offset by half a gap so dots are centered on each side, not bunched at the path start
            path.setLineDash(pattern, count: 2, phase: adjustedGap / 2)
        }
    }
}

enum RectFillStyle: Int, CaseIterable {
    case stroke = 0         // outline only
    case strokeAndFill = 1  // outline + semi-transparent fill
    case fill = 2           // filled only (respects color opacity)

    /// Fill opacity multiplier for strokeAndFill style (0.2 = 20% opacity)
    static let strokeAndFillOpacity: CGFloat = 0.2
}

enum NumberFormat: Int, CaseIterable {
    case decimal = 0    // 1, 2, 3
    case roman = 1      // I, II, III
    case alpha = 2      // A, B, C
    case alphaLower = 3 // a, b, c

    func format(_ number: Int) -> String {
        switch self {
        case .decimal: return "\(number)"
        case .roman: return Self.toRoman(number)
        case .alpha: return Self.toAlpha(number, uppercase: true)
        case .alphaLower: return Self.toAlpha(number, uppercase: false)
        }
    }

    private static func toRoman(_ n: Int) -> String {
        let values = [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")]
        var result = ""
        var remaining = max(1, min(n, 3999))
        for (value, numeral) in values {
            while remaining >= value {
                result += numeral
                remaining -= value
            }
        }
        return result
    }

    private static func toAlpha(_ n: Int, uppercase: Bool) -> String {
        let base = uppercase ? Character("A") : Character("a")
        let idx = ((max(1, n) - 1) % 26)
        return String(Character(UnicodeScalar(base.asciiValue! + UInt8(idx))))
    }
}

enum NumberToolConfiguration {
    static let minStartValue = 1
    static let maxStartValue = 20

    static func clampedStartValue(_ value: Int) -> Int {
        min(max(value, minStartValue), maxStartValue)
    }
}

enum CensorMode: Int, CaseIterable {
    case pixelate = 0
    case blur = 1
    case solid = 2
    case erase = 3

    var label: String {
        switch self {
        case .pixelate: return LanguageManager.shared.localizedString("Pixelate")
        case .blur: return LanguageManager.shared.localizedString("Blur")
        case .solid: return LanguageManager.shared.localizedString("Solid")
        case .erase: return LanguageManager.shared.localizedString("Erase")
        }
    }
}

enum CensorDrawScope: Int, CaseIterable {
    case all = 0
    case textOnly = 1
}

enum ArrowStyle: Int, CaseIterable {
    case single = 0     // arrowhead at end only
    case thick = 1      // solid filled banner arrow shape
    case double = 2     // arrowheads at both ends
    case open = 3       // open/unfilled chevron arrowhead
    case tail = 4       // filled arrowhead at end + circle at start
}

class Annotation {
    let tool: AnnotationTool
    var startPoint: NSPoint
    var endPoint: NSPoint
    var color: NSColor
    var strokeWidth: CGFloat
    var text: String?
    var attributedText: NSAttributedString?  // rich text (overrides text + style flags)
    var number: Int?
    var numberFormat: NumberFormat = .decimal
    var points: [NSPoint]?
    var pressures: [CGFloat]?  // per-point pressure (parallel to points), nil = uniform width
    var sourceImage: NSImage?    // for pixelate: temporary reference during drawing (cleared after bake)
    var sourceImageBounds: NSRect = .zero  // the bounds the image was drawn into
    var bakedBlurNSImage: NSImage?    // baked result for pixelate/blur (NSImage avoids CGImage flip issues)
    var loupeSourcePoint: NSPoint?    // magnified callout sampling center
    var loupeMagnification: CGFloat = MagnifiedCalloutGeometry.magnification
    var outlineGlowImage: NSImage?   // cached selection outline glow (invalidated on move/change)
    var outlineGlowRect: NSRect = .zero  // the rect the cached glow covers
    var textImage: NSImage?   // snapshot of the NSTextView at commit time — drawn as-is, no coord math
    var textDrawRect: NSRect = .zero  // where to draw textImage in OverlayView coords
    var fontSize: CGFloat = 20
    var isBold: Bool = false
    var isItalic: Bool = false
    var groupID: UUID?  // for batch undo (e.g. auto-redact)
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false
    var rotation: CGFloat = 0         // rotation angle in radians

    var supportsRotation: Bool {
        switch tool {
        case .rectangle, .filledRectangle, .ellipse, .stamp, .text, .number:
            return true
        default:
            return false
        }
    }
    @available(*, deprecated, message: "Use anchorPoints instead for multi-anchor lines/arrows")
    var controlPoint: NSPoint? = nil  // optional bend point for line/arrow (legacy single bend)
    /// Ordered waypoints for multi-anchor lines/arrows: [start, anchor1, anchor2, ..., end].
    /// When set, overrides startPoint/endPoint/controlPoint for rendering.
    var anchorPoints: [NSPoint]?

    /// Returns the full ordered path: anchorPoints if set, otherwise [start, end].
    /// Legacy controlPoint is intentionally excluded so old single-bend lines/arrows
    /// keep their original Bezier behavior.
    var waypoints: [NSPoint] {
        if let anchors = anchorPoints, anchors.count >= 2 {
            return anchors
        }
        return [startPoint, endPoint]
    }

    /// Whether this annotation uses multi-anchor points (vs legacy single bend).
    var hasMultiAnchor: Bool { anchorPoints != nil && (anchorPoints?.count ?? 0) >= 3 }
    var hasLegacyControlPoint: Bool { controlPoint != nil && !hasMultiAnchor }

    @available(*, deprecated, message: "Use rectCornerRadius instead")
    var isRounded: Bool = false       // legacy — kept for compat, see rectCornerRadius
    var rectCornerRadius: CGFloat = 0 // 0..30, actual corner radius for rect tools
    var lineStyle: LineStyle = .solid // line/arrow/rect/ellipse stroke style
    var arrowStyle: ArrowStyle = .single // arrow head style
    var arrowReversed: Bool = false      // head at start instead of end
    var rectFillStyle: RectFillStyle = .stroke // rectangle fill mode
    var stampImage: NSImage?          // rendered emoji or loaded picture for stamp tool
    var measureInPoints: Bool = false  // true = show pt, false = show px
    var censorMode: CensorMode = .pixelate
    var censorDrawScope: CensorDrawScope = .all
    var textBgColor: NSColor?         // background pill color (nil = no background)
    var textOutlineColor: NSColor?    // text outline/stroke color (nil = no outline)
    var textAlignment: NSTextAlignment = .left // text alignment within the box
    var fontFamilyName: String?       // font family for text (nil = system default)
    var outlineColor: NSColor?        // shape/arrow/line outline color (nil = no outline)

    init(tool: AnnotationTool, startPoint: NSPoint, endPoint: NSPoint, color: NSColor, strokeWidth: CGFloat) {
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.strokeWidth = strokeWidth
    }

    // NOTE: When adding new properties, also update CodableAnnotation in AnnotationCodable.swift
    // (toCodable + fromCodable) so they are preserved in editable history.
    func clone(includeBakedRenderAssets: Bool = true) -> Annotation {
        let c = Annotation(tool: tool, startPoint: startPoint, endPoint: endPoint, color: color, strokeWidth: strokeWidth)
        c.text = text
        c.attributedText = attributedText
        c.number = number
        c.numberFormat = numberFormat
        c.points = points
        c.pressures = pressures
        if includeBakedRenderAssets {
            c.bakedBlurNSImage = bakedBlurNSImage
        }
        c.loupeSourcePoint = loupeSourcePoint
        c.loupeMagnification = loupeMagnification
        c.textImage = textImage
        c.textDrawRect = textDrawRect
        c.fontSize = fontSize
        c.isBold = isBold
        c.isItalic = isItalic
        c.groupID = groupID
        c.isUnderline = isUnderline
        c.isStrikethrough = isStrikethrough
        c.rotation = rotation
        c.controlPoint = controlPoint
        c.anchorPoints = anchorPoints
        c.isRounded = isRounded
        c.rectCornerRadius = rectCornerRadius
        c.lineStyle = lineStyle
        c.arrowStyle = arrowStyle
        c.arrowReversed = arrowReversed
        c.rectFillStyle = rectFillStyle
        c.stampImage = stampImage
        c.measureInPoints = measureInPoints
        c.censorMode = censorMode
        c.censorDrawScope = censorDrawScope
        c.textBgColor = textBgColor
        c.textOutlineColor = textOutlineColor
        c.textAlignment = textAlignment
        c.fontFamilyName = fontFamilyName
        c.outlineColor = outlineColor
        c.sourceImage = sourceImage
        c.sourceImageBounds = sourceImageBounds
        if includeBakedRenderAssets {
            c.outlineGlowImage = outlineGlowImage
            c.outlineGlowRect = outlineGlowRect
        }
        return c
    }

    func propertyChangeSnapshot() -> Annotation {
        clone(includeBakedRenderAssets: false)
    }

    private func hasSameColor(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.isEqual(right)
        default:
            return false
        }
    }

    func hasEquivalentPropertyState(to other: Annotation) -> Bool {
        guard tool == other.tool,
              color.isEqual(other.color),
              strokeWidth == other.strokeWidth,
              lineStyle == other.lineStyle,
              arrowStyle == other.arrowStyle,
              arrowReversed == other.arrowReversed,
              rectFillStyle == other.rectFillStyle,
              rectCornerRadius == other.rectCornerRadius,
              fontSize == other.fontSize,
              isBold == other.isBold,
              isItalic == other.isItalic,
              isUnderline == other.isUnderline,
              isStrikethrough == other.isStrikethrough,
              hasSameColor(textBgColor, other.textBgColor),
              hasSameColor(textOutlineColor, other.textOutlineColor),
              textAlignment == other.textAlignment,
              fontFamilyName == other.fontFamilyName,
              numberFormat == other.numberFormat,
              measureInPoints == other.measureInPoints,
              censorMode == other.censorMode,
              censorDrawScope == other.censorDrawScope,
              hasSameColor(outlineColor, other.outlineColor),
              sourceImage === other.sourceImage,
              sourceImageBounds == other.sourceImageBounds,
              loupeMagnification == other.loupeMagnification
        else {
            return false
        }

        if tool == .loupe {
            return startPoint == other.startPoint
                && endPoint == other.endPoint
                && loupeSourcePoint == other.loupeSourcePoint
        }

        return true
    }

    /// Copy all visual/style properties from another annotation (for undo/redo of property edits).
    func copyProperties(from src: Annotation) {
        color = src.color
        strokeWidth = src.strokeWidth
        lineStyle = src.lineStyle
        arrowStyle = src.arrowStyle
        arrowReversed = src.arrowReversed
        rectFillStyle = src.rectFillStyle
        rectCornerRadius = src.rectCornerRadius
        fontSize = src.fontSize
        isBold = src.isBold
        isItalic = src.isItalic
        isUnderline = src.isUnderline
        isStrikethrough = src.isStrikethrough
        textBgColor = src.textBgColor
        textOutlineColor = src.textOutlineColor
        textAlignment = src.textAlignment
        fontFamilyName = src.fontFamilyName
        outlineColor = src.outlineColor
        numberFormat = src.numberFormat
        measureInPoints = src.measureInPoints
        censorMode = src.censorMode
        censorDrawScope = src.censorDrawScope
        sourceImage = src.sourceImage
        sourceImageBounds = src.sourceImageBounds
        bakedBlurNSImage = src.bakedBlurNSImage
        loupeMagnification = src.loupeMagnification
        if tool == .loupe {
            startPoint = src.startPoint
            endPoint = src.endPoint
            loupeSourcePoint = src.loupeSourcePoint
        }
    }

    var boundingRect: NSRect {
        var minX = min(startPoint.x, endPoint.x)
        var minY = min(startPoint.y, endPoint.y)
        var maxX = max(startPoint.x, endPoint.x)
        var maxY = max(startPoint.y, endPoint.y)
        if let anchors = anchorPoints {
            for p in anchors {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        if let cp = controlPoint {
            minX = min(minX, cp.x); minY = min(minY, cp.y)
            maxX = max(maxX, cp.x); maxY = max(maxY, cp.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether this annotation type can be moved
    var isMovable: Bool {
        switch tool {
        case .select, .translateOverlay:
            return false
        default:
            return true
        }
    }

    /// Hit-test: returns true if the point is close enough to this annotation
    func hitTest(point: NSPoint, threshold: CGFloat = 8) -> Bool {
        // For rotated annotations, un-rotate the test point around the annotation's center
        var point = point
        if rotation != 0 && supportsRotation {
            let center = NSPoint(x: boundingRect.midX, y: boundingRect.midY)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let cosR = cos(-rotation)
            let sinR = sin(-rotation)
            point = NSPoint(x: center.x + dx * cosR - dy * sinR,
                            y: center.y + dx * sinR + dy * cosR)
        }
        switch tool {
        case .pencil, .marker:
            guard let points = points else { return false }
            let strokeRadius = strokeWidth / 2
            let effectiveThreshold = max(threshold, strokeRadius)
            for p in points {
                if hypot(p.x - point.x, p.y - point.y) < effectiveThreshold { return true }
            }
            return false
        case .line, .measure:
            if !boundingRect.insetBy(dx: -threshold, dy: -threshold).contains(point) {
                return false
            }
            if hasMultiAnchor {
                return distanceToPolyline(point: point, waypoints: waypoints) < threshold
            }
            if let cp = controlPoint {
                return distanceToQuadCurve(point: point, from: startPoint, control: cp, to: endPoint) < threshold
            }
            return distanceToLineSegment(point: point, from: startPoint, to: endPoint) < threshold
        case .arrow:
            if arrowStyle == .thick {
                let totalLen = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
                let sizeScale = min(1.0, max(0.2, totalLen / 120))
                // Match the actual drawn shape width: shaft is strokeWidth*1.5, head is strokeWidth*3
                let shaftHalf = max(4, strokeWidth * 1.5) * sizeScale
                let hitThreshold = max(threshold, shaftHalf + 4)
                if !boundingRect.insetBy(dx: -hitThreshold, dy: -hitThreshold).contains(point) {
                    return false
                }
                if hasMultiAnchor {
                    return distanceToPolyline(point: point, waypoints: waypoints) < hitThreshold
                }
                if let cp = controlPoint {
                    return distanceToQuadCurve(point: point, from: startPoint, control: cp, to: endPoint) < hitThreshold
                }
                return distanceToLineSegment(point: point, from: startPoint, to: endPoint) < hitThreshold
            }
            if !boundingRect.insetBy(dx: -threshold, dy: -threshold).contains(point) {
                return false
            }
            if hasMultiAnchor {
                return distanceToPolyline(point: point, waypoints: waypoints) < threshold
            }
            if let cp = controlPoint {
                return distanceToQuadCurve(point: point, from: startPoint, control: cp, to: endPoint) < threshold
            }
            return distanceToLineSegment(point: point, from: startPoint, to: endPoint) < threshold
        case .rectangle, .filledRectangle:
            let rect = boundingRect
            if tool == .filledRectangle || rectFillStyle == .fill || rectFillStyle == .strokeAndFill {
                return rect.insetBy(dx: -threshold, dy: -threshold).contains(point)
            }
            // For outlined rect, check proximity to edges
            let outer = rect.insetBy(dx: -threshold, dy: -threshold)
            let inner = rect.insetBy(dx: threshold, dy: threshold)
            return outer.contains(point) && (inner.width < 0 || inner.height < 0 || !inner.contains(point))
        case .ellipse:
            let rect = boundingRect
            guard rect.width > 0, rect.height > 0 else { return false }
            let cx = rect.midX, cy = rect.midY
            let rx = rect.width / 2, ry = rect.height / 2
            let nx = (point.x - cx) / rx, ny = (point.y - cy) / ry
            let d = nx * nx + ny * ny
            if rectFillStyle == .fill || rectFillStyle == .strokeAndFill {
                return d <= 1.0 + (threshold / min(rx, ry))
            }
            let rNorm = threshold / min(rx, ry)
            return abs(d - 1.0) < rNorm * 2
        case .loupe:
            let rect = boundingRect
            guard rect.width > 0, rect.height > 0 else { return false }
            let cx = rect.midX, cy = rect.midY
            let rx = rect.width / 2, ry = rect.height / 2
            let nx = (point.x - cx) / rx, ny = (point.y - cy) / ry
            let d = nx * nx + ny * ny
            return d <= 1.0 + (threshold / min(rx, ry))
        case .text:
            return textDrawRect.insetBy(dx: -threshold, dy: -threshold).contains(point)
        case .number:
            let radius = 8 + strokeWidth * 3 + threshold
            return hypot(point.x - startPoint.x, point.y - startPoint.y) < radius
        case .stamp, .pixelate, .blur:
            return boundingRect.insetBy(dx: -threshold, dy: -threshold).contains(point)
        default:
            return false
        }
    }

    /// Move this annotation by a delta
    func move(dx: CGFloat, dy: CGFloat) {
        startPoint.x += dx
        startPoint.y += dy
        endPoint.x += dx
        endPoint.y += dy
        if textDrawRect != .zero {
            textDrawRect.origin.x += dx
            textDrawRect.origin.y += dy
        }
        if let loupeSourcePoint {
            self.loupeSourcePoint = NSPoint(x: loupeSourcePoint.x + dx, y: loupeSourcePoint.y + dy)
        }
        if var pts = points {
            for i in 0..<pts.count {
                pts[i].x += dx
                pts[i].y += dy
            }
            points = pts
        }
        if var cp = controlPoint {
            cp.x += dx; cp.y += dy
            controlPoint = cp
        }
        if var anchors = anchorPoints {
            for i in 0..<anchors.count {
                anchors[i].x += dx
                anchors[i].y += dy
            }
            anchorPoints = anchors
        }
        // Clear baked image so it re-renders at the new position.
        // .blur shares the same bakedBlurNSImage cache as .pixelate (see Annotation+DrawingCensor),
        // so legacy .blur annotations must also invalidate on move.
        if tool == .loupe || tool == .pixelate || tool == .blur {
            bakedBlurNSImage = nil
        }
        // Shift the cached glow rect instead of invalidating — the glow shape
        // doesn't change during a move, only its position.
        if outlineGlowImage != nil {
            outlineGlowRect.origin.x += dx
            outlineGlowRect.origin.y += dy
        }
    }

    // MARK: - Geometry helpers

    /// Approximate the arc length of a cubic bezier by sampling.
    static func approxBezierLength(from p0: NSPoint, cp1: NSPoint, cp2: NSPoint, to p3: NSPoint, steps: Int = 30) -> CGFloat {
        var length: CGFloat = 0
        var prev = p0
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let u = 1 - t
            let x = u*u*u*p0.x + 3*u*u*t*cp1.x + 3*u*t*t*cp2.x + t*t*t*p3.x
            let y = u*u*u*p0.y + 3*u*u*t*cp1.y + 3*u*t*t*cp2.y + t*t*t*p3.y
            length += hypot(x - prev.x, y - prev.y)
            prev = NSPoint(x: x, y: y)
        }
        return length
    }

    fileprivate func distanceToQuadCurve(point: NSPoint, from a: NSPoint, control c: NSPoint, to b: NSPoint) -> CGFloat {
        // The curve is drawn as a cubic bezier with cp1 == cp2 == c (NSBezierPath.curve),
        // so sample the cubic formula to match the actual rendered path.
        let steps = 40
        var minDist = CGFloat.greatestFiniteMagnitude
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let u = 1 - t
            let px = u*u*u*a.x + 3*u*u*t*c.x + 3*u*t*t*c.x + t*t*t*b.x
            let py = u*u*u*a.y + 3*u*u*t*c.y + 3*u*t*t*c.y + t*t*t*b.y
            let d = hypot(point.x - px, point.y - py)
            if d < minDist { minDist = d }
        }
        return minDist
    }

    fileprivate func distanceToLineSegment(point: NSPoint, from a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let proj = NSPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }

    /// Minimum distance from a point to the smooth curve through waypoints.
    fileprivate func distanceToPolyline(point: NSPoint, waypoints pts: [NSPoint]) -> CGFloat {
        guard pts.count >= 2 else { return .greatestFiniteMagnitude }
        if pts.count == 2 {
            return distanceToLineSegment(point: point, from: pts[0], to: pts[1])
        }
        var minDist = CGFloat.greatestFiniteMagnitude
        for seg in 0..<(pts.count - 1) {
            let p0 = seg > 0 ? pts[seg - 1] : pts[seg]
            let p1 = pts[seg]
            let p2 = pts[seg + 1]
            let p3 = seg + 2 < pts.count ? pts[seg + 2] : pts[seg + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            let segmentBounds = NSRect(
                x: min(min(p1.x, p2.x), min(cp1.x, cp2.x)),
                y: min(min(p1.y, p2.y), min(cp1.y, cp2.y)),
                width: max(max(p1.x, p2.x), max(cp1.x, cp2.x)) - min(min(p1.x, p2.x), min(cp1.x, cp2.x)),
                height: max(max(p1.y, p2.y), max(cp1.y, cp2.y)) - min(min(p1.y, p2.y), min(cp1.y, cp2.y))
            )
            if minDist.isFinite
                && !segmentBounds.insetBy(dx: -minDist, dy: -minDist).contains(point)
            {
                continue
            }

            let segmentLength = max(
                hypot(p2.x - p1.x, p2.y - p1.y),
                Self.approxBezierLength(from: p1, cp1: cp1, cp2: cp2, to: p2, steps: 8)
            )
            let steps = max(6, min(18, Int(ceil(segmentLength / 24))))
            var prev = p1
            for step in 1...steps {
                let localT = CGFloat(step) / CGFloat(steps)
                let u = 1 - localT
                let px = u*u*u*p1.x + 3*u*u*localT*cp1.x + 3*u*localT*localT*cp2.x + localT*localT*localT*p2.x
                let py = u*u*u*p1.y + 3*u*u*localT*cp1.y + 3*u*localT*localT*cp2.y + localT*localT*localT*p2.y
                let cur = NSPoint(x: px, y: py)

                let d = distanceToLineSegment(point: point, from: prev, to: cur)
                if d < minDist { minDist = d }
                prev = cur
            }
        }
        return minDist
    }

}
