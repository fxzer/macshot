import Cocoa

// MARK: - Freeform Drawing (Pencil, Marker)

extension Annotation {

    func drawFreeform(alpha: CGFloat, width: CGFloat) {
        guard let points = points, !points.isEmpty else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Single point: draw a filled circle (dot)
        if points.count == 1 {
            let p = points[0]
            let r = width / 2
            ctx.setAlpha(alpha)
            color.withAlphaComponent(1.0).setFill()
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: width, height: width))
            ctx.setAlpha(1.0)
            return
        }

        // For dotted freeform, place dots at evenly-spaced arc-length positions
        // to avoid uneven spacing caused by segment boundaries in the polyline.
        if lineStyle == .dotted {
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            color.withAlphaComponent(1.0).setFill()

            // Compute cumulative arc lengths
            var cumLengths: [CGFloat] = [0]
            for i in 1..<points.count {
                cumLengths.append(cumLengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
            }
            let totalLength = cumLengths.last!
            guard totalLength > 0 else {
                ctx.endTransparencyLayer()
                ctx.setAlpha(1.0)
                return
            }

            let gap = max(width * 2, 6)
            let count = max(1, round(totalLength / gap))
            let spacing = totalLength / count
            let dotRadius = width / 2

            var segIdx = 0
            var dist: CGFloat = 0
            while dist <= totalLength + 0.01 {
                // Find the segment containing this distance
                while segIdx < points.count - 2 && cumLengths[segIdx + 1] < dist {
                    segIdx += 1
                }
                let segStart = cumLengths[segIdx]
                let segLen = cumLengths[segIdx + 1] - segStart
                let t: CGFloat = segLen > 0 ? (dist - segStart) / segLen : 0
                let x = points[segIdx].x + t * (points[segIdx + 1].x - points[segIdx].x)
                let y = points[segIdx].y + t * (points[segIdx + 1].y - points[segIdx].y)
                let dotRect = NSRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                NSBezierPath(ovalIn: dotRect).fill()
                dist += spacing
            }

            ctx.endTransparencyLayer()
            ctx.setAlpha(1.0)
            return
        }

        // Variable-width stroke (pressure sensitive)
        if let pressures = pressures, pressures.count == points.count, lineStyle == .solid {
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            color.withAlphaComponent(1.0).setFill()

            // Map raw pressure (0–1) to a usable width range:
            // - Minimum 20% of stroke width even at lightest touch
            // - Power curve (0.6) compresses the range so light/medium pressure
            //   differences are subtle, heavy pressure stands out
            let minFraction: CGFloat = 0.2
            func pressureWidth(_ p: CGFloat) -> CGFloat {
                let mapped = minFraction + pow(min(max(p, 0), 1), 0.6) * (1.0 - minFraction)
                return max(width * mapped, 0.5)
            }

            // Draw filled circles at each point + connecting quads for smooth width transitions
            for i in 0..<points.count {
                let r = pressureWidth(pressures[i]) / 2
                ctx.fillEllipse(in: CGRect(x: points[i].x - r, y: points[i].y - r, width: r * 2, height: r * 2))

                if i > 0 {
                    let p0 = points[i - 1]
                    let p1 = points[i]
                    let r0 = pressureWidth(pressures[i - 1]) / 2
                    let r1 = pressureWidth(pressures[i]) / 2

                    let dx = p1.x - p0.x
                    let dy = p1.y - p0.y
                    let len = hypot(dx, dy)
                    guard len > 0.1 else { continue }
                    // Normal perpendicular to the line segment
                    let nx = -dy / len
                    let ny = dx / len

                    // Build a quad connecting the two circles
                    let quad = NSBezierPath()
                    quad.move(to: NSPoint(x: p0.x + nx * r0, y: p0.y + ny * r0))
                    quad.line(to: NSPoint(x: p1.x + nx * r1, y: p1.y + ny * r1))
                    quad.line(to: NSPoint(x: p1.x - nx * r1, y: p1.y - ny * r1))
                    quad.line(to: NSPoint(x: p0.x - nx * r0, y: p0.y - ny * r0))
                    quad.close()
                    quad.fill()
                }
            }

            ctx.endTransparencyLayer()
            ctx.setAlpha(1.0)
            return
        }

        // Use a transparency layer so self-overlapping segments don't compound alpha
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        lineStyle.apply(to: path)
        color.withAlphaComponent(1.0).setStroke()
        path.move(to: points[0])
        for i in 1..<points.count {
            path.line(to: points[i])
        }
        path.stroke()
        ctx.endTransparencyLayer()
        ctx.setAlpha(1.0)
    }

    /// Build a smooth Catmull-Rom spline path through the given points.
    /// For 2 points: straight line. For 3+: smooth curves through all points.
    static func smoothPath(through pts: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard pts.count >= 2 else { return path }
        path.move(to: pts[0])
        if pts.count == 2 {
            path.line(to: pts[1])
            return path
        }
        // Catmull-Rom → cubic Bezier conversion
        // For each segment i→i+1, compute control points from surrounding points
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : pts[i + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    /// Approximate length of a smooth path through waypoints.
    static func smoothPathLength(_ pts: [NSPoint]) -> CGFloat {
        guard pts.count >= 2 else { return 0 }
        if pts.count == 2 {
            return hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
        }
        // Sample the Catmull-Rom spline
        let steps = pts.count * 20
        var length: CGFloat = 0
        var prev = pts[0]
        for s in 1...steps {
            let t = CGFloat(s) / CGFloat(steps)
            let totalSegments = CGFloat(pts.count - 1)
            let segF = t * totalSegments
            let seg = min(Int(segF), pts.count - 2)
            let localT = segF - CGFloat(seg)

            let p0 = seg > 0 ? pts[seg - 1] : pts[seg]
            let p1 = pts[seg]
            let p2 = pts[seg + 1]
            let p3 = seg + 2 < pts.count ? pts[seg + 2] : pts[seg + 1]

            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)

            let u = 1 - localT
            let px = u*u*u*p1.x + 3*u*u*localT*cp1.x + 3*u*localT*localT*cp2.x + localT*localT*localT*p2.x
            let py = u*u*u*p1.y + 3*u*u*localT*cp1.y + 3*u*localT*localT*cp2.y + localT*localT*localT*p2.y
            let cur = NSPoint(x: px, y: py)
            length += hypot(cur.x - prev.x, cur.y - prev.y)
            prev = cur
        }
        return length
    }
}
