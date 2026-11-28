import AppKit

/// 按住辅助键时的屏幕区域识别：
/// 1. 构造 1x 位图时从原始高分屏像素提取无损边缘掩码（保留 1px 细边框并桥接单像素缺口）。
/// 2. 自动估计窗口主背景色，针对「多色封面/媒体卡片」走非背景前景岛屿连通，
///    针对「1px 细边框白底卡片」走边缘墙封闭内腔填充，并抑制纯白大空白区域溢出。
nonisolated enum RegionSnapDetector {
    struct Target: Equatable, Sendable {
        /// 区域在遮罩视图坐标下的矩形。
        let rect: NSRect
    }

    /// 不可变位图 + 无损边缘掩码快照，构建完成后只读，可安全跨线程传递。
    final class Bitmap: @unchecked Sendable {
        let width: Int
        let height: Int
        let viewSize: NSSize
        /// 1x sRGB 像素（RGBA, bytesPerRow = width * 4）。
        let bytes: [UInt8]
        /// 与 1x 像素对齐的高对比边缘墙（0 = 平坦区，1 = 边缘/1px 细线）。
        let edgeMask: [UInt8]

        init(width: Int, height: Int, viewSize: NSSize, bytes: [UInt8], edgeMask: [UInt8]) {
            self.width = width
            self.height = height
            self.viewSize = viewSize
            self.bytes = bytes
            self.edgeMask = edgeMask
        }
    }

    private struct RGB {
        let r: Int
        let g: Int
        let b: Int
    }

    private struct PixelBox {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
        var filledCount: Int

        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var area: Int { width * height }
    }

    private struct ClipBounds {
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int

        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var area: Int { width * height }
    }

    /// 检测内部 1x 位图长边上限。
    private static let maxBitmapDimension: CGFloat = 2200
    /// 原图细线提取临时缓冲区长边上限（Retina 2x 完整保留 1px 边框）。
    private static let maxSourceSampleDimension: CGFloat = 4096

    /// 高分屏子像素块内最大色跨度门限（超过则判定为细线/文字边缘）。
    private static let subpixelEdgeSpanThreshold = 18
    /// 1x 相邻像素跳变门限（单通道或总和）。
    private static let neighborEdgeChannelThreshold = 10
    private static let neighborEdgeManhattanThreshold = 20

    /// 主背景色匹配阈值（可容忍压缩噪点，但能区分 #FFFFFF 与 #F1F2F3 / #F6F8FA）。
    private static let bgMatchChannelThreshold = 7
    private static let bgMatchManhattanThreshold = 16

    /// 同色内腔填充阈值（更严格以防穿墙，同时能区分 #FFFFFF 与 #FAFAFA）。
    private static let cavityChannelThreshold = 5
    private static let cavityManhattanThreshold = 12

    /// 过小连通域（文字笔画/小图标）判定阈值。
    private static let smallForegroundWidth = 26
    private static let smallForegroundHeight = 26
    private static let smallForegroundCount = 400

    /// 最小有效识别矩形（逻辑点）。
    private static let minimumLogicalSize: CGFloat = 10

    /// 从截屏 `CGImage` 构造 1x 位图与无损边缘掩码。
    static func makeBitmap(from cgImage: CGImage, viewSize: NSSize) -> Bitmap? {
        guard viewSize.width >= 1, viewSize.height >= 1 else { return nil }
        let maxViewSide = max(viewSize.width, viewSize.height)
        let scale = maxViewSide > maxBitmapDimension ? maxBitmapDimension / maxViewSide : 1.0
        let width = max(1, Int(round(viewSize.width * scale)))
        let height = max(1, Int(round(viewSize.height * scale)))

        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        // 决定源图像采样缓冲尺寸：当原图分辨率高于 1x 目标时保留原图细节以防 1px 细边框被稀释。
        let rawSrcW = CGFloat(cgImage.width)
        let rawSrcH = CGFloat(cgImage.height)
        let maxRawSide = max(rawSrcW, rawSrcH)
        let srcScale = maxRawSide > maxSourceSampleDimension ? maxSourceSampleDimension / maxRawSide : 1.0
        let srcW = max(width, Int(round(rawSrcW * srcScale)))
        let srcH = max(height, Int(round(rawSrcH * srcScale)))

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var edgeMask = [UInt8](repeating: 0, count: width * height)

        if srcW > width || srcH > height {
            var srcBytes = [UInt8](repeating: 0, count: srcW * srcH * 4)
            let ok = renderRGBA(cgImage: cgImage, width: srcW, height: srcH, colorSpace: srgb, into: &srcBytes)
            guard ok else { return nil }
            downsampleWithEdgePreservation(
                srcBytes: srcBytes, srcW: srcW, srcH: srcH,
                dstW: width, dstH: height,
                dstBytes: &bytes, edgeMask: &edgeMask
            )
        } else {
            let ok = renderRGBA(cgImage: cgImage, width: width, height: height, colorSpace: srgb, into: &bytes)
            guard ok else { return nil }
        }

        augmentNeighborEdgesAndBridgeGaps(bytes: bytes, width: width, height: height, edgeMask: &edgeMask)
        return Bitmap(width: width, height: height, viewSize: viewSize, bytes: bytes, edgeMask: edgeMask)
    }

    private static func renderRGBA(
        cgImage: CGImage,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        into buffer: inout [UInt8]
    ) -> Bool {
        buffer.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let ctx = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
    }

    /// 将高分屏图像映射到 1x 网格：颜色取中心点，边缘掩码取子像素块内最大色差，避免 1px 边框被平均抹淡。
    private static func downsampleWithEdgePreservation(
        srcBytes: [UInt8], srcW: Int, srcH: Int,
        dstW: Int, dstH: Int,
        dstBytes: inout [UInt8], edgeMask: inout [UInt8]
    ) {
        let scaleX = Double(srcW) / Double(dstW)
        let scaleY = Double(srcH) / Double(dstH)

        srcBytes.withUnsafeBufferPointer { srcPtr in
            for dy in 0..<dstH {
                let sy0 = min(srcH - 1, Int(Double(dy) * scaleY))
                let sy1 = max(sy0 + 1, min(srcH, Int(ceil(Double(dy + 1) * scaleY))))
                let midY = min(srcH - 1, (sy0 + sy1 - 1) >> 1)

                for dx in 0..<dstW {
                    let sx0 = min(srcW - 1, Int(Double(dx) * scaleX))
                    let sx1 = max(sx0 + 1, min(srcW, Int(ceil(Double(dx + 1) * scaleX))))
                    let midX = min(srcW - 1, (sx0 + sx1 - 1) >> 1)

                    let centerOff = (midY * srcW + midX) * 4
                    let dstOff = (dy * dstW + dx) * 4
                    dstBytes[dstOff] = srcPtr[centerOff]
                    dstBytes[dstOff + 1] = srcPtr[centerOff + 1]
                    dstBytes[dstOff + 2] = srcPtr[centerOff + 2]
                    dstBytes[dstOff + 3] = srcPtr[centerOff + 3]

                    var minR = 255, maxR = 0
                    var minG = 255, maxG = 0
                    var minB = 255, maxB = 0
                    for sy in sy0..<sy1 {
                        let rowBase = sy * srcW
                        for sx in sx0..<sx1 {
                            let off = (rowBase + sx) * 4
                            let r = Int(srcPtr[off])
                            let g = Int(srcPtr[off + 1])
                            let b = Int(srcPtr[off + 2])
                            if r < minR { minR = r }; if r > maxR { maxR = r }
                            if g < minG { minG = g }; if g > maxG { maxG = g }
                            if b < minB { minB = b }; if b > maxB { maxB = b }
                        }
                    }
                    let span = max(maxR - minR, max(maxG - minG, maxB - minB))
                    if span >= subpixelEdgeSpanThreshold {
                        edgeMask[dy * dstW + dx] = 1
                    }
                }
            }
        }
    }

    /// 补充 1x 相邻像素跳变边界，并桥接正交方向 1px 孤立断口（消除圆角抗锯齿漏水点）。
    private static func augmentNeighborEdgesAndBridgeGaps(
        bytes: [UInt8],
        width: Int,
        height: Int,
        edgeMask: inout [UInt8]
    ) {
        bytes.withUnsafeBufferPointer { ptr in
            for y in 0..<height {
                let row = y * width
                for x in 0..<width {
                    let idx = row + x
                    if edgeMask[idx] != 0 { continue }
                    let off = idx * 4
                    let r = Int(ptr[off])
                    let g = Int(ptr[off + 1])
                    let b = Int(ptr[off + 2])

                    var hasEdge = false
                    if x + 1 < width {
                        let nOff = (idx + 1) * 4
                        let dr = abs(r - Int(ptr[nOff]))
                        let dg = abs(g - Int(ptr[nOff + 1]))
                        let db = abs(b - Int(ptr[nOff + 2]))
                        if max(dr, max(dg, db)) >= neighborEdgeChannelThreshold
                            || (dr + dg + db) >= neighborEdgeManhattanThreshold
                        {
                            hasEdge = true
                        }
                    }
                    if !hasEdge && y + 1 < height {
                        let nOff = (idx + width) * 4
                        let dr = abs(r - Int(ptr[nOff]))
                        let dg = abs(g - Int(ptr[nOff + 1]))
                        let db = abs(b - Int(ptr[nOff + 2]))
                        if max(dr, max(dg, db)) >= neighborEdgeChannelThreshold
                            || (dr + dg + db) >= neighborEdgeManhattanThreshold
                        {
                            hasEdge = true
                        }
                    }
                    if hasEdge {
                        edgeMask[idx] = 1
                    }
                }
            }
        }

        // 只桥接正交两侧都有墙的 1px 单像素缝隙（避免过度加粗导致贴近元素粘连）。
        guard width > 2, height > 2 else { return }
        let snapshot = edgeMask
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let idx = row + x
                if snapshot[idx] != 0 { continue }
                let hBridge = snapshot[idx - 1] != 0 && snapshot[idx + 1] != 0
                let vBridge = snapshot[idx - width] != 0 && snapshot[idx + width] != 0
                if hBridge || vBridge {
                    edgeMask[idx] = 1
                }
            }
        }
    }

    /// 识别 `viewPoint` 所在处的矩形区域；若提供 `clipRect`（底层窗口边界），严格约束在该窗口内。
    static func target(
        in bitmap: Bitmap,
        atViewPoint viewPoint: NSPoint,
        clipRect: NSRect?
    ) -> Target? {
        let w = bitmap.width
        let h = bitmap.height
        let viewW = bitmap.viewSize.width
        let viewH = bitmap.viewSize.height
        guard w > 0, h > 0, viewW > 0, viewH > 0 else { return nil }

        let px = Int((viewPoint.x / viewW) * CGFloat(w))
        let py = Int((1.0 - viewPoint.y / viewH) * CGFloat(h))
        guard px >= 0, px < w, py >= 0, py < h else { return nil }

        let clip = resolveClipBounds(clipRect: clipRect, bitmap: bitmap)
        guard px >= clip.minX, px <= clip.maxX, py >= clip.minY, py <= clip.maxY else {
            return nil
        }

        let bgColor = estimateWindowBackground(in: bitmap, clip: clip)
        var visited = [UInt8](repeating: 0, count: clip.area)
        let cursorOnBackground = matchesColor(
            rgbAt(bitmap, px, py), bgColor,
            channelMax: bgMatchChannelThreshold, manhattanMax: bgMatchManhattanThreshold
        ) && bitmap.edgeMask[py * w + px] == 0

        var chosenBox: PixelBox?

        if !cursorOnBackground {
            // 分支 A：光标在前景区域（B 站彩色封面、X 合成大图、DeepSeek 灰卡片、或卡片内文字/边框）。
            if let fgBox = floodFillForegroundIsland(
                in: bitmap, startX: px, startY: py, bgColor: bgColor, clip: clip, visited: &visited
            ) {
                let fillDensity = Double(fgBox.filledCount) / Double(max(1, fgBox.area))
                let looksLikeSmallTextOrIcon = fgBox.width < smallForegroundWidth
                    || fgBox.height < smallForegroundHeight
                    || fgBox.filledCount < smallForegroundCount
                    || (fgBox.height <= 36 && fgBox.width > fgBox.height * 4)
                    || (fgBox.height <= 64 && fillDensity < 0.48)

                if looksLikeSmallTextOrIcon,
                   let enclosedBox = findSurroundingCavityBox(
                       in: bitmap, around: fgBox, originX: px, originY: py, clip: clip
                   )
                {
                    chosenBox = enclosedBox
                } else if isTallFlatSidebar(fgBox, in: bitmap, clip: clip),
                          let localCapsule = detectLocalUniformItem(
                              in: bitmap, startX: px, startY: py, clip: clip, sidebarBox: fgBox
                          )
                {
                    chosenBox = localCapsule
                } else if !isOverflowBackground(fgBox, bitmap: bitmap, bgColor: bgColor, clip: clip) {
                    chosenBox = fgBox
                }
            }
        } else {
            // 分支 B：光标在平坦背景色上（如带 1px 细边框的白底引用推文卡片、或卡片间隙大白底）。
            if let cavityBox = floodFillEnclosedRegion(
                in: bitmap, startX: px, startY: py, clip: clip, visited: &visited
            ), !isOverflowBackground(cavityBox, bitmap: bitmap, bgColor: bgColor, clip: clip) {
                chosenBox = cavityBox
            }
        }

        guard let finalBox = chosenBox else { return nil }
        let rect = viewRect(from: finalBox, bitmap: bitmap)
        guard rect.width >= minimumLogicalSize, rect.height >= minimumLogicalSize else {
            return nil
        }
        return Target(rect: rect)
    }

    private static func resolveClipBounds(clipRect: NSRect?, bitmap: Bitmap) -> ClipBounds {
        let w = bitmap.width
        let h = bitmap.height
        let viewBounds = NSRect(origin: .zero, size: bitmap.viewSize)
        let effective = (clipRect?.intersection(viewBounds)).flatMap {
            $0.width >= 2 && $0.height >= 2 ? $0 : nil
        } ?? viewBounds

        let minX = max(0, min(w - 1, Int(floor(effective.minX / bitmap.viewSize.width * CGFloat(w)))))
        let maxX = max(minX, min(w - 1, Int(ceil(effective.maxX / bitmap.viewSize.width * CGFloat(w))) - 1))
        let minY = max(0, min(h - 1, Int(floor((1.0 - effective.maxY / bitmap.viewSize.height) * CGFloat(h)))))
        let maxY = max(minY, min(h - 1, Int(ceil((1.0 - effective.minY / bitmap.viewSize.height) * CGFloat(h))) - 1))
        return ClipBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private static func viewRect(from box: PixelBox, bitmap: Bitmap) -> NSRect {
        let w = CGFloat(bitmap.width)
        let h = CGFloat(bitmap.height)
        let viewW = bitmap.viewSize.width
        let viewH = bitmap.viewSize.height

        let x = CGFloat(box.minX) / w * viewW
        let width = CGFloat(box.width) / w * viewW
        let y = (1.0 - CGFloat(box.maxY + 1) / h) * viewH
        let height = CGFloat(box.height) / h * viewH
        return NSRect(x: x, y: y, width: width, height: height)
            .intersection(NSRect(origin: .zero, size: bitmap.viewSize))
    }

    @inline(__always)
    private static func rgbAt(_ bitmap: Bitmap, _ x: Int, _ y: Int) -> RGB {
        let off = (y * bitmap.width + x) * 4
        return RGB(
            r: Int(bitmap.bytes[off]),
            g: Int(bitmap.bytes[off + 1]),
            b: Int(bitmap.bytes[off + 2])
        )
    }

    @inline(__always)
    private static func matchesColor(
        _ a: RGB,
        _ b: RGB,
        channelMax: Int,
        manhattanMax: Int
    ) -> Bool {
        let dr = abs(a.r - b.r)
        let dg = abs(a.g - b.g)
        let db = abs(a.b - b.b)
        return dr <= channelMax && dg <= channelMax && db <= channelMax
            && (dr + dg + db) <= manhattanMax
    }

    /// 统计窗口内平坦区域的最高频颜色，作为网页/应用主背景色。
    private static func estimateWindowBackground(in bitmap: Bitmap, clip: ClipBounds) -> RGB {
        let step = max(4, min(clip.width, clip.height) / 96)
        var counts: [Int: (count: Int, sumR: Int, sumG: Int, sumB: Int)] = [:]
        counts.reserveCapacity(64)

        var y = clip.minY + 1
        while y < clip.maxY {
            var x = clip.minX + 1
            while x < clip.maxX {
                let idx = y * bitmap.width + x
                if bitmap.edgeMask[idx] == 0 {
                    let c = rgbAt(bitmap, x, y)
                    let key = ((c.r >> 3) << 10) | ((c.g >> 3) << 5) | (c.b >> 3)
                    if var entry = counts[key] {
                        entry.count += 1
                        entry.sumR += c.r
                        entry.sumG += c.g
                        entry.sumB += c.b
                        counts[key] = entry
                    } else {
                        counts[key] = (1, c.r, c.g, c.b)
                    }
                }
                x += step
            }
            y += step
        }

        if let best = counts.values.max(by: { $0.count < $1.count }), best.count > 0 {
            return RGB(
                r: best.sumR / best.count,
                g: best.sumG / best.count,
                b: best.sumB / best.count
            )
        }
        return RGB(r: 255, g: 255, b: 255)
    }

    /// 非背景前景岛屿扫描线填充：忽略内部色彩切换与纹理边界，仅在遇到平坦主背景区时停止。
    private static func floodFillForegroundIsland(
        in bitmap: Bitmap,
        startX: Int,
        startY: Int,
        bgColor: RGB,
        clip: ClipBounds,
        visited: inout [UInt8]
    ) -> PixelBox? {
        let w = bitmap.width

        @inline(__always)
        func isForeground(_ x: Int, _ y: Int) -> Bool {
            let idx = y * w + x
            if bitmap.edgeMask[idx] != 0 { return true }
            let c = rgbAt(bitmap, x, y)
            return !matchesColor(
                c, bgColor,
                channelMax: bgMatchChannelThreshold,
                manhattanMax: bgMatchManhattanThreshold
            )
        }

        return spanFloodFill(
            startX: startX, startY: startY, clip: clip, visited: &visited, canEnter: isForeground
        )
    }

    /// 带边缘墙阻挡的同色内腔扫描线填充：用于识别带 1px 细边框的白底/同色卡片，绝不从圆角抗锯齿漏出。
    private static func floodFillEnclosedRegion(
        in bitmap: Bitmap,
        startX: Int,
        startY: Int,
        clip: ClipBounds,
        visited: inout [UInt8]
    ) -> PixelBox? {
        let w = bitmap.width
        let seed = rgbAt(bitmap, startX, startY)

        @inline(__always)
        func isEnclosedMatch(_ x: Int, _ y: Int) -> Bool {
            let idx = y * w + x
            if bitmap.edgeMask[idx] != 0 { return false }
            let c = rgbAt(bitmap, x, y)
            return matchesColor(
                c, seed,
                channelMax: cavityChannelThreshold,
                manhattanMax: cavityManhattanThreshold
            )
        }

        return spanFloodFill(
            startX: startX, startY: startY, clip: clip, visited: &visited, canEnter: isEnclosedMatch
        )
    }

    /// 光标落在白底卡片内文字上时，探测紧邻白底并检查是否存在闭合外框卡片（如引用推文卡片）。
    private static func findSurroundingCavityBox(
        in bitmap: Bitmap,
        around smallBox: PixelBox,
        originX: Int,
        originY: Int,
        clip: ClipBounds
    ) -> PixelBox? {
        let w = bitmap.width
        let offsets = [2, 5, 10]
        var localVisited = [UInt8](repeating: 0, count: clip.area)
        var best: PixelBox?
        var attempts = 0

        for offset in offsets {
            let midX = (smallBox.minX + smallBox.maxX) >> 1
            let candidates = [
                (originX, smallBox.minY - offset),
                (originX, smallBox.maxY + offset),
                (midX, smallBox.minY - offset),
                (midX, smallBox.maxY + offset),
                (smallBox.minX - offset, originY),
                (smallBox.maxX + offset, originY),
            ]
            for (cx, cy) in candidates {
                guard cx >= clip.minX, cx <= clip.maxX, cy >= clip.minY, cy <= clip.maxY else { continue }
                let idx = cy * w + cx
                if bitmap.edgeMask[idx] != 0 { continue }
                let localIdx = (cy - clip.minY) * clip.width + (cx - clip.minX)
                if localVisited[localIdx] != 0 { continue }

                attempts += 1
                if attempts > 6 { break }

                guard let box = floodFillEnclosedRegion(
                    in: bitmap, startX: cx, startY: cy, clip: clip, visited: &localVisited
                ) else { continue }

                // 允许内腔白底比含边框的前景元素少 2px 边框厚度。
                let containsSmall = box.minX <= smallBox.minX + 3
                    && box.maxX >= smallBox.maxX - 3
                    && box.minY <= smallBox.minY + 3
                    && box.maxY >= smallBox.maxY - 3
                guard containsSmall,
                      box.width >= 36,
                      box.height >= 36,
                      box.area > smallBox.area + smallBox.area / 2,
                      Double(box.area) <= Double(clip.area) * 0.55
                else { continue }

                if let current = best {
                    if box.filledCount > current.filledCount { best = box }
                } else {
                    best = box
                }
            }
            if attempts > 6 { break }
        }
        return best
    }

    /// 判定是否为通栏窄高平坦侧边栏（如 DeepSeek 历史会话栏、Edge 垂直标签栏）。
    private static func isTallFlatSidebar(_ box: PixelBox, in bitmap: Bitmap, clip: ClipBounds) -> Bool {
        let heightRatio = Double(box.height) / Double(max(1, clip.height))
        let widthRatio = Double(box.width) / Double(max(1, clip.width))
        return heightRatio >= 0.72 && widthRatio <= 0.32 && box.width >= 100
    }

    /// 在通栏侧边栏内尝试识别独立的局部同色胶囊条目（如当前高亮会话）。
    private static func detectLocalUniformItem(
        in bitmap: Bitmap,
        startX: Int,
        startY: Int,
        clip: ClipBounds,
        sidebarBox: PixelBox
    ) -> PixelBox? {
        var localVisited = [UInt8](repeating: 0, count: clip.area)
        guard let item = floodFillEnclosedRegion(
            in: bitmap, startX: startX, startY: startY, clip: clip, visited: &localVisited
        ) else { return nil }

        guard item.width >= 60,
              item.height >= 20,
              item.height <= 96,
              item.width <= sidebarBox.width,
              item.area < sidebarBox.area / 3
        else { return nil }
        return item
    }

    /// 过滤空白间隙溢出的大背景网格容器，避免鼠标滑过卡片间隙时突然闪出全屏级选框。
    private static func isOverflowBackground(
        _ box: PixelBox,
        bitmap: Bitmap,
        bgColor: RGB,
        clip: ClipBounds
    ) -> Bool {
        let areaRatio = Double(box.area) / Double(max(1, clip.area))
        let widthRatio = Double(box.width) / Double(max(1, clip.width))
        let heightRatio = Double(box.height) / Double(max(1, clip.height))

        if widthRatio > 0.88 && heightRatio > 0.78 {
            return true
        }
        if areaRatio > 0.55 {
            // 抽样判断箱体内部是否大多是主背景色；如果是纯背景连通网则抑制。
            let stepX = max(4, box.width / 12)
            let stepY = max(4, box.height / 12)
            var total = 0
            var bgHits = 0
            var y = box.minY
            while y <= box.maxY {
                var x = box.minX
                while x <= box.maxX {
                    total += 1
                    if matchesColor(
                        rgbAt(bitmap, x, y), bgColor,
                        channelMax: bgMatchChannelThreshold,
                        manhattanMax: bgMatchManhattanThreshold
                    ) {
                        bgHits += 1
                    }
                    x += stepX
                }
                y += stepY
            }
            if total > 0 && Double(bgHits) / Double(total) >= 0.45 {
                return true
            }
        }
        return false
    }

    /// 通用扫描线连通域填充核心循环。
    private static func spanFloodFill(
        startX: Int,
        startY: Int,
        clip: ClipBounds,
        visited: inout [UInt8],
        canEnter: (Int, Int) -> Bool
    ) -> PixelBox? {
        let clipW = clip.width

        @inline(__always)
        func canFill(_ x: Int, _ y: Int) -> Bool {
            let localIdx = (y - clip.minY) * clipW + (x - clip.minX)
            return visited[localIdx] == 0 && canEnter(x, y)
        }

        guard canFill(startX, startY) else { return nil }

        var box = PixelBox(
            minX: startX, maxX: startX, minY: startY, maxY: startY, filledCount: 0
        )

        var stack: [(x: Int, y: Int)] = []
        stack.reserveCapacity(512)
        stack.append((startX, startY))

        while let item = stack.popLast() {
            let y = item.y
            let seedX = item.x
            if !canFill(seedX, y) { continue }

            var left = seedX
            while left > clip.minX && canFill(left - 1, y) {
                left -= 1
            }

            var right = seedX
            while right < clip.maxX && canFill(right + 1, y) {
                right += 1
            }

            let rowOffset = (y - clip.minY) * clipW - clip.minX
            for x in left...right {
                visited[rowOffset + x] = 1
            }

            box.minX = min(box.minX, left)
            box.maxX = max(box.maxX, right)
            box.minY = min(box.minY, y)
            box.maxY = max(box.maxY, y)
            box.filledCount += right - left + 1

            for ny in [y - 1, y + 1] {
                guard ny >= clip.minY, ny <= clip.maxY else { continue }
                var x = left
                var inSpan = false
                while x <= right {
                    if canFill(x, ny) {
                        if !inSpan {
                            stack.append((x, ny))
                            inSpan = true
                        }
                    } else {
                        inSpan = false
                    }
                    x += 1
                }
            }
        }

        return box.filledCount > 0 ? box : nil
    }
}
