import Cocoa
import AVFoundation
import AVKit
import UniformTypeIdentifiers

extension VideoEditorView {

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Controls background
        let controlsBg = NSRect(x: 0, y: 0, width: bounds.width, height: controlsH)
        ToolbarLayout.bgColor.setFill()
        NSBezierPath(rect: controlsBg).fill()

        // Separator
        ToolbarLayout.iconColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: controlsH, width: bounds.width, height: 0.5)).fill()

        guard duration > 0 else { return }

        drawTimeline()
        drawButtons()
        drawTimeLabels()
        if let msg = statusMessage { drawStatus(msg) }
    }

    func drawTimeline() {
        let tlX = timelinePad
        let tlW = bounds.width - timelinePad * 2
        let tlY: CGFloat = 55
        let tlH: CGFloat = 36
        timelineRect = NSRect(x: tlX, y: tlY, width: tlW, height: tlH)

        // Regenerate thumbnails if width changed significantly
        if abs(tlW - lastThumbnailWidth) > 40 && !thumbnailsGenerating && asset != nil {
            generateThumbnails()
        }

        // Track background with rounded clip
        let trackPath = NSBezierPath(roundedRect: timelineRect, xRadius: 5, yRadius: 5)
        ToolbarLayout.iconColor.withAlphaComponent(0.06).setFill()
        trackPath.fill()

        // Draw thumbnails — use floor/ceil to avoid sub-pixel gaps between tiles
        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        if !thumbnailImages.isEmpty {
            let count = thumbnailImages.count
            for (i, img) in thumbnailImages.enumerated() {
                let x0 = floor(tlX + CGFloat(i) * tlW / CGFloat(count))
                let x1 = ceil(tlX + CGFloat(i + 1) * tlW / CGFloat(count))
                let r = NSRect(x: x0, y: tlY, width: x1 - x0, height: tlH)
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.5)
            }
        }

        // Dim untrimmed regions
        let startX = tlX + CGFloat(trimStart / duration) * tlW
        let endX = tlX + CGFloat(trimEnd / duration) * tlW
        NSColor.black.withAlphaComponent(0.6).setFill()
        if startX > tlX {
            NSRect(x: tlX, y: tlY, width: startX - tlX, height: tlH).fill()
        }
        if endX < tlX + tlW {
            NSRect(x: endX, y: tlY, width: tlX + tlW - endX, height: tlH).fill()
        }

        // Trim border highlight
        let trimRect = NSRect(x: startX, y: tlY, width: endX - startX, height: tlH)
        let trimBorder = NSBezierPath(roundedRect: trimRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        trimBorder.lineWidth = 1.5
        ToolbarLayout.accentColor.withAlphaComponent(0.8).setStroke()
        trimBorder.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Trim handles
        let handleW: CGFloat = 10
        let handleH: CGFloat = tlH + 8

        let startHandleRect = NSRect(x: startX - handleW / 2, y: tlY - 4, width: handleW, height: handleH)
        ToolbarLayout.accentColor.setFill()
        NSBezierPath(roundedRect: startHandleRect, xRadius: 3, yRadius: 3).fill()
        drawHandleGrip(in: startHandleRect)

        let endHandleRect = NSRect(x: endX - handleW / 2, y: tlY - 4, width: handleW, height: handleH)
        ToolbarLayout.accentColor.setFill()
        NSBezierPath(roundedRect: endHandleRect, xRadius: 3, yRadius: 3).fill()
        drawHandleGrip(in: endHandleRect)

        // Playhead
        if player != nil || isGIF {
            let currentTime = currentPlaybackTime
            let playheadX = max(tlX, min(tlX + tlW, tlX + CGFloat(currentTime / duration) * tlW))

            // Playhead line with subtle shadow
            ToolbarLayout.iconColor.withAlphaComponent(0.9).setFill()
            let playheadRect = NSRect(x: playheadX - 1, y: tlY - 2, width: 2, height: tlH + 4)
            NSBezierPath(roundedRect: playheadRect, xRadius: 1, yRadius: 1).fill()

            // Playhead circle
            let circleR: CGFloat = 5
            let circleX = max(tlX + circleR, min(tlX + tlW - circleR, playheadX))
            ToolbarLayout.iconColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: circleX - circleR, y: tlY + tlH + 2, width: circleR * 2, height: circleR * 2)).fill()
        }
    }

    func drawHandleGrip(in rect: NSRect) {
        ToolbarLayout.iconColor.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        let midY = rect.midY
        for dy in stride(from: -3 as CGFloat, through: 3, by: 3) {
            path.move(to: NSPoint(x: rect.midX - 2, y: midY + dy))
            path.line(to: NSPoint(x: rect.midX + 2, y: midY + dy))
        }
        path.stroke()
    }

    func drawButtons() {
        let btnH: CGFloat = 28
        let btnY: CGFloat = 12
        let gap: CGFloat = 8
        let iconBtnW: CGFloat = 34
        let labelBtnW: CGFloat = 100

        // Pre-compute right group width so left content knows where to stop
        let copyArrowW: CGFloat = 20
        let saveArrowW: CGFloat = 20
        let rightGroupW = (labelBtnW + copyArrowW) + gap + iconBtnW + gap + labelBtnW + gap + (labelBtnW + saveArrowW)
        let maxLeftX = bounds.width - timelinePad - rightGroupW - 12  // 12pt breathing room

        // Left group: play, mute
        var x: CGFloat = timelinePad

        let isPlaying = isGIF ? gifIsPlaying : (player?.rate ?? 0 > 0)
        playBtnRect = NSRect(x: x, y: btnY, width: iconBtnW, height: btnH)
        drawIconButton(rect: playBtnRect, symbol: isPlaying ? "pause.fill" : "play.fill", accent: true)
        x += iconBtnW + gap

        muteBtnRect = NSRect(x: x, y: btnY, width: iconBtnW, height: btnH)
        drawIconButton(rect: muteBtnRect, symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accent: false, active: isMuted)
        x += iconBtnW + gap

        // Format toggle + file info
        if !isGIF {
            // MP4 | GIF segmented toggle
            let segW: CGFloat = 88
            let segH: CGFloat = 22
            let segY = btnY + (btnH - segH) / 2
            formatToggleRect = NSRect(x: x + 4, y: segY, width: segW, height: segH)
            let halfW = segW / 2
            formatMP4Rect = NSRect(x: formatToggleRect.minX, y: segY, width: halfW, height: segH)
            formatGIFRect = NSRect(x: formatToggleRect.minX + halfW, y: segY, width: halfW, height: segH)

            // Background
            ToolbarLayout.iconColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: formatToggleRect, xRadius: 5, yRadius: 5).fill()

            // Selected segment highlight
            let selRect = exportAsGIF ? formatGIFRect : formatMP4Rect
            ToolbarLayout.accentColor.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: selRect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()

            // Labels
            let selAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: ToolbarLayout.iconColor,
            ]
            let unselAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.5),
            ]
            let mp4Str = "MP4" as NSString
            let gifStr = "GIF" as NSString
            let mp4Size = mp4Str.size(withAttributes: selAttrs)
            let gifSize = gifStr.size(withAttributes: selAttrs)
            mp4Str.draw(at: NSPoint(x: formatMP4Rect.midX - mp4Size.width / 2, y: formatMP4Rect.midY - mp4Size.height / 2),
                        withAttributes: exportAsGIF ? unselAttrs : selAttrs)
            gifStr.draw(at: NSPoint(x: formatGIFRect.midX - gifSize.width / 2, y: formatGIFRect.midY - gifSize.height / 2),
                        withAttributes: exportAsGIF ? selAttrs : unselAttrs)
            x += segW + 12
        }

        do {
            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.4),
            ]
            let sourceFileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(sourceFileSize), countStyle: .file)
            let fpsValue = asset?.tracks(withMediaType: .video).first?.nominalFrameRate ?? 0
            let fpsStr = fpsValue > 0 ? "\(Int(fpsValue.rounded()))fps" : ""
            let infoStr = "\(sizeStr)  ·  \(fpsStr)" as NSString
            let infoSize = infoStr.size(withAttributes: infoAttrs)
            if x + infoSize.width < maxLeftX {
                infoStr.draw(at: NSPoint(x: x + 4, y: btnY + (btnH - infoSize.height) / 2), withAttributes: infoAttrs)
                x += infoSize.width + 12
            }

            // Dimensions dropdown button
            dimensionsBtnRect = .zero
            if originalWidth > 0 && x < maxLeftX {
                let exportW = Int(CGFloat(originalWidth) * exportScale)
                let exportH = Int(CGFloat(originalHeight) * exportScale)
                let dimLabel: String
                if exportScale >= 0.999 {
                    dimLabel = "\(originalWidth)×\(originalHeight)"
                } else {
                    let pct = Int((exportScale * 100).rounded())
                    dimLabel = "\(exportW)×\(exportH) (\(pct)%)"
                }
                let dimAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(exportScale < 0.999 ? 0.7 : 0.4),
                ]
                let dimStr = "  ·  \(dimLabel) ▼" as NSString
                let dimSize = dimStr.size(withAttributes: dimAttrs)
                let dimBtnW = dimSize.width + 8
                if x + dimBtnW < maxLeftX {
                    dimensionsBtnRect = NSRect(x: x, y: btnY, width: dimBtnW, height: btnH)
                    dimStr.draw(at: NSPoint(x: x + 4, y: btnY + (btnH - dimSize.height) / 2), withAttributes: dimAttrs)
                    x += dimBtnW
                }
            }

            // Estimated export size — show when trim, scale, or format change would affect output
            let trimRatio = duration > 0 ? (trimEnd - trimStart) / duration : 1.0
            let scaleRatio = exportScale * exportScale  // pixels scale quadratically
            let willChange = trimRatio < 0.99 || scaleRatio < 0.99 || exportAsGIF
            if willChange && sourceFileSize > 0 && x < maxLeftX {
                let estimated: Int64
                if exportAsGIF {
                    let gifFPSRatio = min(15.0, fpsValue) / max(fpsValue, 1.0)
                    estimated = Int64(Double(sourceFileSize) * trimRatio * scaleRatio * 3.0 * Double(gifFPSRatio))
                } else {
                    estimated = Int64(Double(sourceFileSize) * trimRatio * scaleRatio)
                }
                let estStr = "  ·  ~\(ByteCountFormatter.string(fromByteCount: estimated, countStyle: .file))" as NSString
                let estAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.35),
                ]
                let estSize = estStr.size(withAttributes: estAttrs)
                if x + estSize.width + 8 < maxLeftX {
                    estStr.draw(at: NSPoint(x: x + 4, y: btnY + (btnH - estSize.height) / 2), withAttributes: estAttrs)
                }
            }
        }

        // Right group: save, upload, finder, copy
        x = bounds.width - timelinePad
        let fullCopyW = labelBtnW + copyArrowW
        x -= fullCopyW
        let fullCopyRect = NSRect(x: x, y: btnY, width: fullCopyW, height: btnH)
        copyBtnRect = NSRect(x: x, y: btnY, width: labelBtnW, height: btnH)
        copyArrowRect = NSRect(x: x + labelBtnW, y: btnY, width: copyArrowW, height: btnH)

        // Draw combined background
        ToolbarLayout.iconColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: fullCopyRect, xRadius: 6, yRadius: 6).fill()

        do {
            let iconSize: CGFloat = 12
            let copyAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.85),
            ]
            let copyLabel = L("Copy") as NSString
            let copyLabelSize = copyLabel.size(withAttributes: copyAttrs)
            let totalCopyW = iconSize + 4 + copyLabelSize.width
            let copyStartX = copyBtnRect.midX - totalCopyW / 2
            if let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: iconSize, weight: .medium)) {
                let tinted = NSImage(size: img.size, flipped: false) { r in
                    img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                    ToolbarLayout.iconColor.withAlphaComponent(0.85).setFill()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: copyStartX, y: copyBtnRect.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            copyLabel.draw(at: NSPoint(x: copyStartX + iconSize + 4, y: copyBtnRect.midY - copyLabelSize.height / 2), withAttributes: copyAttrs)
        }

        // Separator line
        ToolbarLayout.iconColor.withAlphaComponent(0.2).setStroke()
        let copySep = NSBezierPath()
        copySep.move(to: NSPoint(x: copyArrowRect.minX, y: copyArrowRect.minY + 4))
        copySep.line(to: NSPoint(x: copyArrowRect.minX, y: copyArrowRect.maxY - 4))
        copySep.lineWidth = 1
        copySep.stroke()

        // Chevron
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold)) {
            let tinted = NSImage(size: chevron.size, flipped: false) { r in
                chevron.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                ToolbarLayout.iconColor.withAlphaComponent(0.6).setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: copyArrowRect.midX - chevron.size.width / 2, y: copyArrowRect.midY - chevron.size.height / 2,
                                    width: chevron.size.width, height: chevron.size.height))
        }

        x -= gap + iconBtnW
        finderBtnRect = NSRect(x: x, y: btnY, width: iconBtnW, height: btnH)
        drawIconButton(rect: finderBtnRect, symbol: "folder", accent: false, dimmed: savedURL == nil)
        x -= gap + labelBtnW
        let uploadProvider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"
        let canUpload = (uploadProvider == "gdrive" && GoogleDriveUploader.shared.isSignedIn) || (uploadProvider == "s3" && S3Uploader.shared.isConfigured) || (uploadProvider == "cfimgbed" && CloudflareImgBedUploader.shared.isConfigured)
        uploadBtnRect = NSRect(x: x, y: btnY, width: labelBtnW, height: btnH)
        drawLabelButton(rect: uploadBtnRect, symbol: "icloud.and.arrow.up", label: L("Upload"), dimmed: !canUpload)
        let arrowW: CGFloat = 20
        x -= gap + labelBtnW + arrowW
        let fullSaveW = labelBtnW + arrowW
        let fullSaveRect = NSRect(x: x, y: btnY, width: fullSaveW, height: btnH)
        saveBtnRect = NSRect(x: x, y: btnY, width: labelBtnW, height: btnH)
        saveArrowRect = NSRect(x: x + labelBtnW, y: btnY, width: arrowW, height: btnH)

        // Draw combined background
        ToolbarLayout.iconColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: fullSaveRect, xRadius: 6, yRadius: 6).fill()

        // Draw save icon + label
        do {
            let iconSize: CGFloat = 12
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.85),
            ]
            let saveLabel = L("Save") as NSString
            let labelSize = saveLabel.size(withAttributes: attrs)
            let totalW = iconSize + 4 + labelSize.width
            let startX = saveBtnRect.midX - totalW / 2
            if let img = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: iconSize, weight: .medium)) {
                let tinted = NSImage(size: img.size, flipped: false) { r in
                    img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                    ToolbarLayout.iconColor.withAlphaComponent(0.85).setFill()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: startX, y: saveBtnRect.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            saveLabel.draw(at: NSPoint(x: startX + iconSize + 4, y: saveBtnRect.midY - labelSize.height / 2), withAttributes: attrs)
        }

        // Draw separator line
        ToolbarLayout.iconColor.withAlphaComponent(0.2).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: saveArrowRect.minX, y: saveArrowRect.minY + 4))
        sep.line(to: NSPoint(x: saveArrowRect.minX, y: saveArrowRect.maxY - 4))
        sep.lineWidth = 1
        sep.stroke()

        // Draw chevron in arrow portion
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold)) {
            let tinted = NSImage(size: chevron.size, flipped: false) { r in
                chevron.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                ToolbarLayout.iconColor.withAlphaComponent(0.6).setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: saveArrowRect.midX - chevron.size.width / 2, y: saveArrowRect.midY - chevron.size.height / 2,
                                    width: chevron.size.width, height: chevron.size.height))
        }
    }

    func drawIconButton(rect: NSRect, symbol: String, accent: Bool, active: Bool = false, dimmed: Bool = false) {
        let bg = accent ? ToolbarLayout.accentColor : (active ? ToolbarLayout.accentColor.withAlphaComponent(0.4) : ToolbarLayout.iconColor.withAlphaComponent(dimmed ? 0.04 : 0.1))
        bg.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let alpha: CGFloat = dimmed ? 0.25 : 1.0
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) {
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                ToolbarLayout.iconColor.withAlphaComponent(alpha).setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            let imgRect = NSRect(x: rect.midX - img.size.width / 2, y: rect.midY - img.size.height / 2,
                                  width: img.size.width, height: img.size.height)
            tinted.draw(in: imgRect)
        }
    }

    func drawLabelButton(rect: NSRect, symbol: String, label: String, dimmed: Bool = false) {
        let bg = ToolbarLayout.iconColor.withAlphaComponent(dimmed ? 0.04 : 0.1)
        bg.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let alpha: CGFloat = dimmed ? 0.25 : 0.85
        let iconSize: CGFloat = 12
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(alpha),
        ]
        let str = label as NSString
        let textSize = str.size(withAttributes: attrs)
        let iconGap: CGFloat = 8
        let totalW = iconSize + iconGap + textSize.width
        let startX = rect.midX - totalW / 2

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: iconSize, weight: .medium)) {
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                ToolbarLayout.iconColor.withAlphaComponent(alpha).setFill()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: startX, y: rect.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
        str.draw(at: NSPoint(x: startX + iconSize + iconGap, y: rect.midY - textSize.height / 2), withAttributes: attrs)
    }

    func drawTimeLabels() {
        let currentTime = currentPlaybackTime
        let trimDuration = trimEnd - trimStart
        let labelY = timelineRect.maxY + 14

        let leftStr = formatTime(currentTime) as NSString
        let rightStr = String(format: L("%@ selected"), formatTime(trimDuration)) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(0.5),
        ]

        leftStr.draw(at: NSPoint(x: timelinePad, y: labelY), withAttributes: attrs)

        let rightSize = rightStr.size(withAttributes: attrs)
        rightStr.draw(at: NSPoint(x: bounds.width - timelinePad - rightSize.width, y: labelY), withAttributes: attrs)
    }

    func drawStatus(_ message: String) {
        let color: NSColor = statusIsError ? NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.5, alpha: 1.0) : .systemGreen
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
        ]
        let str = message as NSString
        let size = str.size(withAttributes: attrs)
        let labelY = timelineRect.maxY + 14
        str.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: labelY), withAttributes: attrs)
    }

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - floor(seconds)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}
