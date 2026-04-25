import Cocoa

// MARK: - Shape Drawing (Rectangle, Ellipse, Line)

extension Annotation {

    func drawStraightLine() {
        // Multi-anchor: smooth Catmull-Rom spline
        if hasMultiAnchor {
            let pts = waypoints
            let path = Self.smoothPath(through: pts)
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            if lineStyle != .solid {
                lineStyle.applyFitted(to: path, pathLength: Self.smoothPathLength(pts))
            }
            // Outline: same path stroked wider first, then normal on top
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke(); path.stroke()
            return
        }

        // Legacy: straight line or single bezier bend
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        if lineStyle != .solid {
            let length: CGFloat
            if hasMultiAnchor {
                length = Annotation.smoothPathLength(waypoints)
            } else if let cp = controlPoint {
                length = Annotation.approxBezierLength(from: startPoint, cp1: cp, cp2: cp, to: endPoint)
            } else {
                length = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
            }
            lineStyle.applyFitted(to: path, pathLength: length)
        }
        path.move(to: startPoint)
        if hasMultiAnchor {
            let smoothPath = Self.smoothPath(through: waypoints)
            path.append(smoothPath)
        } else if let cp = controlPoint {
            path.curve(to: endPoint, controlPoint1: cp, controlPoint2: cp)
        } else {
            path.line(to: endPoint)
        }
        // Outline: same path stroked wider first, then normal on top
        if let oc = outlineColor {
            path.lineWidth = strokeWidth + 6
            oc.setStroke(); path.stroke()
            path.lineWidth = strokeWidth
        }
        color.setStroke(); path.stroke()
    }

    func drawRectangle(forceFilled: Bool = false) {
        let rect = boundingRect
        guard rect.width > 0, rect.height > 0 else { return }
        // Migrate legacy isRounded to rectCornerRadius
        let cornerRadius: CGFloat = rectCornerRadius > 0 ? rectCornerRadius : (isRounded ? min(rect.width, rect.height) * 0.2 : 0)
        let style = forceFilled ? RectFillStyle.fill : rectFillStyle

        // When outline is active, force solid style (dashed/dotted disabled in UI)
        let effectiveLineStyle = outlineColor != nil ? .solid : lineStyle

        let rectPerimeter: CGFloat = {
            let r = min(cornerRadius, min(rect.width, rect.height) / 2)
            return 2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r) + 2 * .pi * r
        }()

        switch style {
        case .fill:
            if let oc = outlineColor {
                let outlinePath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                outlinePath.lineWidth = strokeWidth + 6
                outlinePath.lineJoinStyle = cornerRadius > 0 ? .round : .miter
                oc.setStroke()
                outlinePath.stroke()
            }
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

        case .strokeAndFill:
            let fillAlpha = color.alphaComponent * RectFillStyle.strokeAndFillOpacity
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.lineWidth = strokeWidth
            path.lineJoinStyle = cornerRadius > 0 ? .round : .miter
            if effectiveLineStyle != .solid {
                effectiveLineStyle.applyFitted(to: path, pathLength: rectPerimeter)
            }
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke()
            path.stroke()

        case .stroke:
            if cornerRadius < 1 && (effectiveLineStyle == .dotted || effectiveLineStyle == .dashed) {
                if effectiveLineStyle == .dotted {
                    drawDottedRectPerSide(rect: rect)
                } else {
                    drawDashedRectPerSide(rect: rect)
                }
            } else {
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                path.lineWidth = strokeWidth
                path.lineJoinStyle = cornerRadius > 0 ? .round : .miter
                if effectiveLineStyle != .solid {
                    effectiveLineStyle.applyFitted(to: path, pathLength: rectPerimeter)
                }
                if let oc = outlineColor {
                    path.lineWidth = strokeWidth + 6
                    oc.setStroke(); path.stroke()
                    path.lineWidth = strokeWidth
                }
                color.setStroke()
                path.stroke()
            }
        }
    }

    /// Draw a dotted rectangle with dots guaranteed at every corner.
    /// Each side is drawn independently so dots tile evenly per-side.
    fileprivate func drawDottedRectPerSide(rect: NSRect) {
        let dotRadius = strokeWidth / 2
        let idealGap = max(strokeWidth * 2, 6)
        color.setFill()

        // Corner points (bottom-left origin, clockwise: BL → TL → TR → BR)
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY),  // bottom-left
            NSPoint(x: rect.minX, y: rect.maxY),  // top-left
            NSPoint(x: rect.maxX, y: rect.maxY),  // top-right
            NSPoint(x: rect.maxX, y: rect.minY),  // bottom-right
        ]

        for i in 0..<4 {
            let p0 = corners[i]
            let p1 = corners[(i + 1) % 4]
            let sideLen = hypot(p1.x - p0.x, p1.y - p0.y)
            guard sideLen > 0 else { continue }

            // Number of segments (gaps between dots). At least 1 so we get dots at both ends.
            let n = max(1, Int(round(sideLen / idealGap)))
            let step = sideLen / CGFloat(n)
            let dx = (p1.x - p0.x) / sideLen
            let dy = (p1.y - p0.y) / sideLen

            // Draw dots from p0 to p1 (inclusive of p0, exclusive of p1 to avoid double-drawing corners)
            for j in 0..<n {
                let t = CGFloat(j) * step
                let x = p0.x + dx * t
                let y = p0.y + dy * t
                let dotRect = NSRect(x: x - dotRadius, y: y - dotRadius, width: strokeWidth, height: strokeWidth)
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    /// Draw a dashed rectangle with dashes evenly distributed per side.
    /// Each side is inset by half the stroke width so corners don't overlap.
    fileprivate func drawDashedRectPerSide(rect: NSRect) {
        let idealDash = strokeWidth * 3
        let idealGap = strokeWidth * 2
        let idealCycle = idealDash + idealGap
        let hw = strokeWidth / 2  // half stroke width — inset to avoid corner overlap
        color.setStroke()

        // Corners inset by half stroke width along each side's direction
        let sides: [(NSPoint, NSPoint)] = [
            // bottom: left→right
            (NSPoint(x: rect.minX + hw, y: rect.minY), NSPoint(x: rect.maxX - hw, y: rect.minY)),
            // left: bottom→top
            (NSPoint(x: rect.minX, y: rect.minY + hw), NSPoint(x: rect.minX, y: rect.maxY - hw)),
            // top: left→right
            (NSPoint(x: rect.minX + hw, y: rect.maxY), NSPoint(x: rect.maxX - hw, y: rect.maxY)),
            // right: bottom→top
            (NSPoint(x: rect.maxX, y: rect.minY + hw), NSPoint(x: rect.maxX, y: rect.maxY - hw)),
        ]

        for (p0, p1) in sides {
            let sideLen = hypot(p1.x - p0.x, p1.y - p0.y)
            guard sideLen > 0 else { continue }

            let path = NSBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .butt
            path.move(to: p0)
            path.line(to: p1)

            let n = max(1, round(sideLen / idealCycle))
            let adjustedCycle = sideLen / n
            let ratio = idealDash / idealCycle
            let dash = adjustedCycle * ratio
            let gap = adjustedCycle - dash
            let pattern: [CGFloat] = [dash, gap]
            path.setLineDash(pattern, count: 2, phase: dash / 2)
            path.stroke()
        }
    }

    func drawEllipse() {
        let rect = boundingRect
        guard rect.width > 0, rect.height > 0 else { return }

        // When outline is active, force solid style (dashed/dotted disabled in UI)
        let effectiveLineStyle = outlineColor != nil ? .solid : lineStyle

        let ellipsePerimeter: CGFloat = {
            let a = rect.width / 2, b = rect.height / 2
            return CGFloat.pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        }()

        switch rectFillStyle {
        case .fill:
            if let oc = outlineColor {
                let outlinePath = NSBezierPath(ovalIn: rect)
                outlinePath.lineWidth = strokeWidth + 6
                oc.setStroke()
                outlinePath.stroke()
            }
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()

        case .strokeAndFill:
            let fillAlpha = color.alphaComponent * RectFillStyle.strokeAndFillOpacity
            color.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = strokeWidth
            if effectiveLineStyle != .solid {
                effectiveLineStyle.applyFitted(to: path, pathLength: ellipsePerimeter)
            }
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke()
            path.stroke()

        case .stroke:
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = strokeWidth
            if effectiveLineStyle != .solid {
                effectiveLineStyle.applyFitted(to: path, pathLength: ellipsePerimeter)
            }
            if let oc = outlineColor {
                path.lineWidth = strokeWidth + 6
                oc.setStroke(); path.stroke()
                path.lineWidth = strokeWidth
            }
            color.setStroke()
            path.stroke()
        }
    }
}
