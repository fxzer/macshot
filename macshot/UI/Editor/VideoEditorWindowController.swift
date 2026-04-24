import Cocoa
import AVFoundation
import AVKit
import UniformTypeIdentifiers

/// Standalone video editor window for trimming and exporting recorded videos.
final class VideoEditorWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var editorView: VideoEditorView?
    private static var activeControllers: [VideoEditorWindowController] = []

    static func open(url: URL) {
        let controller = VideoEditorWindowController()
        controller.show(url: url)
        activeControllers.append(controller)
        if activeControllers.count == 1 {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func show(url: URL) {
        guard let screen = NSScreen.main else { return }

        // Size window to fit content, capped at 60% of screen
        let controlsH: CGFloat = 140
        let maxW = screen.frame.width * 0.6
        let maxH = screen.frame.height * 0.6
        var contentW: CGFloat = 800
        var contentH: CGFloat = 450

        // Get content dimensions — MP4 uses AVAsset track info
        if url.pathExtension.lowercased() != "gif" {
            let asset = AVAsset(url: url)
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                let backingScale = screen.backingScaleFactor
                contentW = abs(size.width) / backingScale
                contentH = abs(size.height) / backingScale
            }
        }
        // GIF: keep defaults — AVFoundation can't read GIF dimensions reliably

        // Scale down to fit screen, maintaining aspect ratio
        let scale = min(1.0, min(maxW / contentW, (maxH - controlsH) / contentH))
        let winW = max(820, contentW * scale)
        let winH = max(400, contentH * scale + controlsH)
        let winX = screen.frame.midX - winW / 2
        let winY = screen.frame.midY - winH / 2

        let win = NSWindow(
            contentRect: NSRect(x: winX, y: winY, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = L("macshot Video Editor")
        win.minSize = NSSize(width: 820, height: 400)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.collectionBehavior = [.fullScreenAuxiliary]
        win.backgroundColor = ToolbarLayout.bgColor

        let view = VideoEditorView(frame: NSRect(x: 0, y: 0, width: winW, height: winH), videoURL: url)
        win.contentView = view

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
        self.editorView = view
    }

    func windowWillClose(_ notification: Notification) {
        editorView?.cleanup()
        editorView = nil
        let closingWindow = window
        window = nil
        Self.activeControllers.removeAll { $0 === self }
        if Self.activeControllers.isEmpty {
            (NSApp.delegate as? AppDelegate)?.returnFocusIfNeeded()
        }
    }
}

// MARK: - VideoEditorView

final class VideoEditorView: NSView {

    let videoURL: URL
    let isGIF: Bool
    var player: AVPlayer?
    var playerView: AVPlayerView?
    var gifImageView: NSImageView?
    var asset: AVAsset?
    var duration: Double = 0

    // Timeline state
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var timelineRect: NSRect = .zero
    var isDraggingStart: Bool = false
    var isDraggingEnd: Bool = false
    var isDraggingScrubber: Bool = false
    var timeObserver: Any?
    var gifPlaybackTimer: Timer?
    var gifPlaybackTime: Double = 0
    var gifIsPlaying: Bool = false

    // Timeline thumbnails
    var thumbnailImages: [NSImage] = []
    var thumbnailsGenerating: Bool = false
    var lastThumbnailWidth: CGFloat = 0

    // Format toggle (MP4 vs GIF export)
    var exportAsGIF: Bool = false
    var formatToggleRect: NSRect = .zero
    var formatMP4Rect: NSRect = .zero
    var formatGIFRect: NSRect = .zero

    // Export dimensions
    var originalWidth: Int = 0
    var originalHeight: Int = 0
    var exportScale: CGFloat = 1.0  // 1.0 = original, 0.5 = 50%, etc.
    var dimensionsBtnRect: NSRect = .zero

    // Button rects
    var playBtnRect: NSRect = .zero
    var saveBtnRect: NSRect = .zero
    var saveArrowRect: NSRect = .zero
    var uploadBtnRect: NSRect = .zero
    var copyBtnRect: NSRect = .zero
    var copyArrowRect: NSRect = .zero
    var muteBtnRect: NSRect = .zero
    var finderBtnRect: NSRect = .zero
    var isMuted: Bool = false
    var savedURL: URL?
    var statusMessage: String?
    var statusIsError: Bool = false
    var statusTimer: Timer?

    // Layout
    let controlsH: CGFloat = 140
    let timelinePad: CGFloat = 20

    init(frame: NSRect, videoURL: URL) {
        self.videoURL = videoURL
        self.isGIF = videoURL.pathExtension.lowercased() == "gif"
        super.init(frame: frame)

        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)

        setupPlayer()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setupPlayer() {
        if isGIF {
            setupGIFView()
            return
        }

        let asset = AVAsset(url: videoURL)
        self.asset = asset

        // Store original pixel dimensions
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            originalWidth = Int(abs(size.width))
            originalHeight = Int(abs(size.height))
        }

        Task {
            // Use video track duration (asset duration can be wrong when audio track is present)
            let seconds: Double
            if let videoTrack = asset.tracks(withMediaType: .video).first {
                seconds = CMTimeGetSeconds(videoTrack.timeRange.duration)
            } else if let dur = try? await asset.load(.duration) {
                seconds = CMTimeGetSeconds(dur)
            } else {
                seconds = 0
            }
            await MainActor.run {
                self.duration = max(seconds, 0.1)
                self.trimEnd = self.duration
                self.buildPlayerView()
            }
        }
    }

    func setupGIFView() {
        guard let gifImage = NSImage(contentsOf: videoURL) else { return }
        // Estimate duration from GIF frame count and delay
        if let src = CGImageSourceCreateWithURL(videoURL as CFURL, nil) {
            let count = CGImageSourceGetCount(src)
            var totalDelay: Double = 0
            for i in 0..<count {
                if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [String: Any],
                   let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any],
                   let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? gifProps[kCGImagePropertyGIFDelayTime as String] as? Double {
                    totalDelay += delay
                }
            }
            duration = max(totalDelay, 0.1)
        } else {
            duration = 1.0
        }
        trimEnd = duration

        // Store original GIF dimensions
        if let src = CGImageSourceCreateWithURL(videoURL as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            originalWidth = img.width
            originalHeight = img.height
        }

        let iv = NSImageView()
        iv.image = gifImage
        iv.animates = true
        iv.imageScaling = .scaleProportionallyDown
        iv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        iv.setContentHuggingPriority(.defaultLow, for: .vertical)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        iv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iv)

        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: topAnchor),
            iv.leadingAnchor.constraint(equalTo: leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -controlsH),
        ])
        gifImageView = iv
        gifIsPlaying = true
        gifPlaybackTime = trimStart
        gifPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.gifIsPlaying else { return }
            self.gifPlaybackTime += 1.0/30.0
            if self.gifPlaybackTime >= self.trimEnd {
                self.gifPlaybackTime = self.trimStart
            }
            self.needsDisplay = true
        }
        needsDisplay = true
    }

    func buildPlayerView() {
        let item = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: item)
        self.player = player

        let pv = AVPlayerView()
        pv.player = player
        pv.controlsStyle = .none
        pv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pv)

        NSLayoutConstraint.activate([
            pv.topAnchor.constraint(equalTo: topAnchor),
            pv.leadingAnchor.constraint(equalTo: leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: trailingAnchor),
            pv.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -controlsH),
        ])
        playerView = pv

        // Observe playback position
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self = self, !self.isDraggingScrubber else { return }
            let t = CMTimeGetSeconds(time)
            if t >= self.trimEnd {
                self.player?.pause()
                self.player?.seek(to: CMTime(seconds: self.trimStart, preferredTimescale: 600),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
            }
            self.needsDisplay = true
        }

        generateThumbnails()
        needsDisplay = true
    }

    func generateThumbnails() {
        guard let asset = asset, !thumbnailsGenerating else { return }
        let tlW = bounds.width - timelinePad * 2
        guard tlW > 0 else { return }
        lastThumbnailWidth = tlW
        thumbnailsGenerating = true

        let thumbH: CGFloat = 30
        let thumbW: CGFloat = thumbH * 16 / 9
        let count = max(1, Int(ceil(tlW / thumbW)))
        let dur = duration

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbW * 2, height: thumbH * 2)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var times: [NSValue] = []
        for i in 0..<count {
            let t = dur * Double(i) / Double(count)
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
        }

        var images: [NSImage] = Array(repeating: NSImage(), count: count)
        var idx = 0
        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, cgImage, _, _, _ in
            if let cg = cgImage {
                let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
                images[idx] = img
            }
            idx += 1
            if idx >= count {
                DispatchQueue.main.async {
                    self?.thumbnailImages = images
                    self?.thumbnailsGenerating = false
                    self?.needsDisplay = true
                }
            }
        }
    }

    func cleanup() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        player?.pause()
        player = nil
        playerView?.player = nil
        gifPlaybackTimer?.invalidate()
        gifPlaybackTimer = nil
        // Clean up temp recording file
        try? FileManager.default.removeItem(at: videoURL)
    }

    var currentPlaybackTime: Double {
        if isGIF {
            return gifPlaybackTime
        } else {
            return CMTimeGetSeconds(player?.currentTime() ?? .zero)
        }
    }
}
