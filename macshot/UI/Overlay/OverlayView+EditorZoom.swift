import AppKit
import ObjectiveC

extension OverlayView {

    // MARK: - Editor Zoom (scroll view magnification)

    private var editorZoomRedrawTimer: Timer? {
        get { objc_getAssociatedObject(self, &AssociatedZoomKeys.redrawTimer) as? Timer }
        set { objc_setAssociatedObject(self, &AssociatedZoomKeys.redrawTimer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private var editorZoomTarget: CGFloat {
        get { objc_getAssociatedObject(self, &AssociatedZoomKeys.zoomTarget) as? CGFloat ?? 1.0 }
        set { objc_setAssociatedObject(self, &AssociatedZoomKeys.zoomTarget, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private var editorZoomAnimTimer: Timer? {
        get { objc_getAssociatedObject(self, &AssociatedZoomKeys.animTimer) as? Timer }
        set { objc_setAssociatedObject(self, &AssociatedZoomKeys.animTimer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    private var editorZoomCursorDoc: NSPoint {
        get { objc_getAssociatedObject(self, &AssociatedZoomKeys.cursorDoc) as? NSPoint ?? .zero }
        set { objc_setAssociatedObject(self, &AssociatedZoomKeys.cursorDoc, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private struct AssociatedZoomKeys {
        static var redrawTimer = "editorZoomRedrawTimer"
        static var zoomTarget  = "editorZoomTarget"
        static var animTimer   = "editorZoomAnimTimer"
        static var cursorDoc   = "editorZoomCursorDoc"
    }

    func invalidateEditorZoomTimers() {
        editorZoomRedrawTimer?.invalidate()
        editorZoomRedrawTimer = nil
        editorZoomAnimTimer?.invalidate()
        editorZoomAnimTimer = nil
    }

    func editorZoom(by factor: CGFloat, cursorInWindow: NSPoint, animated: Bool = false) {
        guard let sv = enclosingScrollView else { return }

        if animated {
            if editorZoomAnimTimer == nil {
                editorZoomTarget = sv.magnification
            }
            editorZoomTarget = max(sv.minMagnification, min(sv.maxMagnification, editorZoomTarget * factor))
            editorZoomCursorDoc = convert(cursorInWindow, from: nil)

            if editorZoomAnimTimer == nil {
                editorZoomAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                    guard let self = self, let sv = self.enclosingScrollView else {
                        timer.invalidate()
                        return
                    }
                    let current = sv.magnification
                    let target = self.editorZoomTarget
                    let diff = target - current
                    if abs(diff) < 0.001 {
                        sv.setMagnification(target, centeredAt: self.editorZoomCursorDoc)
                        timer.invalidate()
                        self.editorZoomAnimTimer = nil
                        self.needsDisplay = true
                        if let topBar = sv.superview?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
                            topBar.updateZoom(target)
                        }
                        return
                    }
                    let next = current + diff * 0.25
                    sv.setMagnification(next, centeredAt: self.editorZoomCursorDoc)
                    if let topBar = sv.superview?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
                        topBar.updateZoom(next)
                    }
                }
            }
            return
        }

        let oldMag = sv.magnification
        let newMag = max(sv.minMagnification, min(sv.maxMagnification, oldMag * factor))
        guard newMag != oldMag else { return }

        let cursorInDoc = convert(cursorInWindow, from: nil)
        sv.setMagnification(newMag, centeredAt: cursorInDoc)

        editorZoomRedrawTimer?.invalidate()
        editorZoomRedrawTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.needsDisplay = true
        }

        if let topBar = sv.superview?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
            topBar.updateZoom(newMag)
        }
    }

    private func adjustPendingToolSize(delta: CGFloat) -> Bool {
        switch currentTool {
        case .marker:
            let oldSize = currentMarkerSize
            let newSize = min(100, max(6, oldSize + delta * 0.5))
            guard newSize != oldSize else { return false }
            setActiveStrokeWidth(newSize, for: .marker)
            sharedToolOptionsRowView?.updateStrokeSlider(value: newSize)
            return true
        case .number:
            let oldSize = currentNumberSize
            let newSize = NumberCalloutGeometry.clampSize(oldSize + delta * 0.5)
            guard newSize != oldSize else { return false }
            setActiveStrokeWidth(newSize, for: .number)
            sharedToolOptionsRowView?.updateStrokeSlider(value: newSize)
            return true
        case .loupe:
            let oldSize = currentLoupeSize
            let newSize = min(320, max(40, oldSize + delta * 5))
            guard newSize != oldSize else { return false }
            setActiveStrokeWidth(newSize, for: .loupe)
            sharedToolOptionsRowView?.updateStrokeSlider(value: newSize)
            return true
        case .pencil, .line, .arrow, .rectangle, .ellipse:
            let oldWidth = activeStrokeWidthForTool(currentTool)
            let newWidth = min(30, max(1, oldWidth + delta * 0.5))
            guard newWidth != oldWidth else { return false }
            setActiveStrokeWidth(newWidth, for: currentTool)
            sharedToolOptionsRowView?.updateStrokeSlider(value: newWidth)
            return true
        default:
            return false
        }
    }

    func handleToolAdjustmentScrollWheel(_ event: NSEvent) -> Bool {
        guard state == .selected else { return false }

        let isTrackpadPhased = event.phase != [] || event.momentumPhase != []
        let isCommandScroll = event.modifierFlags.contains(.command)
        guard !isTrackpadPhased, !isCommandScroll else { return false }

        if let ann = selectedAnnotation {
            if ann.tool == .pixelate || ann.tool == .blur { return true }
            let delta = event.deltaY
            let step: CGFloat = 0.5

            scrollPropertyAdjustTimer?.invalidate()
            scrollPropertyAdjustTimer = nil

            if !isScrollAdjustingProperty {
                isScrollAdjustingProperty = true
                setCachedAnnotationLayerExcludingSelected(
                    buildAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
                )
            }

            if ann.tool == .text {
                let oldSize = ann.fontSize
                let newSize = min(200, max(8, oldSize + delta * step))
                if newSize != oldSize {
                    ann.fontSize = newSize
                    needsDisplay = true
                    sharedToolOptionsRowView?.updateFontSizeDisplay(value: newSize)
                    scheduleScrollPropertyCommit { [weak self] in
                        guard let self = self else { return }
                        let snapshot = ann.clone()
                        self.pushPropertyChangeUndo(annotation: ann, snapshot: snapshot)
                    }
                }
                return true
            } else if ann.tool == .number {
                let oldSize = currentNumberSize
                let newSize = NumberCalloutGeometry.clampSize(oldSize + delta * step)
                if newSize != oldSize {
                    currentNumberSize = newSize
                    ann.strokeWidth = currentNumberSize
                    needsDisplay = true
                    sharedToolOptionsRowView?.updateStrokeSlider(value: newSize)
                    scheduleScrollPropertyCommit { [weak self] in
                        guard let self = self else { return }
                        UserDefaults.standard.set(newSize, forKey: "numberStrokeWidth")
                        if self.annotations.contains(where: { $0 === ann }) {
                            let snapshot = ann.clone()
                            self.undoStack.append(.propertyChange(annotation: ann, snapshot: snapshot))
                        }
                    }
                }
                return true
            } else if ann.tool == .marker {
                let oldSize = currentMarkerSize
                let newSize = min(100, max(6, oldSize + delta * step))
                if newSize != oldSize {
                    currentMarkerSize = newSize
                    ann.strokeWidth = currentMarkerSize
                    needsDisplay = true
                    sharedToolOptionsRowView?.updateStrokeSlider(value: newSize)
                    scheduleScrollPropertyCommit { [weak self] in
                        guard let self = self else { return }
                        UserDefaults.standard.set(newSize, forKey: "markerStrokeWidth")
                        if self.annotations.contains(where: { $0 === ann }) {
                            let snapshot = ann.clone()
                            self.undoStack.append(.propertyChange(annotation: ann, snapshot: snapshot))
                        }
                    }
                }
                return true
            } else if ann.tool == .loupe {
                let oldSize = currentLoupeSize
                let oldSnapshot = ann.clone()
                let newSize = min(320, max(50, oldSize + delta * step * 10))
                if newSize != oldSize {
                    currentLoupeSize = newSize
                    let center = NSPoint(x: ann.boundingRect.midX, y: ann.boundingRect.midY)
                    ann.startPoint = NSPoint(x: center.x - newSize / 2, y: center.y - newSize / 2)
                    ann.endPoint = NSPoint(x: center.x + newSize / 2, y: center.y + newSize / 2)
                    ann.bakeLoupe()
                    needsDisplay = true
                    sharedToolOptionsRowView?.updateStrokeSlider(value: newSize)
                    scheduleScrollPropertyCommit { [weak self] in
                        guard let self = self else { return }
                        UserDefaults.standard.set(newSize, forKey: "loupeSize")
                        if self.annotations.contains(where: { $0 === ann }) {
                            self.undoStack.append(.propertyChange(annotation: ann, snapshot: oldSnapshot))
                        }
                    }
                }
                return true
            } else {
                let oldWidth = ann.strokeWidth
                let newWidth = min(30, max(1, oldWidth + delta * step))
                if newWidth != oldWidth {
                    ann.strokeWidth = newWidth
                    setActiveStrokeWidth(newWidth, for: ann.tool)
                    needsDisplay = true
                    sharedToolOptionsRowView?.updateStrokeSlider(value: newWidth)
                    scheduleScrollPropertyCommit { [weak self] in
                        guard let self = self else { return }
                        let snapshot = ann.clone()
                        self.pushPropertyChangeUndo(annotation: ann, snapshot: snapshot)
                    }
                }
                return true
            }
        }

        if adjustPendingToolSize(delta: event.deltaY) {
            needsDisplay = true
            return true
        }

        return false
    }

    // MARK: - Scroll Wheel & Pinch

    override func scrollWheel(with event: NSEvent) {
        if isInsideScrollView {
            if handleToolAdjustmentScrollWheel(event) { return }
            enclosingScrollView?.scrollWheel(with: event)
            return
        }
        guard state == .selected else { return }
        let isTrackpadPhased = event.phase != [] || event.momentumPhase != []
        let isCommandScroll = event.modifierFlags.contains(.command)

        if isTrackpadPhased && !isCommandScroll && currentAnnotation != nil { return }
        if isTrackpadPhased && !isCommandScroll {
            let imageExceedsView =
                canPanAtOneX()
                || (isEditorMode
                    && (selectionRect.height > bounds.height || selectionRect.width > bounds.width))
            guard zoomLevel != 1.0 || imageExceedsView else { return }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            zoomAnchorView.x += dx
            zoomAnchorView.y -= dy
            clampZoomAnchor()
            needsDisplay = true
            return
        }

        if isCommandScroll {
            let cursor = convert(event.locationInWindow, from: nil)
            let delta = event.deltaY
            let factor: CGFloat = 0.1
            setZoom(zoomLevel + delta * factor, cursorView: cursor)
            return
        }

        guard !isTrackpadPhased else { return }
        _ = handleToolAdjustmentScrollWheel(event)
    }

    override func magnify(with event: NSEvent) {
        if isInsideScrollView {
            editorZoom(by: 1.0 + event.magnification, cursorInWindow: event.locationInWindow)
            return
        }
        guard state == .selected else { return }
        let cursor = convert(event.locationInWindow, from: nil)
        setZoom(zoomLevel + event.magnification, cursorView: cursor)
    }
}
