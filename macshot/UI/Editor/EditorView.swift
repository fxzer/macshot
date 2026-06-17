import Cocoa

/// Standalone editor view — subclass of OverlayView for the editor window.
/// NSScrollView handles zoom, pan, centering, momentum.
class EditorView: OverlayView {

    override var isEditorMode: Bool { true }
    override var isInsideScrollView: Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Ensure the view redraws fully on magnification changes instead of
        // scaling the stale layer contents (which causes blurry regions).
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    // MARK: - Background drawing (simple — NSScrollView handles centering/zoom)

    override func drawEditorBackground(context: NSGraphicsContext) {
        // NSScrollView.backgroundColor handles the dark background.
        // CenteringClipView handles centering. Magnification handles zoom.
        guard !beautifyEnabled else { return }

        // Fast path: if we have a cached composite (screenshot + all committed annotations)
        // and nothing is actively being drawn, draw the single cached image.
        // This avoids re-rendering the screenshot + iterating all annotations every frame.
        if !isActivelyDrawing, let cached = cachedCompositedImage {
            cached.draw(in: selectionRect, from: .zero, operation: .copy, fraction: 1.0)
            drewFromCompositeCache = true
            return
        }

        drewFromCompositeCache = false
        if let image = screenshotImage {
            image.draw(in: selectionRect, from: .zero, operation: .copy, fraction: 1.0)
        }
    }

    /// Set during drawEditorBackground to signal the base draw() to skip annotation loops.
    var drewFromCompositeCache: Bool = false

    // MARK: - Selection chrome (disabled in editor)

    override func shouldClipSelectionImage() -> Bool { false }
    override func shouldDrawSelectionBorder() -> Bool { false }
    override func shouldDrawSizeLabel() -> Bool { false }

    // MARK: - Coordinate transforms
    // Base: identity (scroll view handles zoom/pan).
    // When beautify is active, the actual image/annotation canvas is shifted by
    // beautifyEditorOffset inside the enlarged document view, so hit-testing and
    // cursor previews must apply the inverse offset too.

    override func adjustPointForEditor(_ p: NSPoint) -> NSPoint {
        let off = beautifyEditorOffset
        return off == .zero ? p : NSPoint(x: p.x - off.x, y: p.y - off.y)
    }

    override func restorePointFromEditor(_ p: NSPoint) -> NSPoint {
        let off = beautifyEditorOffset
        return off == .zero ? p : NSPoint(x: p.x + off.x, y: p.y + off.y)
    }

    override func applyEditorTransform(to context: NSGraphicsContext) {
        let off = beautifyEditorOffset
        if off != .zero {
            context.cgContext.translateBy(x: off.x, y: off.y)
        }
    }

    // MARK: - Cursor (arrow outside image, tool cursor inside)

    override func resetCursorRects() {
        // Arrow cursor for the full document view; updateCursorForPoint overrides
        // this with the tool cursor only when the mouse is over the image area.
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        if isSharingActive {
            NSCursor.arrow.set()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if pointIsInSelection(point) {
            super.mouseMoved(with: event)
        } else {
            cursorVisualMode = .system
            updateToolCursorPreviews(at: point)
            NSCursor.arrow.set()
        }
    }

    // MARK: - Selection interaction (disabled in editor)

    override func shouldAllowSelectionResize() -> Bool { false }
    override func shouldAllowNewSelection() -> Bool { false }
    override func shouldAllowDetach() -> Bool { false }

    // MARK: - Zoom (not needed — NSScrollView handles it)

    override func canPanAtOneX() -> Bool { false }
    override func clampZoomAnchorForEditor(r: NSRect, z: CGFloat, ac: NSPoint, av: inout NSPoint) {}

    // MARK: - Export

    override var captureDrawRect: NSRect { selectionRect }

    // Top bar is handled by EditorTopBarView (real NSView in the container)
}
