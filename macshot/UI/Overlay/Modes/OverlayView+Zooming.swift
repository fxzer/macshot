//
//  OverlayView+Zooming.swift
//  macshot
//
//  Zoom management for OverlayView:
//  coordinate transforms, zoom state, zoom label/input, loupe preview,
//  scroll wheel and trackpad pinch handling.
//

import AppKit
import ObjectiveC

private enum OverlayZoomAssociatedKeys {
    static var level: UInt8 = 0
    static var anchorCanvas: UInt8 = 0
    static var anchorView: UInt8 = 0
    static var fadingOut: UInt8 = 0
    static var labelOpacity: UInt8 = 0
    static var fadeTimer: UInt8 = 0
    static var labelRect: UInt8 = 0
}

extension OverlayView {

    // MARK: - Coordinate Transforms

    /// Convert a canvas-space point to view-space (reverse of viewToCanvas).
    func canvasToView(_ p: NSPoint) -> NSPoint {
        if isInsideScrollView { return restorePointFromEditor(p) }
        var q = p
        if zoomLevel != 1.0 || zoomAnchorCanvas != .zero || zoomAnchorView != .zero {
            q = NSPoint(
                x: zoomAnchorView.x + (p.x - zoomAnchorCanvas.x) * zoomLevel,
                y: zoomAnchorView.y + (p.y - zoomAnchorCanvas.y) * zoomLevel
            )
        }
        return restorePointFromEditor(q)
    }

    /// Convert a point in view space to canvas (annotation) space by reversing the zoom transform.
    func viewToCanvas(_ p: NSPoint) -> NSPoint {
        if isInsideScrollView { return adjustPointForEditor(p) }
        let q = adjustPointForEditor(p)
        if zoomLevel == 1.0 && zoomAnchorCanvas == .zero && zoomAnchorView == .zero { return q }
        guard zoomAnchorCanvas != .zero || zoomAnchorView != .zero else { return q }
        return NSPoint(
            x: zoomAnchorCanvas.x + (q.x - zoomAnchorView.x) / zoomLevel,
            y: zoomAnchorCanvas.y + (q.y - zoomAnchorView.y) / zoomLevel
        )
    }

    func applyZoomTransform(to context: NSGraphicsContext) {
        if isInsideScrollView { return }
        if zoomLevel == 1.0 && zoomAnchorCanvas == .zero && zoomAnchorView == .zero { return }
        guard zoomAnchorCanvas != .zero || zoomAnchorView != .zero else { return }
        let cgCtx = context.cgContext
        // screen = anchorView + (canvas - anchorCanvas) * zoom
        cgCtx.translateBy(
            x: zoomAnchorView.x - zoomAnchorCanvas.x * zoomLevel,
            y: zoomAnchorView.y - zoomAnchorCanvas.y * zoomLevel)
        cgCtx.scaleBy(x: zoomLevel, y: zoomLevel)
    }

    /// Apply editor canvas offset + zoom transform. Use this for all canvas-space drawing.
    func applyCanvasTransform(to context: NSGraphicsContext) {
        applyEditorTransform(to: context)
        applyZoomTransform(to: context)
    }

    // MARK: - Zoom State

    /// Set zoom level, pinning the given view-space cursor point in place.
    func setZoom(_ level: CGFloat, cursorView: NSPoint) {
        let canvasUnderCursor = viewToCanvas(cursorView)
        zoomLevel = max(zoomMin, min(zoomMax, level))

        if abs(zoomLevel - 1.0) < 0.005 {
            zoomLevel = 1.0
            zoomAnchorCanvas = .zero
            zoomAnchorView = .zero
        } else {
            zoomAnchorCanvas = canvasUnderCursor
            zoomAnchorView = cursorView
            clampZoomAnchor()
        }
        showZoomLabel()
        needsDisplay = true
    }

    /// Reset zoom to 1× (no transform).
    func resetZoom() {
        zoomLevel = 1.0
        zoomAnchorCanvas = .zero
        zoomAnchorView = .zero
    }

    /// Clamp zoomAnchorView so the image doesn't scroll out of the visible area.
    ///
    /// zoom > 1×: keep all four image edges inside selectionRect (no empty border visible).
    /// zoom < 1×: allow free panning but keep image partially visible.
    func clampZoomAnchor() {
        if zoomLevel == 1.0 { return }
        let r = selectionRect
        let z = zoomLevel
        let ac = zoomAnchorCanvas
        var av = zoomAnchorView

        if z > 1.0 {
            let maxAVx = r.minX - (r.minX - ac.x) * z
            let minAVx = r.maxX - (r.maxX - ac.x) * z
            av.x = max(minAVx, min(maxAVx, av.x))

            let maxAVy = r.minY - (r.minY - ac.y) * z
            let minAVy = r.maxY - (r.maxY - ac.y) * z
            av.y = max(minAVy, min(maxAVy, av.y))
        }

        zoomAnchorView = av
    }

    // MARK: - Zoom Label & Fade

    func showZoomLabel() {
        zoomLabelOpacity = 1.0
        zoomFadingOut = false
        zoomFadeTimer?.invalidate()
        zoomFadeTimer = nil
        if zoomLevel == 1.0 {
            zoomFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) {
                [weak self] _ in
                self?.fadeOutZoomLabel()
            }
        }
    }

    func fadeOutZoomLabel() {
        guard zoomLevel == 1.0 else { return }
        zoomFadingOut = true
        let step: CGFloat = 0.08
        zoomFadeTimer?.invalidate()
        zoomFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.zoomLevel != 1.0 {
                self.zoomLabelOpacity = 1.0
                self.zoomFadingOut = false
                timer.invalidate()
                if self.zoomFadeTimer === timer { self.zoomFadeTimer = nil }
                self.needsDisplay = true
                return
            }
            self.zoomLabelOpacity -= step
            if self.zoomLabelOpacity <= 0 {
                self.zoomLabelOpacity = 0
                self.zoomFadingOut = false
                timer.invalidate()
                if self.zoomFadeTimer === timer { self.zoomFadeTimer = nil }
            }
            self.needsDisplay = true
        }
    }

    // MARK: - Zoom Label Drawing

    func drawZoomLabel() {
        let sizeLabelRect = sharedSizeLabelRect
        guard sizeLabelRect != .zero else { return }
        let zoom = zoomLevel
        let text: String
        if abs(zoom - 1.0) < 0.005 {
            text = "1×"
        } else if zoom >= 10 {
            text = String(format: "%.0f×", zoom)
        } else {
            text = String(format: "%.1f×", zoom).replacingOccurrences(of: ".0×", with: "×")
        }

        let alpha = zoomLabelOpacity
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.sharedSizeLabelFont,
            .foregroundColor: ToolbarLayout.iconColor.withAlphaComponent(alpha),
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 6
        let labelW = textSize.width + padding * 2
        let labelH = sizeLabelRect.height
        let gap: CGFloat = 6
        let edge: CGFloat = 4
        let labelY = sizeLabelRect.minY

        var labelX = sizeLabelRect.maxX + gap
        if labelX + labelW > bounds.maxX - edge {
            let leftX = sizeLabelRect.minX - gap - labelW
            if leftX >= bounds.minX + edge {
                labelX = leftX
            }
        }
        labelX = min(max(labelX, bounds.minX + edge), bounds.maxX - edge - labelW)

        let rect = NSRect(x: labelX, y: labelY, width: labelW, height: labelH)
        zoomLabelRect = rect

        let bgColor = ToolbarLayout.bgColor.withAlphaComponent(alpha * 0.85)
        bgColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: NSPoint(x: labelX + padding, y: labelY + padding / 2), withAttributes: attrs)
    }

    // MARK: - Crop

    /// Crop the screenshot to `viewRect` (canvas-space, within selectionRect),
    /// translate all annotations accordingly, and reset zoom.
    func commitCrop(viewRect: NSRect) {
        guard let originalImage = screenshotImage,
            let cgOriginal = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let canvasRect = viewRect
        let pointsW = originalImage.size.width
        let pixScale = CGFloat(cgOriginal.width) / pointsW

        let normX = (canvasRect.minX - selectionRect.minX) / selectionRect.width
        let normY = (canvasRect.minY - selectionRect.minY) / selectionRect.height
        let normW = canvasRect.width / selectionRect.width
        let normH = canvasRect.height / selectionRect.height

        let cgW = CGFloat(cgOriginal.width)
        let cgH = CGFloat(cgOriginal.height)
        let cgPixelRect = CGRect(
            x: max(0, normX * cgW),
            y: max(0, (1.0 - normY - normH) * cgH),
            width: min(normW * cgW, cgW - max(0, normX * cgW)),
            height: min(normH * cgH, cgH - max(0, (1.0 - normY - normH) * cgH))
        )

        guard cgPixelRect.width > 0, cgPixelRect.height > 0,
            let croppedCG = cgOriginal.cropping(to: cgPixelRect)
        else { return }

        let prevImage = originalImage.copy() as! NSImage
        undoStack.append(.imageTransform(previousImage: prevImage, annotationOffsets: []))
        redoStack.removeAll()

        let dx = selectionRect.minX - canvasRect.minX
        let dy = selectionRect.minY - canvasRect.minY
        for ann in annotations { ann.move(dx: dx, dy: dy) }

        let croppedPointSize = NSSize(
            width: CGFloat(croppedCG.width) / pixScale,
            height: CGFloat(croppedCG.height) / pixScale)
        replaceScreenshotImage(croppedCG, size: croppedPointSize)
        selectionRect = NSRect(origin: .zero, size: croppedPointSize)
        cachedCompositedImage = nil

        if isInsideScrollView {
            frame.size = croppedPointSize
            enclosingScrollView?.magnification = 1.0
            if let topBar = chromeParentView?.subviews.compactMap({ $0 as? EditorTopBarView }).first {
                topBar.updateSizeLabel(width: croppedCG.width, height: croppedCG.height)
                topBar.updateZoom(1.0)
            }
        } else {
            resetZoom()
        }
        currentTool = .arrow
        rebuildToolbarLayout()
        needsDisplay = true
    }

    var zoomLevel: CGFloat {
        get { associatedCGFloat(for: &OverlayZoomAssociatedKeys.level, default: 1.0) }
        set { setAssociatedCGFloat(newValue, for: &OverlayZoomAssociatedKeys.level) }
    }

    var zoomAnchorCanvas: NSPoint {
        get { associatedPoint(for: &OverlayZoomAssociatedKeys.anchorCanvas) }
        set { setAssociatedPoint(newValue, for: &OverlayZoomAssociatedKeys.anchorCanvas) }
    }

    var zoomAnchorView: NSPoint {
        get { associatedPoint(for: &OverlayZoomAssociatedKeys.anchorView) }
        set { setAssociatedPoint(newValue, for: &OverlayZoomAssociatedKeys.anchorView) }
    }

    var zoomFadingOut: Bool {
        get { associatedBool(for: &OverlayZoomAssociatedKeys.fadingOut) }
        set { setAssociatedBool(newValue, for: &OverlayZoomAssociatedKeys.fadingOut) }
    }

    var zoomLabelOpacity: CGFloat {
        get { associatedCGFloat(for: &OverlayZoomAssociatedKeys.labelOpacity, default: 0.0) }
        set { setAssociatedCGFloat(newValue, for: &OverlayZoomAssociatedKeys.labelOpacity) }
    }

    var zoomFadeTimer: Timer? {
        get { objc_getAssociatedObject(self, &OverlayZoomAssociatedKeys.fadeTimer) as? Timer }
        set {
            objc_setAssociatedObject(
                self,
                &OverlayZoomAssociatedKeys.fadeTimer,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var zoomMin: CGFloat { 1.0 }
    var zoomMax: CGFloat { 8.0 }

    var zoomLabelRect: NSRect {
        get { associatedRect(for: &OverlayZoomAssociatedKeys.labelRect) }
        set { setAssociatedRect(newValue, for: &OverlayZoomAssociatedKeys.labelRect) }
    }

    func shouldIgnoreZoomLabelMouseDown(at point: NSPoint) -> Bool {
        zoomLabelOpacity > 0 && zoomLabelRect.contains(point)
    }

    func resetZoomUIState() {
        zoomLabelOpacity = 0.0
        zoomFadingOut = false
        zoomFadeTimer?.invalidate()
        zoomFadeTimer = nil
        zoomLabelRect = .zero
    }

    private func associatedCGFloat(for key: UnsafeRawPointer, default defaultValue: CGFloat) -> CGFloat {
        guard let number = objc_getAssociatedObject(self, key) as? NSNumber else { return defaultValue }
        return CGFloat(number.doubleValue)
    }

    private func setAssociatedCGFloat(_ value: CGFloat, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSNumber(value: Double(value)),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func associatedBool(for key: UnsafeRawPointer) -> Bool {
        (objc_getAssociatedObject(self, key) as? NSNumber)?.boolValue ?? false
    }

    private func setAssociatedBool(_ value: Bool, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSNumber(value: value),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func associatedPoint(for key: UnsafeRawPointer) -> NSPoint {
        (objc_getAssociatedObject(self, key) as? NSValue)?.pointValue ?? .zero
    }

    private func setAssociatedPoint(_ value: NSPoint, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSValue(point: value),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private func associatedRect(for key: UnsafeRawPointer) -> NSRect {
        (objc_getAssociatedObject(self, key) as? NSValue)?.rectValue ?? .zero
    }

    private func setAssociatedRect(_ value: NSRect, for key: UnsafeRawPointer) {
        objc_setAssociatedObject(
            self,
            key,
            NSValue(rect: value),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

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
                    buildInteractionAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
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
                        let snapshot = ann.propertyChangeSnapshot()
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
                            let snapshot = ann.propertyChangeSnapshot()
                            self.pushPropertyChangeUndo(annotation: ann, snapshot: snapshot)
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
                            let snapshot = ann.propertyChangeSnapshot()
                            self.pushPropertyChangeUndo(annotation: ann, snapshot: snapshot)
                        }
                    }
                }
                return true
            } else if ann.tool == .loupe {
                let oldSize = currentLoupeSize
                let oldSnapshot = ann.propertyChangeSnapshot()
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
                            self.pushPropertyChangeUndo(annotation: ann, snapshot: oldSnapshot)
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
                        let snapshot = ann.propertyChangeSnapshot()
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
