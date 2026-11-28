import Cocoa

@main
struct RegionSnapTests {
    static func main() {
        checkBilibiliMulticolorCoverCard()
        checkXCompositeMediaWithWhiteRightHalfAndThinBorder()
        checkXNestedQuoteCardWith1pxBorder()
        checkWhitespaceGapSuppressesFullPageOverflow()
        checkSidebarHighlightedItem()
        checkSubtleGrayCardBoundary()
        checkWindowClippingBoundary()
        checkAppKitYAxisCoordinates()
        checkTinyNoiseIgnored()
        print("PASS: 区域识别核心算法（含 B 站多色封面、X 1px 边框嵌套卡片、空白溢抑制与 2x 降采样）")
    }

    /// 构造高分屏（支持 scale=2 模拟 Retina 1px CSS 边框）RGBA 测试画布。
    private static func makeBitmap(
        logicalWidth: Int,
        logicalHeight: Int,
        scale: Int = 1,
        background: NSColor,
        draw: (CGContext) -> Void
    ) -> RegionSnapDetector.Bitmap {
        let pxW = logicalWidth * scale
        let pxH = logicalHeight * scale
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: pxW * 4,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.setFillColor(background.usingColorSpace(.sRGB)!.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight))
        draw(ctx)
        let cgImage = ctx.makeImage()!
        return RegionSnapDetector.makeBitmap(
            from: cgImage,
            viewSize: NSSize(width: logicalWidth, height: logicalHeight)
        )!
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
    }

    private static func assertRectApprox(
        _ actual: NSRect?,
        _ expected: NSRect,
        tolerance: CGFloat = 3.0,
        _ message: String
    ) {
        guard let actual else {
            preconditionFailure("\(message): actual is nil, expected \(expected)")
        }
        let ok = abs(actual.minX - expected.minX) <= tolerance
            && abs(actual.minY - expected.minY) <= tolerance
            && abs(actual.width - expected.width) <= tolerance
            && abs(actual.height - expected.height) <= tolerance
        precondition(ok, "\(message): actual=\(actual), expected=\(expected)")
    }

    static func checkBilibiliMulticolorCoverCard() {
        // 模拟 2x Retina 下 B 站搜索网格（#FFFFFF 背景）中的多色高反差封面卡片 + 下方标题。
        let coverRect = NSRect(x: 120, y: 240, width: 260, height: 150)
        let titleRect = NSRect(x: 120, y: 214, width: 220, height: 16)

        let bitmap = makeBitmap(logicalWidth: 900, logicalHeight: 600, scale: 2, background: rgb(255, 255, 255)) { ctx in
            // 左半深蓝，右半亮黄，中心绿色高亮条，右下角黑色时长角标，内部白字
            ctx.setFillColor(rgb(18, 36, 72).cgColor)
            ctx.fill(NSRect(x: coverRect.minX, y: coverRect.minY, width: 135, height: coverRect.height))
            ctx.setFillColor(rgb(255, 208, 0).cgColor)
            ctx.fill(NSRect(x: coverRect.minX + 135, y: coverRect.minY, width: 125, height: coverRect.height))
            ctx.setFillColor(rgb(40, 220, 110).cgColor)
            ctx.fill(NSRect(x: coverRect.minX + 60, y: coverRect.minY + 55, width: 140, height: 34))
            ctx.setFillColor(rgb(15, 15, 15).cgColor)
            ctx.fill(NSRect(x: coverRect.maxX - 48, y: coverRect.minY + 6, width: 42, height: 18))
            // 封面下方隔开 10pt 的黑色标题文字
            ctx.setFillColor(rgb(24, 25, 28).cgColor)
            ctx.fill(titleRect)
        }

        for pt in [
            NSPoint(x: coverRect.minX + 30, y: coverRect.midY),      // 左深蓝
            NSPoint(x: coverRect.maxX - 30, y: coverRect.midY + 20), // 右亮黄
            NSPoint(x: coverRect.midX, y: coverRect.midY),           // 中间荧光绿
            NSPoint(x: coverRect.maxX - 20, y: coverRect.minY + 12), // 右下黑角标
        ] {
            let hit = RegionSnapDetector.target(in: bitmap, atViewPoint: pt, clipRect: nil)
            assertRectApprox(hit?.rect, coverRect, "B 站封面内部点 \(pt) 应完整选中整张封面，不应碎成内部色块")
        }
    }

    static func checkXCompositeMediaWithWhiteRightHalfAndThinBorder() {
        // 模拟 X.com "Black Friday" 合成媒体图：1px #CFD9DE 外边框 + 左侧纯黑/蓝色弧线 + 右侧白底手机截图。
        let mediaRect = NSRect(x: 160, y: 140, width: 520, height: 290)
        let bitmap = makeBitmap(logicalWidth: 900, logicalHeight: 600, scale: 2, background: rgb(255, 255, 255)) { ctx in
            // 先画左半黑底 + 蓝色弧线块
            ctx.setFillColor(rgb(8, 10, 16).cgColor)
            ctx.fill(NSRect(x: mediaRect.minX, y: mediaRect.minY, width: 290, height: mediaRect.height))
            ctx.setFillColor(rgb(36, 118, 255).cgColor)
            ctx.fill(NSRect(x: mediaRect.minX + 40, y: mediaRect.maxY - 90, width: 210, height: 42))
            // 右半白色手机区域 + 手机内灰色卡片
            ctx.setFillColor(rgb(255, 255, 255).cgColor)
            ctx.fill(NSRect(x: mediaRect.minX + 290, y: mediaRect.minY, width: 230, height: mediaRect.height))
            ctx.setFillColor(rgb(235, 240, 248).cgColor)
            ctx.fill(NSRect(x: mediaRect.minX + 330, y: mediaRect.minY + 40, width: 150, height: 200))
            // 最外圈 1pt 浅灰边框（在 2x 下对应 2 物理像素，或更细 0.5pt = 1 物理像素）
            ctx.setStrokeColor(rgb(207, 217, 222).cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(mediaRect.insetBy(dx: 0.5, dy: 0.5))
        }

        let hitBlack = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: mediaRect.minX + 35, y: mediaRect.maxY - 30),
            clipRect: nil
        )
        assertRectApprox(hitBlack?.rect, mediaRect, "合成大图左上角应跨过弧线和 1px 灰框包住整张图")

        let hitBlue = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: mediaRect.minX + 120, y: mediaRect.maxY - 70),
            clipRect: nil
        )
        assertRectApprox(hitBlue?.rect, mediaRect, "合成大图内部蓝色高反差块应合并为整张媒体卡片")
    }

    static func checkXNestedQuoteCardWith1pxBorder() {
        // 模拟 X.com 外层白底推文内嵌 1px 浅灰边框（#CFD9DE）圆角引用卡片，2x 下仅 0.5pt（1 物理像素）线宽！
        let outerTweet = NSRect(x: 150, y: 80, width: 560, height: 420)
        let quoteCard = NSRect(x: 210, y: 140, width: 460, height: 220)
        let textLine = NSRect(x: 230, y: 260, width: 320, height: 14)

        let bitmap = makeBitmap(logicalWidth: 900, logicalHeight: 600, scale: 2, background: rgb(255, 255, 255)) { ctx in
            // 外层推文分割线
            ctx.setFillColor(rgb(239, 243, 244).cgColor)
            ctx.fill(NSRect(x: outerTweet.minX, y: outerTweet.minY, width: outerTweet.width, height: 1))
            ctx.fill(NSRect(x: outerTweet.minX, y: outerTweet.maxY, width: outerTweet.width, height: 1))
            // 内层引用推文：0.5pt（2x 下正好 1 个物理像素宽）#CFD9DE 圆角边框
            ctx.setStrokeColor(rgb(207, 217, 222).cgColor)
            ctx.setLineWidth(0.5)
            let path = CGPath(roundedRect: quoteCard, cornerWidth: 12, cornerHeight: 12, transform: nil)
            ctx.addPath(path)
            ctx.strokePath()
            // 内部黑色文字段落
            ctx.setFillColor(rgb(15, 20, 25).cgColor)
            ctx.fill(textLine)
        }

        // 点在引用框内部白底
        let hitWhite = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: quoteCard.midX, y: quoteCard.minY + 40),
            clipRect: nil
        )
        assertRectApprox(hitWhite?.rect, quoteCard, tolerance: 4.0, "1px 细边框白底引用卡片空白处不应漏水穿透")

        // 点在引用框内部黑色文字上
        let hitText = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: textLine.midX, y: textLine.midY),
            clipRect: nil
        )
        assertRectApprox(hitText?.rect, quoteCard, tolerance: 4.0, "点在引用卡片内部文字上也应选中内层引用卡片而非外层主推文")
    }

    static func checkWhitespaceGapSuppressesFullPageOverflow() {
        // 模拟多张卡片之间的纯白缝隙：不应突然亮出占满整个窗口的大框。
        let bitmap = makeBitmap(logicalWidth: 900, logicalHeight: 600, scale: 1, background: rgb(255, 255, 255)) { ctx in
            ctx.setFillColor(rgb(30, 60, 120).cgColor)
            ctx.fill(NSRect(x: 100, y: 350, width: 240, height: 140))
            ctx.fill(NSRect(x: 380, y: 350, width: 240, height: 140))
        }

        let gapHit = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: 360, y: 400),
            clipRect: nil
        )
        precondition(gapHit == nil, "卡片间大白底间隙不应触发整页大框溢出，实际得到 \(String(describing: gapHit))")
    }

    static func checkSidebarHighlightedItem() {
        // 模拟通栏窄高浅灰侧边栏中的单个高亮选中胶囊。
        let sidebar = NSRect(x: 0, y: 0, width: 220, height: 600)
        let activeItem = NSRect(x: 12, y: 380, width: 196, height: 38)

        let bitmap = makeBitmap(logicalWidth: 900, logicalHeight: 600, scale: 2, background: rgb(255, 255, 255)) { ctx in
            ctx.setFillColor(rgb(244, 245, 247).cgColor)
            ctx.fill(sidebar)
            ctx.setFillColor(rgb(219, 232, 254).cgColor)
            ctx.fill(activeItem)
        }

        let itemHit = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: activeItem.midX, y: activeItem.midY),
            clipRect: nil
        )
        assertRectApprox(itemHit?.rect, activeItem, "侧边栏内高亮选中条目应优先单独识别")
    }

    static func checkSubtleGrayCardBoundary() {
        let cardRect = NSRect(x: 80, y: 80, width: 220, height: 140)
        let bitmap = makeBitmap(logicalWidth: 400, logicalHeight: 300, scale: 1, background: rgb(255, 255, 255)) { ctx in
            ctx.setFillColor(rgb(250, 250, 250).cgColor)
            ctx.fill(cardRect)
        }

        let target = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: 150, y: 150),
            clipRect: nil
        )
        assertRectApprox(target?.rect, cardRect, "#FAFAFA 与 #FFFFFF 之间不应穿通")
    }

    static func checkWindowClippingBoundary() {
        let windowRect = NSRect(x: 120, y: 60, width: 500, height: 400)
        // 卡片横跨了窗口左边界（从 x=60 延伸到 x=280），裁剪后应只保留窗口内的 [120...280]。
        let cardRect = NSRect(x: 60, y: 140, width: 220, height: 160)
        let expectedClipped = cardRect.intersection(windowRect)
        let bitmap = makeBitmap(logicalWidth: 800, logicalHeight: 600, scale: 1, background: rgb(255, 255, 255)) { ctx in
            ctx.setFillColor(rgb(235, 240, 250).cgColor)
            ctx.fill(cardRect)
        }

        let target = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: 200, y: 200),
            clipRect: windowRect
        )
        assertRectApprox(target?.rect, expectedClipped, "区域识别结果应严格裁剪在所属窗口范围内")
    }

    static func checkAppKitYAxisCoordinates() {
        let topLeftRect = NSRect(x: 20, y: 300, width: 120, height: 80)
        let bottomRightRect = NSRect(x: 260, y: 20, width: 100, height: 60)

        let bitmap = makeBitmap(logicalWidth: 400, logicalHeight: 400, scale: 2, background: rgb(255, 255, 255)) { ctx in
            ctx.setFillColor(rgb(230, 240, 255).cgColor)
            ctx.fill(topLeftRect)
            ctx.setFillColor(rgb(255, 235, 220).cgColor)
            ctx.fill(bottomRightRect)
        }

        let topTarget = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: 60, y: 340),
            clipRect: nil
        )
        assertRectApprox(topTarget?.rect, topLeftRect, "左上角区域坐标不应出现 Y 轴翻转")

        let bottomTarget = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: 300, y: 50),
            clipRect: nil
        )
        assertRectApprox(bottomTarget?.rect, bottomRightRect, "右下角区域坐标不应出现 Y 轴翻转")
    }

    static func checkTinyNoiseIgnored() {
        let tinyClip = NSRect(x: 50, y: 50, width: 6, height: 6)
        let bitmap = makeBitmap(logicalWidth: 200, logicalHeight: 200, scale: 1, background: rgb(240, 240, 240)) { _ in }

        let target = RegionSnapDetector.target(
            in: bitmap,
            atViewPoint: NSPoint(x: 53, y: 53),
            clipRect: tinyClip
        )
        precondition(target == nil, "小于最小有效尺寸 10pt 的碎块不应返回命中目标")
    }
}
