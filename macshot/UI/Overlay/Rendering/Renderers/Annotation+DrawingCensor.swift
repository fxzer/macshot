import Cocoa
import Vision

// MARK: - Censor/Blur/Pixelate Drawing

extension Annotation {

    // MARK: - Pixelate

    /// Bake the processed image from source, then release the source screenshot reference.
    /// Called once when the annotation is finalized (mouseUp).
    func bakePixelate() {
        // Legacy blur annotations + unified pixelate tool
        guard (tool == .pixelate || tool == .blur), bakedBlurNSImage == nil else { return }
        // Legacy .blur tool → set censorMode so drawing dispatches correctly
        if tool == .blur { censorMode = .blur }

        let mode = censorMode
        let rect = boundingRect

        if censorDrawScope == .textOnly, let textOnlyImage = bakeTextOnlyCensor() {
            bakedBlurNSImage = textOnlyImage
            return
        }

        // Solid mode: no source image needed — just a filled rect
        if mode == .solid {
            let img = NSImage(size: rect.size, flipped: false) { drawRect in
                self.color.setFill()
                NSBezierPath(rect: drawRect).fill()
                return true
            }
            bakedBlurNSImage = img
            return
        }

        // Erase mode: sample edge colors and fill with smooth gradient
        if mode == .erase {
            guard let _ = sourceImage else { return }
            bakedBlurNSImage = bakeErase()
            return
        }

        guard let _ = sourceImage, let regionImage = cropRegionFromSource() else { return }
        guard let tiffData = regionImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else { return }

        if mode == .blur {
            guard let blurredCG = applyGaussianBlur(to: cgImage) else { return }
            bakedBlurNSImage = NSImage(cgImage: blurredCG, size: rect.size)
        } else {
            // Pixelate: down-sample → up-scale with nearest-neighbor
            let pixelBlock = 8
            let tinyW = max(1, cgImage.width / pixelBlock)
            let tinyH = max(1, cgImage.height / pixelBlock)
            let cs = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

            guard let ctx1 = CGContext(data: nil, width: tinyW, height: tinyH,
                                        bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo) else { return }
            ctx1.interpolationQuality = .low
            ctx1.draw(cgImage, in: CGRect(x: 0, y: 0, width: tinyW, height: tinyH))
            guard let tiny1 = ctx1.makeImage() else { return }

            let tinyW2 = max(1, tinyW / 2)
            let tinyH2 = max(1, tinyH / 2)
            guard let ctx2 = CGContext(data: nil, width: tinyW2, height: tinyH2,
                                        bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo) else { return }
            ctx2.interpolationQuality = .low
            ctx2.draw(tiny1, in: CGRect(x: 0, y: 0, width: tinyW2, height: tinyH2))
            guard let tiny2 = ctx2.makeImage() else { return }

            let finalW = max(1, Int(rect.width * 2))
            let finalH = max(1, Int(rect.height * 2))
            guard let ctx3 = CGContext(data: nil, width: finalW, height: finalH,
                                        bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo) else { return }
            ctx3.interpolationQuality = .none
            ctx3.draw(tiny2, in: CGRect(x: 0, y: 0, width: finalW, height: finalH))

            guard let pixelatedCG = ctx3.makeImage() else { return }
            bakedBlurNSImage = NSImage(cgImage: pixelatedCG, size: rect.size)
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

        // Live preview while drawing
        switch censorMode {
        case .pixelate:
            NSColor.black.withAlphaComponent(0.3).setFill()
            NSBezierPath(rect: rect).fill()
        case .blur:
            NSColor.white.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: rect).fill()
        case .solid:
            color.setFill()
            NSBezierPath(rect: rect).fill()
            return  // no border for solid
        case .erase:
            // Subtle crosshatch pattern to indicate erase area
            NSColor(white: 0.5, alpha: 0.2).setFill()
            NSBezierPath(rect: rect).fill()
        }

        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        let pattern: [CGFloat] = [4, 4]
        border.setLineDash(pattern, count: 2, phase: 0)
        NSColor.white.withAlphaComponent(censorMode == .blur ? 0.7 : 0.5).setStroke()
        border.stroke()
    }

    fileprivate func bakeTextOnlyCensor() -> NSImage? {
        let rect = boundingRect
        guard rect.width > 4, rect.height > 4,
              let regionImage = cropRegionFromSource(),
              let tiffData = regionImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage
        else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        let imageBounds = NSRect(origin: .zero, size: rect.size)
        let padding: CGFloat = 4

        let result = NSImage(size: rect.size, flipped: false) { _ in
            for observation in observations {
                let box = observation.boundingBox
                let localRect = NSRect(
                    x: box.origin.x * rect.width - padding,
                    y: box.origin.y * rect.height - padding,
                    width: box.width * rect.width + padding * 2,
                    height: box.height * rect.height + padding * 2
                ).intersection(imageBounds)

                guard localRect.width > 1, localRect.height > 1 else { continue }

                let textAnnotation = Annotation(
                    tool: self.tool,
                    startPoint: localRect.origin,
                    endPoint: NSPoint(x: localRect.maxX, y: localRect.maxY),
                    color: self.color,
                    strokeWidth: self.strokeWidth
                )
                textAnnotation.censorMode = self.censorMode
                textAnnotation.censorDrawScope = .all
                if self.censorMode != .solid {
                    textAnnotation.sourceImage = regionImage
                    textAnnotation.sourceImageBounds = imageBounds
                }
                textAnnotation.bakePixelate()
                if let baked = textAnnotation.bakedBlurNSImage {
                    baked.draw(in: localRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }
            return true
        }
        return result
    }

    /// Erase mode: sample the border pixels around the rect from the source image,
    /// then fill each pixel by interpolating from the nearest edge colors.
    fileprivate func bakeErase() -> NSImage? {
        guard let src = sourceImage, let srcBounds = sourceImageBounds as NSRect? else { return nil }
        let rect = boundingRect
        guard rect.width > 2, rect.height > 2 else { return nil }

        // Render the source region with some padding into a bitmap for pixel sampling
        let samplePad: CGFloat = 4  // pixels outside the rect to sample
        let sampleRect = NSRect(
            x: rect.minX - samplePad, y: rect.minY - samplePad,
            width: rect.width + samplePad * 2, height: rect.height + samplePad * 2)

        let regionImage = NSImage(size: sampleRect.size, flipped: false) { _ in
            src.draw(in: NSRect(x: -(sampleRect.minX - srcBounds.minX),
                                y: -(sampleRect.minY - srcBounds.minY),
                                width: srcBounds.width, height: srcBounds.height),
                     from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        guard let tiffData = regionImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let bmpW = bitmap.pixelsWide, bmpH = bitmap.pixelsHigh
        guard bmpW > 4, bmpH > 4 else { return nil }

        // Inner rect in bitmap pixel coords
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
            return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
        }

        // Sample left and right edge colors per row (just outside the rect)
        var leftColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
        var rightColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
        for row in 0..<ih {
            let sy = iy + row
            // Average a few pixels outside the left/right edge
            var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0
            var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0
            let n = max(1, min(ix, 3))  // sample up to 3 pixels
            for d in 1...n {
                let l = samplePixel(ix - d, sy)
                lr += l.r; lg += l.g; lb += l.b
                let r = samplePixel(ix + iw - 1 + d, sy)
                rr += r.r; rg += r.g; rb += r.b
            }
            leftColors.append((lr / CGFloat(n), lg / CGFloat(n), lb / CGFloat(n)))
            rightColors.append((rr / CGFloat(n), rg / CGFloat(n), rb / CGFloat(n)))
        }

        // Sample top and bottom edge colors per column
        var topColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
        var bottomColors = [(r: CGFloat, g: CGFloat, b: CGFloat)]()
        for col in 0..<iw {
            let sx = ix + col
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
            let n = max(1, min(iy, 3))
            for d in 1...n {
                let t = samplePixel(sx, iy + ih - 1 + d)
                tr += t.r; tg += t.g; tb += t.b
                let b = samplePixel(sx, iy - d)
                br += b.r; bg += b.g; bb += b.b
            }
            topColors.append((tr / CGFloat(n), tg / CGFloat(n), tb / CGFloat(n)))
            bottomColors.append((br / CGFloat(n), bg / CGFloat(n), bb / CGFloat(n)))
        }

        // Render the fill: for each pixel, blend horizontal interpolation (left↔right)
        // with vertical interpolation (bottom↔top)
        let outW = iw, outH = ih
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: outW, height: outH,
                                  bitsPerComponent: 8, bytesPerRow: outW * 4,
                                  space: cs, bitmapInfo: bitmapInfo),
              let outData = ctx.data else { return nil }
        let outPtr = outData.bindMemory(to: UInt8.self, capacity: outW * outH * 4)

        for row in 0..<outH {
            let ty = CGFloat(row) / max(1, CGFloat(outH - 1))  // 0 = bottom, 1 = top
            let lc = leftColors[row], rc = rightColors[row]
            for col in 0..<outW {
                let tx = CGFloat(col) / max(1, CGFloat(outW - 1))  // 0 = left, 1 = right
                let tc = topColors[col], bc = bottomColors[col]
                // Horizontal lerp from left/right edge colors for this row
                let hr = lc.r + (rc.r - lc.r) * tx
                let hg = lc.g + (rc.g - lc.g) * tx
                let hb = lc.b + (rc.b - lc.b) * tx
                // Vertical lerp from bottom/top edge colors for this column
                let vr = bc.r + (tc.r - bc.r) * ty
                let vg = bc.g + (tc.g - bc.g) * ty
                let vb = bc.b + (tc.b - bc.b) * ty
                // Average horizontal and vertical
                let off = (row * outW + col) * 4
                outPtr[off]   = UInt8(max(0, min(255, (hr + vr) * 0.5 * 255)))
                outPtr[off+1] = UInt8(max(0, min(255, (hg + vg) * 0.5 * 255)))
                outPtr[off+2] = UInt8(max(0, min(255, (hb + vb) * 0.5 * 255)))
                outPtr[off+3] = 255
            }
        }

        guard let resultCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: resultCG, size: rect.size)
    }

    static let ciContext = CIContext()

    fileprivate func applyGaussianBlur(to cgImage: CGImage) -> CGImage? {
        let w = cgImage.width
        let h = cgImage.height
        let radius = max(10.0, min(Double(w), Double(h)) * 0.03)

        let ciImage = CIImage(cgImage: cgImage)

        guard let clamp = CIFilter(name: "CIAffineClamp") else { return nil }
        clamp.setValue(ciImage, forKey: kCIInputImageKey)
        clamp.setValue(NSAffineTransform(), forKey: kCIInputTransformKey)
        guard let clamped = clamp.outputImage else { return nil }

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage else { return nil }

        let outputRect = CGRect(x: 0, y: 0, width: w, height: h)
        return Annotation.ciContext.createCGImage(output, from: outputRect)
    }

    // MARK: - Shared region crop

    /// Render the source image region matching boundingRect into a new NSImage.
    /// Uses NSImage drawing which handles all coordinate transforms correctly.
    fileprivate func cropRegionFromSource() -> NSImage? {
        guard let sourceImage = sourceImage else { return nil }
        let rect = boundingRect
        guard rect.width > 4, rect.height > 4 else { return nil }

        let srcBounds = sourceImageBounds
        let regionImage = NSImage(size: rect.size, flipped: false) { _ in
            sourceImage.draw(in: NSRect(x: -rect.minX, y: -rect.minY,
                                         width: srcBounds.width, height: srcBounds.height),
                             from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        return regionImage
    }
}
