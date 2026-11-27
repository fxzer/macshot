//
//  ToolOptionsRowView+SegmentImages.swift
//  macshot
//
//  线型、箭头样式、形状填充分段控件的预览图绘制。
//

import Cocoa

extension ToolOptionsRowView {

    // MARK: - Segment preview images

    static func lineStyleImage(_ style: LineStyle) -> NSImage {
        let size = NSSize(width: 28, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            path.lineWidth = 2
            path.lineCapStyle = .round
            style.apply(to: path)
            ToolbarLayout.iconColor.setStroke()
            path.move(to: NSPoint(x: 4, y: size.height / 2))
            path.line(to: NSPoint(x: size.width - 4, y: size.height / 2))
            path.stroke()
            return true
        }
    }

    static func arrowStyleImage(_ style: ArrowStyle) -> NSImage {
        let size = NSSize(width: 24, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let mid = size.height / 2
            let from = NSPoint(x: 3, y: mid)
            let to = NSPoint(x: size.width - 3, y: mid)
            ToolbarLayout.iconColor.setStroke()
            ToolbarLayout.iconColor.setFill()

            switch style {
            case .single:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                head.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                head.close()
                head.fill()
            case .thick:
                let path = NSBezierPath()
                path.lineWidth = 2.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 6, y: mid))
                path.stroke()
                let headHalf: CGFloat = 3.5
                let headBase = NSPoint(x: to.x - 5, y: mid)
                let head = NSBezierPath()
                head.move(to: from)
                head.line(to: NSPoint(x: headBase.x, y: mid - headHalf))
                head.line(to: to)
                head.line(to: NSPoint(x: headBase.x, y: mid + headHalf))
                head.close()
                head.fill()
            case .double:
                let headLen: CGFloat = 4
                let angle: CGFloat = .pi / 6
                let s1 = NSPoint(x: from.x + headLen * cos(angle), y: from.y + headLen * sin(angle))
                let s2 = NSPoint(x: from.x + headLen * cos(-angle), y: from.y + headLen * sin(-angle))
                let sh = NSBezierPath()
                sh.move(to: from)
                sh.line(to: s1)
                sh.line(to: s2)
                sh.close()
                sh.fill()
                let e1 = NSPoint(x: to.x - headLen * cos(angle), y: to.y - headLen * sin(angle))
                let e2 = NSPoint(x: to.x - headLen * cos(-angle), y: to.y - headLen * sin(-angle))
                let eh = NSBezierPath()
                eh.move(to: to)
                eh.line(to: e1)
                eh.line(to: e2)
                eh.close()
                eh.fill()
                let shaft = NSBezierPath()
                shaft.lineWidth = 1.5
                shaft.move(to: from)
                shaft.line(to: to)
                shaft.stroke()
            case .open:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4.5, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.lineWidth = 1.5
                head.lineCapStyle = .round
                head.lineJoinStyle = .round
                head.move(to: NSPoint(x: to.x - 4.5, y: mid + 3))
                head.line(to: to)
                head.line(to: NSPoint(x: to.x - 4.5, y: mid - 3))
                head.stroke()
            case .tail:
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.move(to: from)
                path.line(to: NSPoint(x: to.x - 4, y: mid))
                path.stroke()
                let head = NSBezierPath()
                head.move(to: to)
                head.line(to: NSPoint(x: to.x - 5, y: mid + 3))
                head.line(to: NSPoint(x: to.x - 5, y: mid - 3))
                head.close()
                head.fill()
                let tailR: CGFloat = 2.5
                NSBezierPath(ovalIn: NSRect(x: from.x - tailR, y: mid - tailR, width: tailR * 2, height: tailR * 2)).fill()
            }
            return true
        }
    }

    static func shapeFillImage(_ style: RectFillStyle, oval: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        return NSImage(size: size, flipped: false) { _ in
            let inset: CGFloat = 2
            let rect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            let path = oval ? NSBezierPath(ovalIn: rect) : NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            ToolbarLayout.iconColor.setStroke()
            path.lineWidth = 1.5
            switch style {
            case .stroke:
                path.stroke()
            case .strokeAndFill:
                path.stroke()
                ToolbarLayout.iconColor.withAlphaComponent(RectFillStyle.strokeAndFillOpacity).setFill()
                path.fill()
            case .fill:
                ToolbarLayout.iconColor.setFill()
                path.fill()
            }
            return true
        }
    }
}
