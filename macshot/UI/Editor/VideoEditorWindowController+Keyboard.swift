import Cocoa
import AVFoundation
import AVKit
import UniformTypeIdentifiers

extension VideoEditorView {

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space
            togglePlayPause()
        case 123: // Left arrow — step back one frame
            stepFrame(forward: false)
        case 124: // Right arrow — step forward one frame
            stepFrame(forward: true)
        default:
            super.keyDown(with: event)
        }
    }

    func stepFrame(forward: Bool) {
        guard let player = player else { return }
        // Pause if playing
        if player.rate > 0 { player.pause(); needsDisplay = true }

        let fps = asset?.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30
        let frameDuration = 1.0 / Double(fps)
        let current = CMTimeGetSeconds(player.currentTime())
        let target = forward
            ? min(current + frameDuration, trimEnd)
            : max(current - frameDuration, trimStart)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        needsDisplay = true
    }
}
