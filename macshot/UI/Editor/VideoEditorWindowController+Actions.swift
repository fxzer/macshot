import Cocoa
import AVFoundation
import AVKit
import UniformTypeIdentifiers

extension VideoEditorView {

    // MARK: - Actions

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        needsDisplay = true
    }

    func togglePlayPause() {
        if isGIF {
            gifIsPlaying.toggle()
            gifImageView?.animates = gifIsPlaying
            if gifIsPlaying {
                gifPlaybackTime = trimStart
            }
            needsDisplay = true
            return
        }
        guard let player = player else { return }
        if player.rate > 0 {
            player.pause()
        } else {
            let current = CMTimeGetSeconds(player.currentTime())
            if current < trimStart || current >= trimEnd - 0.1 {
                player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600))
            }
            player.play()
        }
        needsDisplay = true
    }

    func showStatus(_ msg: String, isError: Bool = false) {
        statusMessage = msg
        statusIsError = isError
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: isError ? 6 : 3, repeats: false) { [weak self] _ in
            self?.statusMessage = nil
            self?.needsDisplay = true
        }
        needsDisplay = true
    }

    func copyToClipboard() {
        // If GIF mode is selected but no GIF has been saved yet, convert to a temp GIF first
        if exportAsGIF && !isGIF && !(savedURL?.pathExtension.lowercased() == "gif") {
            showStatus(L("Converting to GIF…"))
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
            convertToGIF(destURL: tmpURL) { [weak self] success in
                guard let self = self, success else { return }
                self.copyGIFData(from: tmpURL)
            }
            return
        }

        let url = savedURL ?? videoURL
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if isGIF || url.pathExtension.lowercased() == "gif" {
            copyGIFData(from: url)
        } else {
            pasteboard.writeObjects([url as NSURL])
            videoNeverExported = false
            showStatus(L("Copied to clipboard!"))
        }
    }

    func copyGIFData(from url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = try? Data(contentsOf: url) {
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
            item.setString(url.absoluteString, forType: .fileURL)
            pasteboard.writeObjects([item])
        }
        videoNeverExported = false
        showStatus(L("Copied to clipboard!"))
    }

    func showCopyMenu() {
        let menu = NSMenu()
        let pathItem = NSMenuItem(title: L("Copy Path"), action: #selector(copyPathAction), keyEquivalent: "")
        pathItem.target = self
        menu.addItem(pathItem)
        let pos = NSPoint(x: copyArrowRect.minX, y: copyArrowRect.maxY)
        menu.popUp(positioning: nil, at: pos, in: self)
    }

    @objc func copyPathAction() {
        let url = savedURL ?? videoURL
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        showStatus(L("Path copied!"))
    }

    func exportSession(asset: AVAsset, timeRange: CMTimeRange, outputURL: URL) -> AVAssetExportSession? {
        let needsScale = exportScale < 0.999

        // Build a composition when we need to strip audio or scale
        let composition = AVMutableComposition()
        guard let videoTrack = asset.tracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        try? compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        // Include audio unless muted
        if !isMuted {
            for audioTrack in asset.tracks(withMediaType: .audio) {
                if let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: .zero)
                }
            }
        }

        // Scaling is applied via videoComposition below, so the export preset only
        // governs quality — use HighestQuality regardless of needsScale.
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        session.outputURL = outputURL
        session.outputFileType = .mp4

        // Apply scale via video composition
        if needsScale {
            let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            let w = abs(naturalSize.width)
            let h = abs(naturalSize.height)
            // Round to even for codec compatibility
            let scaledW = CGFloat((Int(w * exportScale) / 2) * 2)
            let scaledH = CGFloat((Int(h * exportScale) / 2) * 2)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

            // Apply the original transform (handles rotation) scaled down
            var transform = videoTrack.preferredTransform
            transform = transform.concatenating(CGAffineTransform(scaleX: exportScale, y: exportScale))
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = [instruction]
            videoComposition.renderSize = CGSize(width: scaledW, height: scaledH)
            videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(videoTrack.nominalFrameRate))
            session.videoComposition = videoComposition
        }

        return session
    }

    func saveVideo(completion: ((Bool) -> Void)? = nil) {
        if exportAsGIF && !isGIF {
            // GIF mode: need Save As panel since extension changes
            saveVideoAs(completion: completion)
            return
        }
        guard let dirURL = SaveDirectoryAccess.resolveRecordingDirectoryIfAccessible() else {
            saveVideoAs(completion: completion)
            return
        }
        let kind: FilenameOutputKind = exportAsGIF || isGIF ? .gif : .recording
        let ext = kind == .gif ? "gif" : videoURL.pathExtension
        let destURL = FilenameTemplateEngine.uniqueDestinationURL(
            in: dirURL,
            baseName: FilenameTemplateEngine.makeBaseName(kind: kind),
            fileExtension: ext
        )
        if exportAsGIF && !isGIF {
            convertToGIF(destURL: destURL, completion: completion)
        } else {
            saveToDestination(destURL, dirURL: dirURL, completion: completion)
        }
    }

    func saveVideoAs(completion: ((Bool) -> Void)? = nil) {
        let panel = NSSavePanel()
        let saveAsGIF = exportAsGIF && !isGIF
        panel.allowedContentTypes = saveAsGIF ? [.gif] : (isGIF ? [.gif] : [.mpeg4Movie])
        let kind: FilenameOutputKind = saveAsGIF || isGIF ? .gif : .recording
        let ext = kind == .gif ? "gif" : videoURL.pathExtension
        panel.nameFieldStringValue = FilenameTemplateEngine.makeFilename(kind: kind, fileExtension: ext)
        panel.directoryURL = SaveDirectoryAccess.recordingDirectoryHint()
        FilePanelPresenter.begin(panel, ownerWindow: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else {
                completion?(false)
                return
            }
            if saveAsGIF {
                self.convertToGIF(destURL: url, completion: completion)
            } else {
                self.saveToDestination(url, dirURL: nil, completion: completion)
            }
        }
    }

    func showSaveMenu() {
        saveVideoAs()
    }

    func showDimensionsMenu() {
        let menu = NSMenu()
        let w = originalWidth, h = originalHeight

        // Original (100%)
        let origItem = NSMenuItem(title: "\(w) × \(h)  (Original)", action: #selector(dimensionSelected(_:)), keyEquivalent: "")
        origItem.target = self
        origItem.tag = 100
        origItem.state = exportScale >= 0.999 ? .on : .off
        menu.addItem(origItem)

        menu.addItem(NSMenuItem.separator())

        // Preset percentages — only include if the result is at least 128px wide
        let presets: [(Int, String)] = [(75, "75%"), (50, "50%"), (33, "33%"), (25, "25%")]
        for (pct, label) in presets {
            let scaledW = w * pct / 100
            let scaledH = h * pct / 100
            guard scaledW >= 128 else { continue }
            // Round to even for codec compatibility
            let evenW = (scaledW / 2) * 2
            let evenH = (scaledH / 2) * 2
            let item = NSMenuItem(title: "\(evenW) × \(evenH)  (\(label))", action: #selector(dimensionSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            item.state = abs(exportScale - CGFloat(pct) / 100.0) < 0.01 ? .on : .off
            menu.addItem(item)
        }

        let pos = NSPoint(x: dimensionsBtnRect.minX, y: dimensionsBtnRect.maxY)
        menu.popUp(positioning: nil, at: pos, in: self)
    }

    @objc func dimensionSelected(_ sender: NSMenuItem) {
        exportScale = CGFloat(sender.tag) / 100.0
        savedURL = nil
        needsDisplay = true
    }

    func convertToGIF(destURL: URL, completion: ((Bool) -> Void)? = nil) {
        guard let asset = asset else { completion?(false); return }
        showStatus(L("Converting to GIF…"))

        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        // GIF capped at 15fps
        let gifFPS = min(15, asset.tracks(withMediaType: .video).first.map { Int($0.nominalFrameRate.rounded()) } ?? 15)
        let scale = exportScale

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let reader = try AVAssetReader(asset: asset)
                guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                    await MainActor.run {
                        self?.showStatus(L("No video track found"), isError: true)
                        completion?(false)
                    }
                    return
                }

                // If scaling, request scaled output directly from AVAssetReaderTrackOutput
                var outputSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                if scale < 0.999 {
                    let natSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
                    let w = Int(abs(natSize.width) * scale) / 2 * 2
                    let h = Int(abs(natSize.height) * scale) / 2 * 2
                    outputSettings[kCVPixelBufferWidthKey as String] = w
                    outputSettings[kCVPixelBufferHeightKey as String] = h
                }

                let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
                trackOutput.alwaysCopiesSampleData = false
                reader.timeRange = timeRange
                reader.add(trackOutput)

                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
                let sourceFPS = Int(videoTrack.nominalFrameRate.rounded())
                let encoder = GIFEncoder(url: tmpURL, fps: gifFPS, sourceFPS: max(sourceFPS, gifFPS))
                reader.startReading()

                while reader.status == .reading {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                       let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        encoder.addFrame(pixelBuffer)
                    }
                }
                let finalized = encoder.finish()
                guard finalized else {
                    // No frames were written (e.g. empty source) — clean up tmp and fail.
                    try? FileManager.default.removeItem(at: tmpURL)
                    throw NSError(domain: "GIFEncoder", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: L("GIF conversion failed")])
                }

                // Move to destination
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tmpURL, to: destURL)

                await MainActor.run {
                    self?.savedURL = destURL
                    self?.videoNeverExported = false
                    self?.showStatus(String(format: L("Saved to %@"), destURL.lastPathComponent))
                    self?.needsDisplay = true
                    completion?(true)
                }
            } catch {
                await MainActor.run {
                    self?.showStatus(L("GIF conversion failed"), isError: true)
                    completion?(false)
                }
            }
        }
    }

    func saveToDestination(_ destURL: URL, dirURL: URL?, completion: ((Bool) -> Void)? = nil) {
        let needsTrim = trimStart > 0.01 || (duration - trimEnd) > 0.01
        let needsScale = exportScale < 0.999
        let needsExport = needsTrim || isMuted || needsScale

        if !needsExport {
            // No processing needed — copy temp file to destination
            try? FileManager.default.removeItem(at: destURL)
            do {
                try FileManager.default.copyItem(at: videoURL, to: destURL)
                savedURL = destURL
                videoNeverExported = false
                if let dirURL = dirURL { SaveDirectoryAccess.stopAccessing(url: dirURL) }
                showStatus(String(format: L("Saved to %@"), destURL.lastPathComponent))
                needsDisplay = true
                completion?(true)
            } catch {
                if dirURL != nil {
                    // Bookmarked directory failed — fall back to Save As
                    saveVideoAs()
                    completion?(false)
                } else {
                    showStatus(L("Save failed"), isError: true)
                    completion?(false)
                }
            }
            return
        }

        guard let asset = asset else { return }
        showStatus(L("Exporting..."))

        // Export to a temp file first, then move to destination
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".\(videoURL.pathExtension)")
        let startTime = CMTime(seconds: trimStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        guard let session = exportSession(asset: asset, timeRange: timeRange, outputURL: tmpURL) else {
            showStatus(L("Export failed"), isError: true)
            return
        }

        Task {
            await session.export()
            await MainActor.run {
                if session.status == .completed {
                    try? FileManager.default.removeItem(at: destURL)
                    do {
                        try FileManager.default.moveItem(at: tmpURL, to: destURL)
                        self.savedURL = destURL
                        self.videoNeverExported = false
                        if let dirURL = dirURL { SaveDirectoryAccess.stopAccessing(url: dirURL) }
                        self.showStatus(String(format: L("Saved to %@"), destURL.lastPathComponent))
                        self.needsDisplay = true
                        completion?(true)
                    } catch {
                        self.showStatus(L("Save failed"), isError: true)
                        completion?(false)
                    }
                } else {
                    self.showStatus(L("Export failed"), isError: true)
                    try? FileManager.default.removeItem(at: tmpURL)
                    completion?(false)
                }
            }
        }
    }

    func uploadVideo() {
        let provider = UserDefaults.standard.string(forKey: DefaultsKey.uploadProvider) ?? "imgbb"

        if provider == "gdrive" && !GoogleDriveUploader.shared.isSignedIn {
            showStatus(L("Sign in to Google Drive in Settings"), isError: true)
            return
        }
        if provider == "s3" && !S3Uploader.shared.isConfigured {
            showStatus(L("Configure S3 in Settings"), isError: true)
            return
        }
        if provider == "cfimgbed" && !CloudflareImgBedUploader.shared.isConfigured {
            showStatus(L("Configure CloudFlare ImgBed in Settings"), isError: true)
            return
        }
        if provider != "gdrive" && provider != "s3" && provider != "cfimgbed" {
            showStatus(L("Video upload requires Google Drive, S3, or CloudFlare ImgBed"), isError: true)
            return
        }

        showStatus(L("Uploading..."))

        let completionHandler: (Result<String, Error>) -> Void = { [weak self] result in
            switch result {
            case .success(let link):
                PasteboardWriter.writeString(link)

                // 使用第一帧缩略图
                let thumbnail = self?.thumbnailImages.first
                UploadHistoryStore.append(link: link, provider: provider, thumbnail: thumbnail)

                self?.videoNeverExported = false
                self?.showStatus(L("Uploaded! Link copied."))
            case .failure(let error):
                self?.showStatus(String(format: L("Upload failed: %@"), error.localizedDescription), isError: true)
            }
        }

        let uploadFileURL: (URL, Bool) -> Void = { fileURL, isTemp in
            let wrappedCompletion: (Result<String, Error>) -> Void = { result in
                if isTemp { try? FileManager.default.removeItem(at: fileURL) }
                completionHandler(result)
            }
            if provider == "s3" {
                S3Uploader.shared.uploadVideo(url: fileURL, progress: nil, completion: wrappedCompletion)
            } else if provider == "cfimgbed" {
                let progressHandler: (Double) -> Void = { [weak self] fraction in
                    self?.showStatus(String(format: L("Uploading... %d%%"), Int(fraction * 100)))
                }
                CloudflareImgBedUploader.shared.uploadVideo(url: fileURL, progress: progressHandler, completion: wrappedCompletion)
            } else {
                let progressHandler: (Double) -> Void = { [weak self] fraction in
                    self?.showStatus(String(format: L("Uploading... %d%%"), Int(fraction * 100)))
                }
                GoogleDriveUploader.shared.uploadVideo(url: fileURL, progress: progressHandler, completion: wrappedCompletion)
            }
        }

        let needsTrim = trimStart > 0.01 || (duration - trimEnd) > 0.01
        let needsExport = needsTrim || isMuted

        if !needsExport {
            uploadFileURL(videoURL, false)
        } else {
            guard let asset = asset else { return }
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("macshot_upload_\(UUID().uuidString).mp4")

            let timeRange = CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 600),
                                        end: CMTime(seconds: trimEnd, preferredTimescale: 600))
            guard let session = exportSession(asset: asset, timeRange: timeRange, outputURL: tmpURL) else {
                showStatus(L("Export failed"), isError: true)
                return
            }

            Task {
                await session.export()
                await MainActor.run {
                    guard session.status == .completed else {
                        self.showStatus(L("Export failed"), isError: true)
                        return
                    }
                    uploadFileURL(tmpURL, true)
                }
            }
        }
    }
}
