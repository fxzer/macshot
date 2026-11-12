import AppKit

extension OverlayView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        let t0 = CFAbsoluteTimeGetCurrent()
        CaptureDiagnostics.log("[macshot-perf][overlayView] viewDidMoveToWindow BEGIN")
        if let existing = mouseMovedTrackingArea {
            removeTrackingArea(existing)
            mouseMovedTrackingArea = nil
        }
        super.viewDidMoveToWindow()
        CaptureDiagnostics.log(
            "[macshot-perf][overlayView] viewDidMoveToWindow super elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms"
        )
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        mouseMovedTrackingArea = area

        windowSnapCooldown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialWindowSnapDelay) { [weak self] in
            guard let self else { return }
            self.windowSnapCooldown = false
        }

        if showToolbars {
            scheduleDeferredToolbarRebuild(reason: "viewDidMoveToWindow")
        }

        NotificationCenter.default.removeObserver(
            self,
            name: .toolbarColorsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToolbarColorsChanged),
            name: .toolbarColorsDidChange,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: .saveDirectoryDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSaveDirectoryChanged),
            name: .saveDirectoryDidChange,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowScreenChanged),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowBackingPropertiesChanged),
                name: NSWindow.didChangeBackingPropertiesNotification,
                object: window
            )
        }

        setupAspectRatioObservers()
    }

    override func mouseMoved(with event: NSEvent) {
        if isSharingActive {
            NSCursor.arrow.set()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        clearKeyboardColorSamplerPoint()

        let mouseCurrentlyOnScreen = isMouseOnCurrentScreen()
        if mouseCurrentlyOnScreen != isMouseOnThisScreen {
            isMouseOnThisScreen = mouseCurrentlyOnScreen
            needsDisplay = true
            overlayDelegate?.overlayViewDidChangeMouseLocation()
        }

        if colorWheel.isVisible && colorWheel.isSticky {
            colorWheel.updateHover(at: point)
            needsDisplay = true
            return
        }

        updateCursorForPoint(point)
        updateToolCursorPreviews(at: point)

        if autoMeasureKeyHeld {
            updateAutoMeasurePreview()
        }

        if windowSnapCooldown { return }
        if state == .idle && windowSnapEnabled && !windowSnapQueryInFlight
            && !(remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1)
        {
            guard
                let screenPoint = window.map({
                    NSPoint(x: $0.frame.origin.x + point.x, y: $0.frame.origin.y + point.y)
                })
            else { return }
            queryWindowSnap(at: screenPoint)
        }

        updateMagnifierIfNeeded()
    }

    override func cursorUpdate(with event: NSEvent) {
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateCursorForPoint(point)
        updateToolCursorPreviews(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearDrawingCursorPreview()
        clearLoupePreview()
        clearStampPreview()
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func resetCursorRects() {
    }

    func findTopBar() -> EditorTopBarView? {
        chromeParentView?.subviews.compactMap { $0 as? EditorTopBarView }.first
    }

    func isPointOnChrome(_ point: NSPoint) -> Bool {
        if showToolbars {
            if let strip = bottomStripView, !strip.isHidden, strip.frame.contains(point) {
                return true
            }
            if let strip = rightStripView, !strip.isHidden, strip.frame.contains(point) {
                return true
            }
            if let row = toolOptionsRowView, !row.isHidden, row.frame.contains(point) {
                return true
            }
        }
        if updateCursorForChrome(at: point) { return true }
        if widthLabelRect.contains(point) || heightLabelRect.contains(point) { return true }
        if zoomLabelRect.contains(point) && zoomLabelOpacity > 0 { return true }
        return false
    }

    private func setupAspectRatioObservers() {
        if let observer = aspectRatioObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = aspectRatioShortcutObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        aspectRatioObserver = NotificationCenter.default.addObserver(
            forName: .aspectRatiosDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }

        aspectRatioShortcutObserver = NotificationCenter.default.addObserver(
            forName: .aspectRatioShortcutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    @objc private func handleToolbarColorsChanged() {
        toolOptionsRowView?.layer?.backgroundColor = ToolbarLayout.bgColor.cgColor
        toolOptionsRowView?.appearance = ToolbarLayout.appearance
        rebuildToolbarLayout()
        if let tool = toolOptionsRowView?.currentTool {
            toolOptionsRowView?.rebuild(for: tool)
        }
        needsDisplay = true
    }

    @objc private func handleSaveDirectoryChanged() {
        rebuildToolbarLayout()
        needsDisplay = true
    }

    @objc private func handleWindowScreenChanged() {
        invalidateScaleDependentRenderCaches()
    }

    @objc private func handleWindowBackingPropertiesChanged() {
        invalidateScaleDependentRenderCaches()
    }

    private func invalidateScaleDependentRenderCaches() {
        invalidateAnnotationCaches()
        cachedCompositedImage = nil
        needsDisplay = true
    }


}
