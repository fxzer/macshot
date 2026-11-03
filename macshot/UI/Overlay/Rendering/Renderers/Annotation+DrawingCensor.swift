import Cocoa
import CoreImage

// MARK: - Censor/Blur/Pixelate Drawing

extension Annotation {

    // MARK: - Pixelate

    /// Bake the processed image from source, then release the source screenshot reference.
    /// Called once when the annotation is finalized (mouseUp).
    func bakePixelate() {
        // Legacy blur annotations + unified pixelate tool
        guard (tool == .pixelate || tool == .blur), bakedBlurNSImage == nil else { return }
        if tool == .blur { censorMode = .blur }

        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return }

        switch censorMode {
        case .solid:
            bakedBlurNSImage = bakeSolid()
            sourceImage = nil

        case .erase:
            bakedBlurNSImage = bakeErase()
            sourceImage = nil

        case .blur:
            bakedBlurNSImage = bakeBlur()
            sourceImage = nil

        case .pixelate:
            bakedBlurNSImage = bakeMosaic()
            sourceImage = nil
        }
    }

    /// Unified censor drawing — dispatches based on censorMode.
    func drawCensor(in context: NSGraphicsContext) {
        let rect = boundingRect
        guard rect.width > 4, rect.height > 4 else { return }

        // Baked (finalized) — draw the result
        if let baked = bakedBlurNSImage {
            baked.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }

        // Live preview while drawing (内敛优雅的半透明指示，不遮挡画面)
        switch censorMode {
        case .pixelate:
            NSColor.black.withAlphaComponent(0.28).setFill()
            NSBezierPath(rect: rect).fill()
        case .blur:
            NSColor.white.withAlphaComponent(0.32).setFill()
            NSBezierPath(rect: rect).fill()
        case .solid, .erase:
            NSColor(white: 0.5, alpha: 0.22).setFill()
            NSBezierPath(rect: rect).fill()
        }

        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        let pattern: [CGFloat] = [4, 4]
        border.setLineDash(pattern, count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        border.stroke()
    }

    // MARK: - Specialized Bakes

    /// Solid mode: 智能提取选区外围背景色填充，彻底告别黄色/黑色补丁。
    fileprivate func bakeSolid() -> NSImage? {
        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return nil }

        // 如果能采样到外围真实背景色，使用智能提取的背景色；否则回退到 self.color
        let fillColor = sampleDominantBackgroundColor() ?? self.color

        let scale = sourceImage.map { ImageRasterizer.pixelScale(of: $0) } ?? 2.0
        let pxW = max(1, Int((rect.width * scale).rounded()))
        let pxH = max(1, Int((rect.height * scale).rounded()))

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.setFillColor(fillColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: rect.size)
    }

    /// Erase mode: PS 级智能无痕背景消除。
    /// 采样外围环形背景带，剔除文字高对比度笔画噪点，纯色底直接无痕平涂，渐变底双线性去噪插值。
    fileprivate func bakeErase() -> NSImage? {
        guard sourceImage != nil else { return nil }
        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return nil }

        let samplePad: CGFloat = 6
        let sampleRect = NSRect(
            x: rect.minX - samplePad, y: rect.minY - samplePad,
            width: rect.width + samplePad * 2, height: rect.height + samplePad * 2)

        guard let regionImage = cropRegion(rect: sampleRect),
              let cgImage = regionImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        let bmpW = bitmap.pixelsWide, bmpH = bitmap.pixelsHigh
        guard bmpW > 4, bmpH > 4 else { return nil }

        let scaleX = CGFloat(bmpW) / sampleRect.width
        let scaleY = CGFloat(bmpH) / sampleRect.height
        let ix = Int(samplePad * scaleX)
        let iy = Int(samplePad * scaleY)
        let iw = Int(rect.width * scaleX)
        let ih = Int(rect.height * scaleY)
        guard iw > 0, ih > 0 else { return nil }

        func samplePixel(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            let cx = max(0, min(bmpW - 1, x))
            let cy = max(0, min(bmpH - 1, y))
            var pixel: [Int] = [0, 0, 0, 0]
            bitmap.getPixel(&pixel, atX: cx, y: cy)
            return (CGFloat(pixel[0]) / 255.0, CGFloat(pixel[1]) / 255.0, CGFloat(pixel[2]) / 255.0)
        }

        // 收集所有外围像素用于计算整体背景主色与抗噪基准
        var allBorderPixels: [(r: CGFloat, g: CGFloat, b: CGFloat)] = []
        let padX = max(1, Int(samplePad * scaleX * 0.75))
        let padY = max(1, Int(samplePad * scaleY * 0.75))

        for row in 0..<ih {
            let sy = iy + row
            for d in 1...padX {
                allBorderPixels.append(samplePixel(ix - d, sy))
                allBorderPixels.append(samplePixel(ix + iw - 1 + d, sy))
            }
        }
        for col in 0..<iw {
            let sx = ix + col
            for d in 1...padY {
                allBorderPixels.append(samplePixel(sx, iy - d))
                allBorderPixels.append(samplePixel(sx, iy + ih - 1 + d))
            }
        }

        guard !allBorderPixels.isEmpty else { return nil }

        // 计算亮度中位数（排除对比度高的文字噪点）
        let sortedByLum = allBorderPixels.sorted {
            (0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b) < (0.299 * $1.r + 0.587 * $1.g + 0.114 * $1.b)
        }
        let medPixel = sortedByLum[sortedByLum.count / 2]

        // 过滤掉色差过大的异常点（比如黑字、深色笔画噪点）
        let cleanPixels = allBorderPixels.filter { p in
            let dr = p.r - medPixel.r
            let dg = p.g - medPixel.g
            let db = p.b - medPixel.b
            return (dr * dr + dg * dg + db * db) < 0.04
        }
        let effectivePixels = cleanPixels.isEmpty ? [medPixel] : cleanPixels

        let avgR = effectivePixels.map(\.r).reduce(0, +) / CGFloat(effectivePixels.count)
        let avgG = effectivePixels.map(\.g).reduce(0, +) / CGFloat(effectivePixels.count)
        let avgB = effectivePixels.map(\.b).reduce(0, +) / CGFloat(effectivePixels.count)
        let baselineBg = (r: avgR, g: avgG, b: avgB)

        // 判断是否有明显渐变（计算有效像素的最大方差/色差）
        var maxDelta: CGFloat = 0
        for p in effectivePixels {
            let dr = abs(p.r - avgR), dg = abs(p.g - avgG), db = abs(p.b - avgB)
            maxDelta = max(maxDelta, max(dr, max(dg, db)))
        }

        let outW = iw, outH = ih
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: outW * 4,
            space: cs, bitmapInfo: bitmapInfo
        ),
        let outData = ctx.data else { return nil }
        let outPtr = outData.bindMemory(to: UInt8.self, capacity: outW * outH * 4)

        // 如果是平坦纯色底（日常截图 90% 场景）：直接用最纯净的背景中位数色填充！
        if maxDelta < 0.035 {
            let rByte = UInt8(max(0, min(255, baselineBg.r * 255.0)))
            let gByte = UInt8(max(0, min(255, baselineBg.g * 255.0)))
            let bByte = UInt8(max(0, min(255, baselineBg.b * 255.0)))
            for i in 0..<(outW * outH) {
                let off = i * 4
                outPtr[off]   = rByte
                outPtr[off+1] = gByte
                outPtr[off+2] = bByte
                outPtr[off+3] = 255
            }
        } else {
            // 渐变底：对每行每列进行抗噪去畸变插值
            func cleanSample(pixels: [(r: CGFloat, g: CGFloat, b: CGFloat)]) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
                let valid = pixels.filter { p in
                    let dr = p.r - baselineBg.r, dg = p.g - baselineBg.g, db = p.b - baselineBg.b
                    return (dr * dr + dg * dg + db * db) < 0.05
                }
                if valid.isEmpty { return baselineBg }
                return (
                    valid.map(\.r).reduce(0, +) / CGFloat(valid.count),
                    valid.map(\.g).reduce(0, +) / CGFloat(valid.count),
                    valid.map(\.b).reduce(0, +) / CGFloat(valid.count)
                )
            }

            var leftColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
            var rightColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
            for row in 0..<ih {
                let sy = iy + row
                var lp = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
                var rp = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
                for d in 1...padX {
                    lp.append(samplePixel(ix - d, sy))
                    rp.append(samplePixel(ix + iw - 1 + d, sy))
                }
                leftColors.append(cleanSample(pixels: lp))
                rightColors.append(cleanSample(pixels: rp))
            }

            var bottomColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
            var topColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
            for col in 0..<iw {
                let sx = ix + col
                var bp = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
                var tp = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
                for d in 1...padY {
                    bp.append(samplePixel(sx, iy - d))
                    tp.append(samplePixel(sx, iy + ih - 1 + d))
                }
                bottomColors.append(cleanSample(pixels: bp))
                topColors.append(cleanSample(pixels: tp))
            }

            for row in 0..<outH {
                let ty = CGFloat(row) / max(1, CGFloat(outH - 1))
                let lc = leftColors[row], rc = rightColors[row]
                for col in 0..<outW {
                    let tx = CGFloat(col) / max(1, CGFloat(outW - 1))
                    let tc = topColors[col], bc = bottomColors[col]
                    let hr = lc.r + (rc.r - lc.r) * tx
                    let hg = lc.g + (rc.g - lc.g) * tx
                    let hb = lc.b + (rc.b - lc.b) * tx
                    let vr = bc.r + (tc.r - bc.r) * ty
                    let vg = bc.g + (tc.g - bc.g) * ty
                    let vb = bc.b + (tc.b - bc.b) * ty
                    let off = (row * outW + col) * 4
                    outPtr[off]   = UInt8(max(0, min(255, (hr + vr) * 0.5 * 255.0)))
                    outPtr[off+1] = UInt8(max(0, min(255, (hg + vg) * 0.5 * 255.0)))
                    outPtr[off+2] = UInt8(max(0, min(255, (hb + vb) * 0.5 * 255.0)))
                    outPtr[off+3] = 255
                }
            }
        }

        guard let resultCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: resultCG, size: rect.size)
    }

    /// Blur mode: 参考 Snapzy 的 Padding 外扩采样高斯模糊算法，彻底消除黑边与接缝拉伸。
    fileprivate func bakeBlur() -> NSImage? {
        guard let sourceImg = sourceImage else { return nil }
        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return nil }

        let shortSide = min(rect.width, rect.height)
        let radius = max(14.0, min(shortSide * 0.28, 48.0))
        let padding = ceil(radius * 2.0)
        let sampleRect = rect.insetBy(dx: -padding, dy: -padding)

        guard let paddedRegionImage = cropRegion(rect: sampleRect),
              let paddedCG = paddedRegionImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let scale = ImageRasterizer.pixelScale(of: sourceImg)
        let ciImage = CIImage(cgImage: paddedCG)

        guard let clamp = CIFilter(name: "CIAffineClamp") else { return nil }
        clamp.setValue(ciImage, forKey: kCIInputImageKey)
        clamp.setValue(NSAffineTransform(), forKey: kCIInputTransformKey)
        guard let clamped = clamp.outputImage else { return nil }

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(radius * scale, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage else { return nil }

        // 精确裁切出原选区在 sampleRect 内部的相对位置
        let cropX = (rect.minX - sampleRect.minX) * scale
        let cropY = (rect.minY - sampleRect.minY) * scale
        let cropW = rect.width * scale
        let cropH = rect.height * scale
        let outputRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)

        guard let blurredCG = Annotation.ciContext.createCGImage(
            output, from: outputRect, format: .RGBA8, colorSpace: paddedCG.colorSpace
        ) else { return nil }

        return NSImage(cgImage: blurredCG, size: rect.size)
    }

    /// Pixelate mode: 自适应视觉网格马赛克（两阶段高保真渲染），解决小区域坍缩和大区域粗糙。
    fileprivate func bakeMosaic() -> NSImage? {
        guard let sourceImg = sourceImage, let regionImage = cropRegionFromSource() else { return nil }
        let rect = boundingRect
        guard rect.width > 2, rect.height > 2,
              let cgImage = regionImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        // 自适应视觉网格大小：小文字约 8pt~10pt，大图约 12pt~14pt
        let blockPt: CGFloat = max(8.0, min(14.0, min(rect.width, rect.height) * 0.22))
        let cols = max(3, Int(round(rect.width / blockPt)))
        let rows = max(2, Int(round(rect.height / blockPt)))
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        // 阶段 1：高质量均值下采样，提取最具代表性的块均色
        guard let ctx1 = CGContext(
            data: nil, width: cols, height: rows,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx1.interpolationQuality = .high
        ctx1.draw(cgImage, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        guard let tinyCG = ctx1.makeImage() else { return nil }

        // 阶段 2：Nearest-Neighbor 锋利上采样放回 native 分辨率
        let bakeScale = ImageRasterizer.pixelScale(of: sourceImg)
        let finalW = max(1, Int((rect.width * bakeScale).rounded()))
        let finalH = max(1, Int((rect.height * bakeScale).rounded()))
        guard let ctx2 = CGContext(
            data: nil, width: finalW, height: finalH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx2.interpolationQuality = .none
        ctx2.draw(tinyCG, in: CGRect(x: 0, y: 0, width: finalW, height: finalH))

        guard let pixelatedCG = ctx2.makeImage() else { return nil }
        return NSImage(cgImage: pixelatedCG, size: rect.size)
    }

    /// 从选区外围环形带采样并剔除噪点，提取真实背景主色
    fileprivate func sampleDominantBackgroundColor() -> NSColor? {
        guard sourceImage != nil else { return nil }
        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return nil }

        let samplePad: CGFloat = 6
        let sampleRect = NSRect(
            x: rect.minX - samplePad, y: rect.minY - samplePad,
            width: rect.width + samplePad * 2, height: rect.height + samplePad * 2)

        guard let regionImage = cropRegion(rect: sampleRect),
              let cgImage = regionImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        let bmpW = bitmap.pixelsWide, bmpH = bitmap.pixelsHigh
        guard bmpW > 4, bmpH > 4 else { return nil }

        let scaleX = CGFloat(bmpW) / sampleRect.width
        let scaleY = CGFloat(bmpH) / sampleRect.height
        let ix = Int(samplePad * scaleX)
        let iy = Int(samplePad * scaleY)
        let iw = Int(rect.width * scaleX)
        let ih = Int(rect.height * scaleY)
        guard iw > 0, ih > 0 else { return nil }

        var borderSamples: [(r: CGFloat, g: CGFloat, b: CGFloat)] = []
        func sample(_ x: Int, _ y: Int) {
            let cx = max(0, min(bmpW - 1, x))
            let cy = max(0, min(bmpH - 1, y))
            var p: [Int] = [0, 0, 0, 0]
            bitmap.getPixel(&p, atX: cx, y: cy)
            borderSamples.append((CGFloat(p[0]) / 255.0, CGFloat(p[1]) / 255.0, CGFloat(p[2]) / 255.0))
        }

        let padX = max(1, Int(samplePad * scaleX * 0.75))
        let padY = max(1, Int(samplePad * scaleY * 0.75))
        for row in 0..<ih {
            let sy = iy + row
            for d in 1...padX {
                sample(ix - d, sy)
                sample(ix + iw - 1 + d, sy)
            }
        }
        for col in 0..<iw {
            let sx = ix + col
            for d in 1...padY {
                sample(sx, iy - d)
                sample(sx, iy + ih - 1 + d)
            }
        }

        guard !borderSamples.isEmpty else { return nil }
        let sorted = borderSamples.sorted {
            (0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b) < (0.299 * $1.r + 0.587 * $1.g + 0.114 * $1.b)
        }
        let med = sorted[sorted.count / 2]
        let clean = borderSamples.filter {
            let dr = $0.r - med.r, dg = $0.g - med.g, db = $0.b - med.b
            return (dr * dr + dg * dg + db * db) < 0.04
        }
        let finalSet = clean.isEmpty ? [med] : clean
        let r = finalSet.map(\.r).reduce(0, +) / CGFloat(finalSet.count)
        let g = finalSet.map(\.g).reduce(0, +) / CGFloat(finalSet.count)
        let b = finalSet.map(\.b).reduce(0, +) / CGFloat(finalSet.count)
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Shared CIContext — uses the canonical context from BeautifyRenderer.
    static var ciContext: CIContext { BeautifyRenderer.sharedCIContext }

    // MARK: - Shared region crop

    /// Render a source image region into a new rasterized NSImage at native pixel scale.
    fileprivate func cropRegion(rect: NSRect) -> NSImage? {
        guard let sourceImage = sourceImage else { return nil }
        guard rect.width > 2, rect.height > 2 else { return nil }

        let srcBounds = sourceImageBounds
        let scale = ImageRasterizer.pixelScale(of: sourceImage)
        let pxW = max(1, Int((rect.width * scale).rounded()))
        let pxH = max(1, Int((rect.height * scale).rounded()))
        let cs = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?.colorSpace
            ?? CGColorSpaceCreateDeviceRGB()
        guard let cgCtx = CGContext(
            data: nil, width: pxW, height: pxH,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cgCtx.scaleBy(x: scale, y: scale)
        cgCtx.translateBy(x: -rect.minX, y: -rect.minY)
        let nsContext = NSGraphicsContext(cgContext: cgCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        sourceImage.draw(
            in: NSRect(origin: .zero, size: srcBounds.size),
            from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = cgCtx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: rect.size)
    }

    /// Render the source image region matching boundingRect into a new NSImage.
    fileprivate func cropRegionFromSource() -> NSImage? {
        cropRegion(rect: boundingRect)
    }
}
