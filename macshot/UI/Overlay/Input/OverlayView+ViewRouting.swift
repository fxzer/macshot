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
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
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
            scheduleDeferredToolbarRebuild()
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

    override func resetCursorRects() {
    }

    func findTopBar() -> EditorTopBarView? {
        chromeParentView?.subviews.compactMap { $0 as? EditorTopBarView }.first
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !isEditorMode {
            let localPoint = convert(point, from: superview)
            if let strip = bottomStripView, !strip.isHidden, strip.frame.contains(localPoint) {
                return strip.hitTest(convert(point, to: strip.superview))
            }
            if let strip = rightStripView, !strip.isHidden, strip.frame.contains(localPoint) {
                return strip.hitTest(convert(point, to: strip.superview))
            }
            if let row = toolOptionsRowView, !row.isHidden, row.frame.contains(localPoint) {
                return row.hitTest(convert(point, to: row.superview))
            }
        }
        return super.hitTest(point)
    }

    func isPointOnChrome(_ point: NSPoint) -> Bool {
        if showToolbars && !isEditorMode {
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

    func hitTestLiveTextResizeHandle(at point: NSPoint, frame: NSRect) -> ResizeHandle? {
        for (handle, rect) in liveTextResizeHandles(for: frame) where rect.contains(point) {
            return handle
        }
        return nil
    }

    func isPointOnLiveTextDragEdge(_ point: NSPoint, frame: NSRect) -> Bool {
        let horizontalBleed: CGFloat = 6
        let topOutsidePadding: CGFloat = 8
        let topInsidePadding: CGFloat = 6
        let topRect = NSRect(
            x: frame.minX - horizontalBleed,
            y: frame.maxY - topInsidePadding,
            width: frame.width + horizontalBleed * 2,
            height: topInsidePadding + topOutsidePadding)
        return topRect.contains(point)
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

    private func liveTextResizeHandles(for frame: NSRect) -> [(ResizeHandle, NSRect)] {
        let handleSize: CGFloat = 10
        return [
            (.bottomLeft, NSRect(x: frame.minX - handleSize / 2, y: frame.minY - handleSize / 2, width: handleSize, height: handleSize)),
            (.bottomRight, NSRect(x: frame.maxX - handleSize / 2, y: frame.minY - handleSize / 2, width: handleSize, height: handleSize)),
            (.topLeft, NSRect(x: frame.minX - handleSize / 2, y: frame.maxY - handleSize / 2, width: handleSize, height: handleSize)),
            (.topRight, NSRect(x: frame.maxX - handleSize / 2, y: frame.maxY - handleSize / 2, width: handleSize, height: handleSize)),
            (.bottom, NSRect(x: frame.midX - handleSize / 2, y: frame.minY - handleSize / 2, width: handleSize, height: handleSize)),
            (.top, NSRect(x: frame.midX - handleSize / 2, y: frame.maxY - handleSize / 2, width: handleSize, height: handleSize)),
            (.left, NSRect(x: frame.minX - handleSize / 2, y: frame.midY - handleSize / 2, width: handleSize, height: handleSize)),
            (.right, NSRect(x: frame.maxX - handleSize / 2, y: frame.midY - handleSize / 2, width: handleSize, height: handleSize)),
        ]
    }
}
