import Cocoa

// MARK: - Arrow Drawing

extension Annotation {

    func drawArrow() {
        // Thick style is a completely different shape — handle separately
        if arrowStyle == .thick {
            drawThickArrow()
            return
        }

        let pts = arrowReversed ? waypoints.reversed() : waypoints
        guard pts.count >= 2 else { return }
        let firstPt = pts.first!
        let lastPt = pts.last!

        let fullArrowLen: CGFloat = max(14, strokeWidth * 5)
        let totalLen = hypot(lastPt.x - firstPt.x, lastPt.y - firstPt.y)
        let maxHead = totalLen * 0.45
        let arrowLen: CGFloat = min(fullArrowLen, max(4, maxHead))
        let arrowAngle: CGFloat = .pi / 6

        // End arrowhead angle
        let endAngle: CGFloat
        if hasMultiAnchor {
            let preLast = pts.count >= 2 ? pts[pts.count - 2] : firstPt
            endAngle = atan2(lastPt.y - preLast.y, lastPt.x - preLast.x)
        } else if let cp = controlPoint {
            endAngle = atan2(lastPt.y - cp.y, lastPt.x - cp.x)
        } else {
            endAngle = atan2(lastPt.y - firstPt.y, lastPt.x - firstPt.x)
        }
        let ep1 = NSPoint(x: lastPt.x - arrowLen * cos(endAngle - arrowAngle),
                           y: lastPt.y - arrowLen * sin(endAngle - arrowAngle))
        let ep2 = NSPoint(x: lastPt.x - arrowLen * cos(endAngle + arrowAngle),
                           y: lastPt.y - arrowLen * sin(endAngle + arrowAngle))
        let endBase = NSPoint(x: (ep1.x + ep2.x) / 2, y: (ep1.y + ep2.y) / 2)

        // Start arrowhead geometry (for double style)
        var startBase = firstPt
        var sp1 = firstPt, sp2 = firstPt
        if arrowStyle == .double {
            let startAngle: CGFloat
            if hasMultiAnchor {
                let postFirst = pts.count >= 2 ? pts[1] : lastPt
                startAngle = atan2(firstPt.y - postFirst.y, firstPt.x - postFirst.x)
            } else if let cp = controlPoint {
                startAngle = atan2(firstPt.y - cp.y, firstPt.x - cp.x)
            } else {
                startAngle = atan2(firstPt.y - lastPt.y, firstPt.x - lastPt.x)
            }
            sp1 = NSPoint(x: firstPt.x - arrowLen * cos(startAngle - arrowAngle),
                           y: firstPt.y - arrowLen * sin(startAngle - arrowAngle))
            sp2 = NSPoint(x: firstPt.x - arrowLen * cos(startAngle + arrowAngle),
                           y: firstPt.y - arrowLen * sin(startAngle + arrowAngle))
            startBase = NSPoint(x: (sp1.x + sp2.x) / 2, y: (sp1.y + sp2.y) / 2)
        }

        // Tail circle radius
        let tailRadius: CGFloat = max(4, strokeWidth * 2)
        let lineStart = arrowStyle == .double ? startBase : firstPt

        // Draw the line shaft
        let path: NSBezierPath
        if hasMultiAnchor {
            // Multi-anchor: smooth Catmull-Rom spline
            var shaftPts = pts
            shaftPts[0] = lineStart
            shaftPts[shaftPts.count - 1] = endBase
            path = Self.smoothPath(through: shaftPts)
        } else {
            // Legacy: straight or single bezier bend
            path = NSBezierPath()
            path.move(to: lineStart)
            if let cp = controlPoint {
                path.curve(to: endBase, controlPoint1: cp, controlPoint2: cp)
            } else {
                path.line(to: endBase)
            }
        }
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        if lineStyle != .solid {
            let length = hasMultiAnchor ? Self.smoothPathLength(pts) :
                (controlPoint != nil ? Annotation.approxBezierLength(from: lineStart, cp1: controlPoint!, cp2: controlPoint!, to: endBase) :
                 hypot(endBase.x - lineStart.x, endBase.y - lineStart.y))
            lineStyle.applyFitted(to: path, pathLength: length)
        }
        // Outline: draw wider stroke behind everything
        let outlineW: CGFloat = 3
        if let oc = outlineColor {
            oc.setStroke()
            oc.setFill()
            let outlinePath = path.copy() as! NSBezierPath
            outlinePath.lineWidth = strokeWidth + outlineW * 2
            outlinePath.lineCapStyle = .round
            outlinePath.stroke()
            // Outline arrowheads
            switch arrowStyle {
            case .single, .tail:
                let h = NSBezierPath(); h.move(to: lastPt); h.line(to: ep1); h.line(to: ep2); h.close()
                h.lineWidth = outlineW * 2; h.lineJoinStyle = .round; h.stroke(); h.fill()
            case .double:
                let eh = NSBezierPath(); eh.move(to: lastPt); eh.line(to: ep1); eh.line(to: ep2); eh.close()
                eh.lineWidth = outlineW * 2; eh.lineJoinStyle = .round; eh.stroke(); eh.fill()
                let sh = NSBezierPath(); sh.move(to: firstPt); sh.line(to: sp1); sh.line(to: sp2); sh.close()
                sh.lineWidth = outlineW * 2; sh.lineJoinStyle = .round; sh.stroke(); sh.fill()
            case .open:
                let h = NSBezierPath(); h.lineWidth = strokeWidth + outlineW * 2
                h.lineCapStyle = .round; h.lineJoinStyle = .round
                h.move(to: ep1); h.line(to: lastPt); h.line(to: ep2); h.stroke()
            case .thick: break
            }
            if arrowStyle == .tail {
                let cr = NSRect(x: firstPt.x - tailRadius - outlineW, y: firstPt.y - tailRadius - outlineW,
                                width: (tailRadius + outlineW) * 2, height: (tailRadius + outlineW) * 2)
                NSBezierPath(ovalIn: cr).fill()
            }
        }

        color.setStroke()
        path.stroke()

        // Draw arrowhead(s)
        color.setFill()
        color.setStroke()
        switch arrowStyle {
        case .single, .tail:
            let head = NSBezierPath()
            head.move(to: lastPt)
            head.line(to: ep1)
            head.line(to: ep2)
            head.close()
            head.fill()
        case .double:
            let endHead = NSBezierPath()
            endHead.move(to: lastPt)
            endHead.line(to: ep1)
            endHead.line(to: ep2)
            endHead.close()
            endHead.fill()
            let startHead = NSBezierPath()
            startHead.move(to: firstPt)
            startHead.line(to: sp1)
            startHead.line(to: sp2)
            startHead.close()
            startHead.fill()
        case .open:
            let head = NSBezierPath()
            head.lineWidth = strokeWidth
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.move(to: ep1)
            head.line(to: lastPt)
            head.line(to: ep2)
            head.stroke()
        case .thick:
            break // handled by early return above
        }

        // Tail: circle at start
        if arrowStyle == .tail {
            let circleRect = NSRect(x: firstPt.x - tailRadius, y: firstPt.y - tailRadius,
                                    width: tailRadius * 2, height: tailRadius * 2)
            NSBezierPath(ovalIn: circleRect).fill()
        }
    }

    fileprivate func drawThickArrow() {
        let pts = arrowReversed ? waypoints.reversed() : waypoints
        let firstPt = pts.first ?? startPoint
        let lastPt = pts.last ?? endPoint
        let totalLen = hasMultiAnchor ? Self.smoothPathLength(pts) : hypot(lastPt.x - firstPt.x, lastPt.y - firstPt.y)
        guard totalLen > 1 else { return }

        // End angle: direction of the last segment approaching the tip
        let preLast = pts.count >= 2 ? pts[pts.count - 2] : firstPt
        let endAngle: CGFloat
        if hasMultiAnchor {
            endAngle = atan2(lastPt.y - preLast.y, lastPt.x - preLast.x)
        } else if let cp = controlPoint {
            endAngle = atan2(lastPt.y - cp.y, lastPt.x - cp.x)
        } else {
            endAngle = atan2(lastPt.y - firstPt.y, lastPt.x - firstPt.x)
        }
        let epx = -sin(endAngle), epy = cos(endAngle)

        // Start angle: direction leaving the tail
        let postFirst = pts.count >= 2 ? pts[1] : lastPt
        let startAngle: CGFloat
        if hasMultiAnchor {
            startAngle = atan2(postFirst.y - firstPt.y, postFirst.x - firstPt.x)
        } else if let cp = controlPoint {
            startAngle = atan2(cp.y - firstPt.y, cp.x - firstPt.x)
        } else {
            startAngle = endAngle
        }
        let spx = -sin(startAngle), spy = cos(startAngle)

        // Sizing — scale everything down when arrow is short
        let sizeScale = min(1.0, max(0.2, totalLen / 120))
        let tailHalf = max(2, strokeWidth * 0.5) * sizeScale
        let shaftHalf = max(4, strokeWidth * 1.5) * sizeScale
        let headHalf = shaftHalf * 2.0
        let headLen = min(totalLen * 0.35, headHalf * 1.8)
        let r: CGFloat = min(headLen * 0.22, headHalf * 0.3)  // corner rounding

        // Head base point
        let headBase = NSPoint(x: lastPt.x - headLen * cos(endAngle),
                               y: lastPt.y - headLen * sin(endAngle))

        // Sample points along the shaft (tail → headBase), offset perpendicular for taper
        // More samples for multi-anchor curves to avoid self-intersection at tight bends
        let steps = hasMultiAnchor ? max(64, pts.count * 32) : 64
        var leftPts: [NSPoint] = []
        var rightPts: [NSPoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let bx, by, tx, ty: CGFloat

            if hasMultiAnchor {
                // Sample a modified curve where the last point is headBase
                var shaftPts = pts
                shaftPts[shaftPts.count - 1] = headBase
                let totalSegs = CGFloat(shaftPts.count - 1)
                let segF = t * totalSegs
                let seg = min(Int(segF), shaftPts.count - 2)
                let lt = segF - CGFloat(seg)
                let p0 = seg > 0 ? shaftPts[seg - 1] : shaftPts[seg]
                let p1 = shaftPts[seg]
                let p2 = shaftPts[seg + 1]
                let p3 = seg + 2 < shaftPts.count ? shaftPts[seg + 2] : shaftPts[seg + 1]
                let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                let u = 1 - lt
                bx = u*u*u*p1.x + 3*u*u*lt*cp1.x + 3*u*lt*lt*cp2.x + lt*lt*lt*p2.x
                by = u*u*u*p1.y + 3*u*u*lt*cp1.y + 3*u*lt*lt*cp2.y + lt*lt*lt*p2.y
                tx = 3*u*u*(cp1.x-p1.x) + 6*u*lt*(cp2.x-cp1.x) + 3*lt*lt*(p2.x-cp2.x)
                ty = 3*u*u*(cp1.y-p1.y) + 6*u*lt*(cp2.y-cp1.y) + 3*lt*lt*(p2.y-cp2.y)
            } else if let cp = controlPoint {
                let mt = 1.0 - t
                bx = mt * mt * firstPt.x + 2 * mt * t * cp.x + t * t * headBase.x
                by = mt * mt * firstPt.y + 2 * mt * t * cp.y + t * t * headBase.y
                tx = 2 * (1 - t) * (cp.x - firstPt.x) + 2 * t * (headBase.x - cp.x)
                ty = 2 * (1 - t) * (cp.y - firstPt.y) + 2 * t * (headBase.y - cp.y)
            } else {
                bx = firstPt.x + t * (headBase.x - firstPt.x)
                by = firstPt.y + t * (headBase.y - firstPt.y)
                tx = headBase.x - firstPt.x
                ty = headBase.y - firstPt.y
            }

            let tLen = max(hypot(tx, ty), 0.001)
            let nx = -ty / tLen, ny = tx / tLen
            let half = tailHalf + (shaftHalf - tailHalf) * t
            leftPts.append(NSPoint(x: bx + nx * half, y: by + ny * half))
            rightPts.append(NSPoint(x: bx - nx * half, y: by - ny * half))
        }

        // Head wing points (the 3 triangle corners)
        let endPoint = lastPt
        let headLeft  = NSPoint(x: headBase.x + epx * headHalf, y: headBase.y + epy * headHalf)
        let headRight = NSPoint(x: headBase.x - epx * headHalf, y: headBase.y - epy * headHalf)
        let shaftLeftEnd  = leftPts.last!
        let shaftRightEnd = rightPts.last!

        // Helper: point along segment from A to B at distance d from A
        func along(_ a: NSPoint, _ b: NSPoint, _ d: CGFloat) -> NSPoint {
            let len = max(hypot(b.x - a.x, b.y - a.y), 0.001)
            let t = min(d / len, 0.45)
            return NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        // Build single unified path
        let path = NSBezierPath()

        // Left shaft edge (tail → head base)
        path.move(to: leftPts[0])
        for p in leftPts.dropFirst() { path.line(to: p) }

        // Corner 1: left wing (shaftLeftEnd → headLeft → endPoint)
        // Approach headLeft from shaft side, curve through headLeft, continue toward tip
        let wL1 = along(headLeft, shaftLeftEnd, r)   // before the corner, on shaft→wing edge
        let wL2 = along(headLeft, endPoint, r)        // after the corner, on wing→tip edge
        path.line(to: wL1)
        path.curve(to: wL2, controlPoint1: headLeft, controlPoint2: headLeft)

        // Corner 2: tip (headLeft → endPoint → headRight)
        let tL = along(endPoint, headLeft, r)         // before tip, on left wing→tip edge
        let tR = along(endPoint, headRight, r)        // after tip, on tip→right wing edge
        path.line(to: tL)
        path.curve(to: tR, controlPoint1: endPoint, controlPoint2: endPoint)

        // Corner 3: right wing (endPoint → headRight → shaftRightEnd)
        let wR1 = along(headRight, endPoint, r)       // before the corner, on tip→wing edge
        let wR2 = along(headRight, shaftRightEnd, r)  // after the corner, on wing→shaft edge
        path.line(to: wR1)
        path.curve(to: wR2, controlPoint1: headRight, controlPoint2: headRight)

        // Right shaft edge (head base → tail)
        path.line(to: shaftRightEnd)
        for p in rightPts.reversed().dropFirst() { path.line(to: p) }

        path.close()

        // Outline: stroke the unified shape behind the fill
        if let oc = outlineColor {
            oc.setStroke()
            path.lineWidth = 6
            path.lineJoinStyle = .round
            path.stroke()
        }

        color.setFill()
        path.fill()
    }
}
