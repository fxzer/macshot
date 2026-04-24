import Cocoa
import AVFoundation
import AVKit
import UniformTypeIdentifiers

extension VideoEditorView {

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Trim handles
        let handleHitW: CGFloat = 16
        let startX = timelineRect.minX + CGFloat(trimStart / duration) * timelineRect.width
        let endX = timelineRect.minX + CGFloat(trimEnd / duration) * timelineRect.width

        if abs(point.x - startX) < handleHitW && abs(point.y - timelineRect.midY) < 25 {
            isDraggingStart = true; return
        }
        if abs(point.x - endX) < handleHitW && abs(point.y - timelineRect.midY) < 25 {
            isDraggingEnd = true; return
        }

        // Scrub timeline
        if timelineRect.insetBy(dx: 0, dy: -10).contains(point) {
            isDraggingScrubber = true
            scrubTo(point: point)
            return
        }

        // Format toggle
        if formatMP4Rect.contains(point) && exportAsGIF {
            exportAsGIF = false; savedURL = nil; needsDisplay = true; return
        }
        if formatGIFRect.contains(point) && !exportAsGIF {
            exportAsGIF = true; savedURL = nil; needsDisplay = true; return
        }

        // Dimensions dropdown
        if dimensionsBtnRect.contains(point) && originalWidth > 0 {
            showDimensionsMenu(); return
        }

        // Buttons
        if playBtnRect.contains(point) { togglePlayPause(); return }
        if muteBtnRect.contains(point) { toggleMute(); return }
        if saveArrowRect.contains(point) { showSaveMenu(); return }
        if saveBtnRect.contains(point) { saveVideo(); return }
        if uploadBtnRect.contains(point) { uploadVideo(); return }
        if finderBtnRect.contains(point) {
            if let url = savedURL { _ = FinderRevealService.reveal(url) }
            return
        }
        if copyArrowRect.contains(point) { showCopyMenu(); return }
        if copyBtnRect.contains(point) { copyToClipboard(); return }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let t = max(0, min(duration, Double((point.x - timelineRect.minX) / timelineRect.width) * duration))

        if isDraggingStart {
            trimStart = min(t, trimEnd - 0.1)
            player?.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            needsDisplay = true
        } else if isDraggingEnd {
            trimEnd = max(t, trimStart + 0.1)
            player?.seek(to: CMTime(seconds: trimEnd, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            needsDisplay = true
        } else if isDraggingScrubber {
            scrubTo(point: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingStart = false
        isDraggingEnd = false
        isDraggingScrubber = false
    }

    func scrubTo(point: NSPoint) {
        let t = max(trimStart, min(trimEnd, Double((point.x - timelineRect.minX) / timelineRect.width) * duration))
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        needsDisplay = true
    }
}
