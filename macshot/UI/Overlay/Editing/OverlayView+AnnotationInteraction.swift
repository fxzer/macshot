//
//  OverlayView+AnnotationInteraction.swift
//  macshot
//
//  Annotation creation and selection interaction helpers.
//

import AppKit

extension OverlayView {

    // MARK: - Annotation Creation

    func startAnnotation(at point: NSPoint) {
        let isPencilTool = currentTool == .pencil

        if selectedAnnotations.count > 1 && multiSelectDeleteButtonRect.contains(point) {
            for ann in selectedAnnotations {
                if let idx = annotations.firstIndex(where: { $0 === ann }) {
                    annotations.remove(at: idx)
                    undoStack.append(.deleted(ann, idx))
                }
            }
            redoStack.removeAll()
            selectedAnnotations = []
            cachedCompositedImage = nil
            needsDisplay = true
            return
        }

        if currentTool != .colorSampler {
            if let selected = selectedAnnotation {
                if handleSelectedAnnotationClick(selected, at: point) { return }
            }
        }

        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        let ctrlHeld = NSEvent.modifierFlags.contains(.control)
        let pencilHasMultiSelection = isPencilTool && selectedAnnotations.count > 1
        let textHasSelection = currentTool == .text && !selectedAnnotations.isEmpty
        let useInstantSelect = currentTool != .colorSampler
            && currentTool != .stamp
            && (currentTool != .text || shiftHeld || textHasSelection)
            && (!isPencilTool || shiftHeld || ctrlHeld || pencilHasMultiSelection)
        if useInstantSelect {
            if let clicked = annotations.reversed().first(where: { $0.isMovable && $0.hitTest(point: point) }) {
                shiftClickPendingDeselect = nil
                if shiftHeld {
                    if isSelected(clicked) {
                        shiftClickPendingDeselect = clicked
                    } else {
                        selectedAnnotations.append(clicked)
                    }
                } else if !isSelected(clicked) {
                    selectedAnnotation = clicked
                }
                isDraggingAnnotation = true
                didMoveAnnotation = false
                annotationDragStart = point
                setCachedAnnotationLayerExcludingSelected(
                    buildInteractionAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
                )
                NSCursor.closedHand.set()
                needsDisplay = true
                return
            }
        }

        if ctrlHeld {
            isLassoSelecting = true
            lassoStart = point
            lassoRect = .zero
            needsDisplay = true
            return
        }

        if isPencilTool && !shiftHeld {
            let hasAnnotationUnder = annotations.reversed().contains(where: {
                $0.isMovable && $0.hitTest(point: point)
            })
            if hasAnnotationUnder {
                longPressPoint = point
                longPressTriggered = false
                longPressTimer?.invalidate()
                longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) {
                    [weak self] _ in
                    guard let self = self else { return }
                    self.longPressTriggered = true
                    self.longPressTimer = nil
                    if let clicked = self.annotations.reversed().first(where: {
                        $0.isMovable && $0.hitTest(point: point)
                    }) {
                        self.shiftClickPendingDeselect = nil
                        if NSEvent.modifierFlags.contains(.shift) {
                            if self.isSelected(clicked) {
                                self.shiftClickPendingDeselect = clicked
                            } else {
                                self.selectedAnnotations.append(clicked)
                            }
                        } else if !self.isSelected(clicked) {
                            self.selectedAnnotation = clicked
                        }
                        self.isDraggingAnnotation = true
                        self.didMoveAnnotation = false
                        self.annotationDragStart = point
                        self.setCachedAnnotationLayerExcludingSelected(
                            self.buildInteractionAnnotationLayer(
                                excluding: Set(self.selectedAnnotations.map { ObjectIdentifier($0) }))
                        )
                        self.currentAnnotation = nil
                        NSCursor.closedHand.set()
                        self.needsDisplay = true
                    }
                }
            }
        }

        if !selectedAnnotations.isEmpty { selectedAnnotations = [] }

        if let handler = toolHandlers[currentTool] {
            if let annotation = handler.start(at: point, canvas: self) {
                currentAnnotation = annotation
                needsDisplay = true
            }
            return
        }

        if currentTool == .colorSampler {
            if let screenshot = screenshotImage,
                let result = sampleColor(from: screenshot, at: point, gamut: currentColorGamut)
            {
                currentColor = result.color
                currentColorOpacity = 1.0
                OverlayView.lastUsedOpacity = 1.0
                UserDefaults.standard.set(1.0, forKey: "lastUsedColorOpacity")
                if selectedColorSlot >= 0 && selectedColorSlot < customColors.count {
                    customColors[selectedColorSlot] = result.color.withAlphaComponent(1.0)
                    saveCustomColors()
                    let nextSlot = selectedColorSlot + 1
                    if nextSlot < customColors.count { selectedColorSlot = nextSlot }
                }
                showColorCopiedHint(String(format: L("Set color %@"), result.hex), colorString: result.hex)
                rebuildToolbarLayout()
                needsDisplay = true
            }
            return
        }

        if currentTool == .text {
            if let existingAnn = annotations.reversed().first(where: {
                $0.tool == .text && $0.hitTest(point: point)
            }) {
                selectedAnnotation = existingAnn
                needsDisplay = true
                if let event = NSApp.currentEvent, event.clickCount >= 2 {
                    textEditor.editingAnnotation = existingAnn
                    textEditor.restoreState(from: existingAnn)
                    if let idx = annotations.firstIndex(where: { $0 === existingAnn }) {
                        annotations.remove(at: idx)
                        selectedAnnotation = nil
                    }
                    showTextField(
                        at: existingAnn.textDrawRect.origin,
                        existingText: existingAnn.attributedText,
                        existingFrame: existingAnn.textDrawRect)
                    cachedCompositedImage = nil
                }
            } else {
                showTextField(at: point)
            }
        }
    }

    /// In select mode, selected annotation controls must consume clicks before the
    /// canvas drag branch, otherwise buttons like delete can be swallowed by selection drag.
    func handleSelectionChromePriorityClick(at viewPoint: NSPoint) -> Bool {
        let canvasPoint = viewToCanvas(viewPoint)

        if selectedAnnotations.count > 1 && multiSelectDeleteButtonRect.contains(canvasPoint) {
            for ann in selectedAnnotations {
                if let idx = annotations.firstIndex(where: { $0 === ann }) {
                    annotations.remove(at: idx)
                    undoStack.append(.deleted(ann, idx))
                }
            }
            redoStack.removeAll()
            selectedAnnotations = []
            cachedCompositedImage = nil
            needsDisplay = true
            return true
        }

        if let selected = selectedAnnotation {
            return handleSelectedAnnotationClick(selected, at: canvasPoint)
        }

        return false
    }

    func updateAnnotation(at point: NSPoint, shiftHeld: Bool = false) {
        guard let annotation = currentAnnotation else { return }
        if let handler = toolHandlers[annotation.tool] {
            handler.update(to: point, shiftHeld: shiftHeld, canvas: self)
        }
    }

    func finishAnnotation(_ annotation: Annotation) {
        if let handler = toolHandlers[annotation.tool] {
            handler.finish(canvas: self)
        }
    }

    /// Handle click on the selected annotation's controls (resize handles, rotation, delete).
    /// Returns true if the click was consumed. Does NOT check the annotation body — that's
    /// handled by the caller's hit-test loop.
    private func handleSelectedAnnotationClick(_ selected: Annotation, at point: NSPoint) -> Bool {
        let handleTestPoint: NSPoint
        if selected.rotation != 0 && selected.supportsRotation {
            let center = NSPoint(x: selected.boundingRect.midX, y: selected.boundingRect.midY)
            let cos_r = cos(-selected.rotation)
            let sin_r = sin(-selected.rotation)
            let dx = point.x - center.x
            let dy = point.y - center.y
            handleTestPoint = NSPoint(
                x: center.x + dx * cos_r - dy * sin_r,
                y: center.y + dx * sin_r + dy * cos_r)
        } else {
            handleTestPoint = point
        }
        for (handleIdx, handleEntry) in annotationResizeHandleRects.enumerated() {
            let (handle, rect) = handleEntry
            if rect.insetBy(dx: -4, dy: -4).contains(handleTestPoint) {
                isResizingAnnotation = true
                setCachedAnnotationLayerExcludingSelected(
                    buildInteractionAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
                )
                annotationResizeHandle = handle
                annotationResizeOrigStart = selected.startPoint
                annotationResizeOrigEnd = selected.endPoint
                annotationResizeOrigTextOrigin = selected.textDrawRect.origin
                annotationResizeOrigFontSize = selected.fontSize
                annotationResizeMouseStart = point
                annotationResizeAnchorIndex = -1
                if let anchors = selected.anchorPoints, anchors.count >= 3, handleIdx >= 2 {
                    let anchorIdx = handleIdx - 2 + 1
                    if anchorIdx > 0 && anchorIdx < anchors.count - 1 {
                        annotationResizeAnchorIndex = anchorIdx
                        annotationResizeOrigControlPoint = anchors[anchorIdx]
                    }
                } else if handle == .none || (handle != .bottomLeft && handle != .topRight) {
                    if annotationResizeAnchorIndex < 0 {
                        annotationResizeOrigControlPoint =
                            selected.controlPoint
                            ?? NSPoint(
                                x: (selected.startPoint.x + selected.endPoint.x) / 2,
                                y: (selected.startPoint.y + selected.endPoint.y) / 2
                            )
                    }
                }
                NSCursor.closedHand.set()
                needsDisplay = true
                return true
            }
        }
        if annotationRotateHandleRect != .zero
            && annotationRotateHandleRect.insetBy(dx: -6, dy: -6).contains(point)
        {
            isRotatingAnnotation = true
            setCachedAnnotationLayerExcludingSelected(
                buildInteractionAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
            )
            let center = NSPoint(x: selected.boundingRect.midX, y: selected.boundingRect.midY)
            rotationStartAngle = atan2(point.x - center.x, point.y - center.y)
            rotationOriginal = selected.rotation
            NSCursor.closedHand.set()
            needsDisplay = true
            return true
        }
        if selected.tool == .text && annotationEditButtonRect != .zero
            && annotationEditButtonRect.contains(point)
        {
            textEditor.restoreState(from: selected)
            if let idx = annotations.firstIndex(where: { $0 === selected }) {
                annotations.remove(at: idx)
                selectedAnnotation = nil
            }
            showTextField(
                at: selected.textDrawRect.origin, existingText: selected.attributedText,
                existingFrame: selected.textDrawRect)
            needsDisplay = true
            return true
        }
        if annotationDeleteButtonRect.contains(point) {
            if let idx = annotations.firstIndex(where: { $0 === selected }) {
                annotations.remove(at: idx)
                undoStack.append(.deleted(selected, idx))
                redoStack.removeAll()
            }
            selectedAnnotation = nil
            needsDisplay = true
            return true
        }
        if selected.tool == .text && selected.hitTest(point: point) {
            if let event = NSApp.currentEvent, event.clickCount >= 2 {
                textEditor.editingAnnotation = selected
                textEditor.restoreState(from: selected)
                if let idx = annotations.firstIndex(where: { $0 === selected }) {
                    annotations.remove(at: idx)
                    selectedAnnotation = nil
                }
                showTextField(
                    at: selected.textDrawRect.origin, existingText: selected.attributedText,
                    existingFrame: selected.textDrawRect)
                cachedCompositedImage = nil
                return true
            }
        }
        if selected.hitTest(point: point) {
            isDraggingAnnotation = true
            didMoveAnnotation = false
            annotationDragStart = point
            setCachedAnnotationLayerExcludingSelected(
                buildInteractionAnnotationLayer(excluding: Set(selectedAnnotations.map { ObjectIdentifier($0) }))
            )
            NSCursor.closedHand.set()
            needsDisplay = true
            return true
        }
        return false
    }

    // MARK: - Annotation Context Helpers

    func addAnchorPoint(to annotation: Annotation, at canvasPoint: NSPoint) {
        var pts = annotation.waypoints

        var bestIdx = 1
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 1..<pts.count {
            let d = distanceToSegment(point: canvasPoint, from: pts[i - 1], to: pts[i])
            if d < bestDist {
                bestDist = d
                bestIdx = i
            }
        }

        let a = pts[bestIdx - 1]
        let b = pts[bestIdx]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        let t: CGFloat =
            lenSq < 0.001
            ? 0.5
            : max(
                0.05,
                min(0.95, ((canvasPoint.x - a.x) * dx + (canvasPoint.y - a.y) * dy) / lenSq))
        let projected = NSPoint(x: a.x + t * dx, y: a.y + t * dy)

        pts.insert(projected, at: bestIdx)

        annotation.anchorPoints = pts
        annotation.startPoint = pts.first!
        annotation.endPoint = pts.last!
        annotation.controlPoint = nil
    }

    private func distanceToSegment(point: NSPoint, from a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq < 0.001 { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let proj = NSPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }
}
