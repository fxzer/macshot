import Cocoa
import Vision

/// Handles text translation overlay: OCR → translate → create overlay annotations.
enum TranslateOverlay {

    private struct OverlayBlock {
        let translatedText: String
        let viewRect: NSRect
        let backgroundColor: NSColor
    }

    /// Perform OCR + translation on the selected region. Calls completion with overlay annotations.
    static func translate(
        screenshot: NSImage,
        selectionRect: NSRect,
        captureDrawRect: NSRect,
        targetLang: String,
        onError: @escaping (String) -> Void,
        completion: @escaping ([Annotation]) -> Void
    ) {
        let regionImage = NSImage(size: selectionRect.size, flipped: false) { _ in
            screenshot.draw(in: NSRect(x: -selectionRect.origin.x, y: -selectionRect.origin.y,
                                       width: captureDrawRect.width, height: captureDrawRect.height),
                            from: .zero, operation: .copy, fraction: 1.0)
            return true
        }

        guard let cgImage = regionImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            onError("Failed to process image")
            return
        }

        let request = VisionOCR.makeTextRecognitionRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation],
                  !observations.isEmpty else {
                DispatchQueue.main.async { onError("No text found in selection.") }
                return
            }

            let blocks = observations.compactMap { obs -> (text: String, box: CGRect)? in
                guard let top = obs.topCandidates(1).first else { return nil }
                let t = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                return (t, obs.boundingBox)
            }

            TranslationService.translateBatch(texts: blocks.map { $0.text }, targetLang: targetLang) { result in
                switch result {
                case .failure(let error):
                    onError("Translation failed: \(error.localizedDescription)")

                case .success(let translations):
                    var overlayBlocks: [OverlayBlock] = []
                    let groupID = UUID()

                    for (i, block) in blocks.enumerated() {
                        guard i < translations.count else { continue }
                        let translated = translations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !translated.isEmpty else { continue }

                        let box = block.box
                        let padding: CGFloat = 1
                        let viewX = selectionRect.origin.x + box.origin.x * selectionRect.width - padding
                        let viewY = selectionRect.origin.y + box.origin.y * selectionRect.height - padding
                        let viewW = box.width * selectionRect.width + padding * 2
                        let viewH = box.height * selectionRect.height + padding * 2

                        let bgColor = sampleAverageColor(in: cgImage, region: CGRect(
                            x: box.origin.x * CGFloat(cgImage.width),
                            y: box.origin.y * CGFloat(cgImage.height),
                            width: box.width * CGFloat(cgImage.width),
                            height: box.height * CGFloat(cgImage.height)
                        ))

                        overlayBlocks.append(
                            OverlayBlock(
                                translatedText: translated,
                                viewRect: NSRect(x: viewX, y: viewY, width: viewW, height: viewH),
                                backgroundColor: bgColor
                            )
                        )
                    }

                    let typicalFontSize = unifiedFontSize(for: overlayBlocks)
                    let annotations = overlayBlocks.map { block in
                        let ann = Annotation(
                            tool: .translateOverlay,
                            startPoint: block.viewRect.origin,
                            endPoint: NSPoint(x: block.viewRect.maxX, y: block.viewRect.maxY),
                            color: block.backgroundColor, strokeWidth: 0
                        )
                        ann.text = block.translatedText
                        ann.fontSize = fittedFontSize(
                            for: block.translatedText,
                            in: block.viewRect.size,
                            preferred: snappedFontSize(
                                raw: max(8, block.viewRect.height * 0.65),
                                typical: typicalFontSize
                            )
                        )
                        ann.groupID = groupID
                        return ann
                    }

                    DispatchQueue.main.async { completion(annotations) }
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                DispatchQueue.main.async { onError("OCR failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: - Helpers

    private static func sampleAverageColor(in cgImage: CGImage, region: CGRect) -> NSColor {
        let clampedX = max(0, min(Int(region.origin.x), cgImage.width - 1))
        let clampedY = max(0, min(Int(region.origin.y), cgImage.height - 1))
        let clampedW = min(max(1, Int(region.width)), cgImage.width - clampedX)
        let clampedH = min(max(1, Int(region.height)), cgImage.height - clampedY)
        guard clampedW > 0, clampedH > 0 else { return .white }

        let thumbW = 4, thumbH = 4
        var pixelData = [UInt8](repeating: 0, count: thumbW * thumbH * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixelData, width: thumbW, height: thumbH,
                                  bitsPerComponent: 8, bytesPerRow: thumbW * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cropped = cgImage.cropping(to: CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH))
        else { return .white }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: thumbW, height: thumbH))

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        let count = CGFloat(thumbW * thumbH)
        for i in 0..<(thumbW * thumbH) {
            let base = i * 4
            r += CGFloat(pixelData[base]) / 255.0
            g += CGFloat(pixelData[base + 1]) / 255.0
            b += CGFloat(pixelData[base + 2]) / 255.0
        }
        return NSColor(deviceRed: r / count, green: g / count, blue: b / count, alpha: 1.0)
    }

    private static func unifiedFontSize(for blocks: [OverlayBlock]) -> CGFloat {
        let rawSizes = blocks.map { max(8, $0.viewRect.height * 0.65) }.sorted()
        guard !rawSizes.isEmpty else { return 8 }
        return rawSizes[rawSizes.count / 2]
    }

    private static func snappedFontSize(raw: CGFloat, typical: CGFloat) -> CGFloat {
        guard typical > 0 else { return raw }

        let delta = abs(raw - typical) / typical
        if delta <= 0.25 {
            return typical
        }
        return raw
    }

    private static func fittedFontSize(
        for text: String,
        in size: NSSize,
        preferred: CGFloat
    ) -> CGFloat {
        let hPad: CGFloat = 3
        let vPad: CGFloat = 2
        let availW = max(1, size.width - hPad * 2)
        let availH = max(1, size.height - vPad * 2)

        var fontSize = max(8, preferred)
        while fontSize > 8 {
            let attrStr = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]
            )
            let needed = attrStr.boundingRect(
                with: NSSize(width: availW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            if needed.height <= availH {
                break
            }
            fontSize -= 1
        }

        return fontSize
    }
}
