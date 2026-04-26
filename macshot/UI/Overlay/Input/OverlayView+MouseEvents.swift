import AppKit

extension OverlayView {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Update pressure for tablet/Sidecar (0.0 for non-tablet events → treat as 1.0)
        let p = event.pressure
        #if PRESSURE_EMULATION
        // Debug: simulate pressure from mouse speed. Slow = heavy (1.0), fast = light (0.2).
        // Uses deltaX/deltaY from the event to compute instantaneous speed.
        let speed = hypot(event.deltaX, event.deltaY)
        let simulated = max(0.2, min(1.0, 1.0 - speed / 40.0))
        currentPressure = simulated
        #else
        currentPressure = p > 0 ? CGFloat(p) : 1.0
        #endif

        // Auto-measure: click to commit the preview annotation
        if autoMeasureKeyHeld, let preview = autoMeasurePreview {
            annotations.append(preview)
            undoStack.append(.added(preview))
            redoStack.removeAll()
            autoMeasurePreview = nil
            cachedCompositedImage = nil
            // Recompute a new preview at the current position
            updateAutoMeasurePreview()
            return
        }

        // Note: toolbar strips and options row are routed by hitTest() — they never reach here

        // Control-click = right-click for color sampler (supports BetterTouchTool and other tools
        // that simulate right-click via control-click instead of rightMouseDown)
        if event.modifierFlags.contains(.control) && state == .selected
            && currentTool == .colorSampler
        {
            _ = copySampledColor(at: viewToCanvas(point))
            return
        }

        // Control-click on line/arrow: add anchor point (same as right-click)
        if event.modifierFlags.contains(.control) && state == .selected {
            if let ann = selectedAnnotation,
                ann.tool == .arrow || ann.tool == .line || ann.tool == .measure
            {
                let canvasPoint = viewToCanvas(point)
                if ann.hitTest(point: canvasPoint) {
                    addAnchorPoint(to: ann, at: canvasPoint)
                    cachedCompositedImage = nil
                    needsDisplay = true
                    return
                }
            }
        }

        // Barcode bar button hit-test
        if let action = barcodeDetector.hitTest(point: point) {
            switch action {
            case .dismiss:
                barcodeDetector.cancel()
                needsDisplay = true
            case .open(let url):
                barcodeDetector.cancel()
                needsDisplay = true
                overlayDelegate?.overlayViewDidCancel()
                if let url = URL(string: url) {
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
            case .copy(let text):
                barcodeDetector.cancel()
                needsDisplay = true
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            return
        }

        // Editor top bar button clicks
        if handleTopChromeClick(at: point) {
            return
        }

        let isTextEditing = textEditView != nil

        // Check text box resize handles when editing
        if isTextEditing && showToolbars {
            // Check text box resize handles
            if let sv = textEditor.scrollView {
                let frame = sv.frame
                if let handle = hitTestLiveTextResizeHandle(at: point, frame: frame) {
                    isResizingTextBox = true
                    textBoxResizeHandle = handle
                    textBoxResizeStart = point
                    textBoxOrigFrame = frame
                    textBoxOrigFontSize = textEditor.fontSize
                    textEditor.lockWidth()
                    return
                }
                if isPointOnLiveTextDragEdge(point, frame: frame) {
                    isDraggingTextBox = true
                    textBoxDragStart = point
                    textBoxDragOrigFrame = frame
                    NSCursor.closedHand.set()
                    return
                }
                // Clicking on the text editor itself — don't commit
                if frame.contains(point) {
                    return
                }
            }
        }

        // Don't commit text if clicking on text formatting controls in the options row
        let isTextFormattingClick =
            textEditView != nil && currentTool == .text
            && ((toolOptionsRowView?.frame.contains(point) ?? false))
        if !isTextFormattingClick {
            commitTextFieldIfNeeded()
        }

        switch state {
        case .idle:
            // Check remote selection handles for cross-screen resize
            if remoteSelectionRect.width >= 1 && remoteSelectionRect.height >= 1 {
                let remoteHandle = hitTestRemoteHandle(at: point)
                if remoteHandle != .none {
                    isResizingRemoteSelection = true
                    remoteResizeHandle = remoteHandle
                    remoteResizeAnchor = anchorForHandle(remoteHandle, in: remoteSelectionFullRect)
                    return
                }
                return
            }
            // Always start a drag — snap is resolved in mouseUp if no real drag occurred
            selectionStart = point
            selectionRect = NSRect(origin: point, size: .zero)
            state = .selecting
            selectionWasRestoredFromMemory = false
            overlayDelegate?.overlayViewDidBeginSelection()

            // Show color sampler magnifier when entering selection state
            showColorSamplerMagnifier()

            needsDisplay = true

        case .selected:
            if shouldIgnoreZoomLabelMouseDown(at: point) { return }

            // Sticky color wheel: click to pick a color
            if colorWheel.isVisible && colorWheel.isSticky {
                colorWheel.updateHover(at: point)
                if colorWheel.hoveredColor != nil {
                    currentColor = colorWheel.hoveredColor!
                    applyColorToTextIfEditing()
                    applyColorToSelectedAnnotation()
                    rebuildToolbarLayout()
                }
                colorWheel.dismiss()
                needsDisplay = true
                return
            }
            // Check handles (disabled in editor)
            if shouldAllowSelectionResize() {
                let handle = hitTestHandle(at: point)
                if handle != .none {
                    isResizingSelection = true
                    selectionWasRestoredFromMemory = false
                    selectionIsWindowSnap = false
                    snappedWindowID = nil
                    snappedWindowImage = nil
                    resizeHandle = handle
                    // Snipaste-style: hide toolbars while resizing so the size label stays readable.
                    showToolbars = false
                    return
                }
            }

            // Crop tool drag (use canvas coords so it aligns with the image)
            if currentTool == .crop && pointIsInSelection(point) {
                isCropDragging = true
                cropDragStart = viewToCanvas(point)
                cropDragRect = .zero
                needsDisplay = true
                return
            }

            // Color sampler works anywhere on the screenshot, not just inside selection
            if currentTool == .colorSampler {
                let canvasPoint = viewToCanvas(point)
                startAnnotation(at: canvasPoint)
                return
            }

            // Snipaste-style: drag selection area when clicking inside selection but not on any annotation
            // This allows moving the selection without clicking the move button
            if pointIsInSelection(point) && currentTool != .crop {
                if currentTool == .select, handleSelectionChromePriorityClick(at: point) {
                    return
                }
                let canvasPoint = viewToCanvas(point)
                // Check if clicking on any movable annotation
                let clickedOnAnnotation = annotations.reversed().contains(where: { $0.isMovable && $0.hitTest(point: canvasPoint) })
                if !clickedOnAnnotation && currentTool == .select {
                    // Inside selection but not on any annotation — start dragging selection
                    isDraggingSelection = true
                    selectionWasRestoredFromMemory = false
                    selectionDragStart = point
                    selectionDragOffset = NSPoint(x: point.x - selectionRect.origin.x, y: point.y - selectionRect.origin.y)
                    NSCursor.closedHand.set()
                    // Snipaste-style: hide toolbars while moving the selection box.
                    showToolbars = false
                    needsDisplay = true
                    return
                }
            }

            // Start annotation (convert to canvas space for zoom).
            // Require the click to be inside the selection rectangle.
            if currentTool != .crop && pointIsInSelection(point) {
                let canvasPoint = viewToCanvas(point)
                startAnnotation(at: canvasPoint)
                return
            }

            // Outside everything - start new selection (locked during recording or editor mode)
            guard shouldAllowNewSelection() else { return }
            showToolbars = false
            annotations.removeAll()
            undoStack.removeAll()
            redoStack.removeAll()
            numberCounter = 0
            resetZoom()
            resetZoomUIState()
            selectionStart = point
            selectionRect = NSRect(origin: point, size: .zero)
            state = .selecting
            selectionWasRestoredFromMemory = false
            overlayDelegate?.overlayViewDidBeginSelection()
            needsDisplay = true

        case .selecting:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        clearKeyboardColorSamplerPoint()

        // Cancel long-press timer if the user moved more than 3px (they're drawing, not selecting)
        if longPressTimer != nil {
            let dx = point.x - longPressPoint.x
            let dy = point.y - longPressPoint.y
            if dx * dx + dy * dy > 9 {
                longPressTimer?.invalidate()
                longPressTimer = nil
            }
        }

        // If long-press already triggered selection, handle as annotation drag
        if longPressTriggered && isDraggingAnnotation {
            // Fall through to the annotation drag handling below
        }

        // Remote selection resize (cross-screen)
        if isResizingRemoteSelection {
            let fullRect = remoteSelectionFullRect
            let newRect = resizedSelectionRect(
                from: fullRect,
                handle: remoteResizeHandle,
                to: point,
                minSize: 10,
                aspectRatio: activeAspectRatio
            )
            // Update full rect and clip for local display
            remoteSelectionFullRect = newRect
            let screenBounds = NSRect(origin: .zero, size: bounds.size)
            let clipped = newRect.intersection(screenBounds)
            remoteSelectionRect = clipped.isEmpty ? .zero : clipped
            // Update primary + other screens
            overlayDelegate?.overlayViewRemoteSelectionDidChange(newRect)
            needsDisplay = true
            return
        }

        // Crop drag update (in canvas coords)
        if isCropDragging {
            let canvasPt = viewToCanvas(point)
            let clampedPoint = NSPoint(
                x: max(selectionRect.minX, min(canvasPt.x, selectionRect.maxX)),
                y: max(selectionRect.minY, min(canvasPt.y, selectionRect.maxY))
            )
            let origin = NSPoint(
                x: min(cropDragStart.x, clampedPoint.x), y: min(cropDragStart.y, clampedPoint.y))
            cropDragRect = NSRect(
                origin: origin,
                size: NSSize(
                    width: abs(clampedPoint.x - cropDragStart.x),
                    height: abs(clampedPoint.y - cropDragStart.y)))
            needsDisplay = true
            return
        }

        // Handle text box resize
        if isResizingTextBox, let sv = textEditor.scrollView, let tv = textEditView {
            let dx = point.x - textBoxResizeStart.x
            let dy = point.y - textBoxResizeStart.y
            let orig = textBoxOrigFrame
            var newFrame = orig
            let minW: CGFloat = 60
            let minH: CGFloat = max(28, textBoxOrigFontSize + 12)
            let isCornerHandle: Bool

            switch textBoxResizeHandle {
            case .right:
                newFrame.size.width = max(minW, orig.width + dx)
                isCornerHandle = false
            case .left:
                newFrame.origin.x = min(orig.maxX - minW, orig.minX + dx)
                newFrame.size.width = orig.maxX - newFrame.minX
                isCornerHandle = false
            case .top:
                newFrame.size.height = max(minH, orig.height + dy)
                isCornerHandle = false
            case .bottom:
                let newMinY = min(orig.maxY - minH, orig.minY + dy)
                newFrame.origin.y = newMinY
                newFrame.size.height = orig.maxY - newMinY
                isCornerHandle = false
            case .topRight:
                newFrame.size.width = max(minW, orig.width + dx)
                newFrame.size.height = max(minH, orig.height + dy)
                isCornerHandle = true
            case .topLeft:
                newFrame.origin.x = min(orig.maxX - minW, orig.minX + dx)
                newFrame.size.width = orig.maxX - newFrame.minX
                newFrame.size.height = max(minH, orig.height + dy)
                isCornerHandle = true
            case .bottomRight:
                newFrame.size.width = max(minW, orig.width + dx)
                let newMinY = min(orig.maxY - minH, orig.minY + dy)
                newFrame.origin.y = newMinY
                newFrame.size.height = orig.maxY - newMinY
                isCornerHandle = true
            case .bottomLeft:
                newFrame.origin.x = min(orig.maxX - minW, orig.minX + dx)
                newFrame.size.width = orig.maxX - newFrame.minX
                let newMinY = min(orig.maxY - minH, orig.minY + dy)
                newFrame.origin.y = newMinY
                newFrame.size.height = orig.maxY - newMinY
                isCornerHandle = true
            default:
                isCornerHandle = false
            }

            if isCornerHandle, orig.width > 0, textBoxOrigFontSize > 0 {
                let newFontSize = max(6, min(200, textBoxOrigFontSize * (newFrame.width / orig.width)))
                textEditor.scaleLiveText(to: newFontSize)
                toolOptionsRowView?.updateFontSizeDisplay(value: newFontSize)
            }

            let shouldFitHeightToContent = textBoxResizeHandle == .left || textBoxResizeHandle == .right
            textEditor.applyLiveFrame(newFrame, fitHeightToContent: shouldFitHeightToContent)
            needsDisplay = true
            return
        }

        if isDraggingTextBox, let sv = textEditor.scrollView {
            let dx = point.x - textBoxDragStart.x
            let dy = point.y - textBoxDragStart.y
            let newOrigin = NSPoint(
                x: textBoxDragOrigFrame.origin.x + dx,
                y: textBoxDragOrigFrame.origin.y + dy
            )
            sv.frame.origin = newOrigin
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }

        switch state {
        case .selecting:
            updateSelectionRectForCurrentSelectionDrag(to: point, shiftHeld: event.modifierFlags.contains(.shift))

        case .selected:
            // Selection dragging (Snipaste-style: drag selection area)
            if isDraggingSelection {
                selectionRect.origin = NSPoint(x: point.x - selectionDragOffset.x, y: point.y - selectionDragOffset.y)
                needsDisplay = true
                return
            }

            // Convert to canvas space for annotation interactions (accounts for zoom)
            let canvasPoint = viewToCanvas(point)
            if isRotatingAnnotation, let annotation = selectedAnnotation {
                let center = NSPoint(
                    x: annotation.boundingRect.midX, y: annotation.boundingRect.midY)
                let currentAngle = atan2(canvasPoint.x - center.x, canvasPoint.y - center.y)
                var newRotation = rotationOriginal - (currentAngle - rotationStartAngle)
                // Shift: snap to 45° steps
                if NSEvent.modifierFlags.contains(.shift) {
                    let step = CGFloat.pi / 4
                    newRotation = (newRotation / step).rounded() * step
                }
                annotation.rotation = newRotation
                needsDisplay = true
                return
            }
            if isResizingAnnotation, let annotation = selectedAnnotation {
                let dx = canvasPoint.x - annotationResizeMouseStart.x
                let dy = canvasPoint.y - annotationResizeMouseStart.y
                let origStart = annotationResizeOrigStart
                let origEnd = annotationResizeOrigEnd

                // Text annotations: resize the text box and re-render textImage
                if annotation.tool == .text {
                    let origRect = NSRect(origin: origStart,
                        size: NSSize(width: origEnd.x - origStart.x, height: origEnd.y - origStart.y))
                    var newRect = origRect
                    let minW: CGFloat = 40
                    let minH: CGFloat = max(20, annotation.fontSize + 8)

                    let isCornerHandle: Bool
                    switch annotationResizeHandle {
                    case .right: newRect.size.width = max(minW, origRect.width + dx); isCornerHandle = false
                    case .left:
                        newRect.origin.x = min(origRect.maxX - minW, origRect.minX + dx)
                        newRect.size.width = origRect.maxX - newRect.minX
                        isCornerHandle = false
                    case .top:
                        newRect.size.height = max(minH, origRect.height + dy)
                        isCornerHandle = false
                    case .bottom:
                        let newMinY = min(origRect.maxY - minH, origRect.minY + dy)
                        newRect.origin.y = newMinY
                        newRect.size.height = origRect.maxY - newMinY
                        isCornerHandle = false
                    case .topRight:
                        newRect.size.width = max(minW, origRect.width + dx)
                        newRect.size.height = max(minH, origRect.height + dy)
                        isCornerHandle = true
                    case .topLeft:
                        newRect.origin.x = min(origRect.maxX - minW, origRect.minX + dx)
                        newRect.size.width = origRect.maxX - newRect.minX
                        newRect.size.height = max(minH, origRect.height + dy)
                        isCornerHandle = true
                    case .bottomRight:
                        newRect.size.width = max(minW, origRect.width + dx)
                        let newMinY = min(origRect.maxY - minH, origRect.minY + dy)
                        newRect.origin.y = newMinY
                        newRect.size.height = origRect.maxY - newMinY
                        isCornerHandle = true
                    case .bottomLeft:
                        newRect.origin.x = min(origRect.maxX - minW, origRect.minX + dx)
                        newRect.size.width = origRect.maxX - newRect.minX
                        let newMinY = min(origRect.maxY - minH, origRect.minY + dy)
                        newRect.origin.y = newMinY
                        newRect.size.height = origRect.maxY - newMinY
                        isCornerHandle = true
                    default: isCornerHandle = false
                    }

                    annotation.startPoint = newRect.origin
                    annotation.endPoint = NSPoint(x: newRect.maxX, y: newRect.maxY)
                    annotation.textDrawRect = newRect

                    // Corner handles: scale font size proportionally, render at exact dragged size
                    if isCornerHandle, origRect.width > 0, annotationResizeOrigFontSize > 0 {
                        let scaleFactor = newRect.width / origRect.width
                        let newFontSize = max(6, min(200, annotationResizeOrigFontSize * scaleFactor))
                        annotation.fontSize = newFontSize
                        // Rebuild attributed string with new font size (inline, don't call
                        // reRenderTextImage which overrides textDrawRect)
                        if let attrText = annotation.attributedText {
                            let mutable = NSMutableAttributedString(attributedString: attrText)
                            let range = NSRange(location: 0, length: mutable.length)
                            var font: NSFont
                            if let familyName = annotation.fontFamilyName, familyName != "System",
                               let familyFont = NSFont(name: familyName, size: newFontSize) {
                                font = familyFont
                            } else {
                                font = NSFont.systemFont(ofSize: newFontSize)
                            }
                            if annotation.isBold && annotation.isItalic {
                                font = NSFontManager.shared.convert(font, toHaveTrait: [.boldFontMask, .italicFontMask])
                            } else if annotation.isBold {
                                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                            } else if annotation.isItalic {
                                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                            }
                            mutable.addAttribute(.font, value: font, range: range)
                            annotation.attributedText = mutable

                            let inset: CGFloat = 4
                            let img = NSImage(size: newRect.size, flipped: true) { _ in
                                mutable.draw(in: NSRect(x: inset, y: inset,
                                    width: newRect.width - inset * 2, height: newRect.height - inset * 2))
                                return true
                            }
                            annotation.textImage = img
                        }
                        annotation.outlineGlowImage = nil
                    } else if let attrStr = annotation.attributedText {
                        // Edge handles: reflow text at same font size
                        let inset: CGFloat = 4
                        let img = NSImage(size: newRect.size, flipped: true) { _ in
                            attrStr.draw(in: NSRect(x: inset, y: inset,
                                width: newRect.width - inset * 2, height: newRect.height - inset * 2))
                            return true
                        }
                        annotation.textImage = img
                    }
                    cachedCompositedImage = nil
                    needsDisplay = true
                    return
                }

                let shiftHeld = event.modifierFlags.contains(.shift)

                // Arrow/line/measure: .bottomLeft = startPoint, .topRight = endPoint, others = anchor points
                if annotation.tool == .arrow || annotation.tool == .line
                    || annotation.tool == .measure
                {
                    let newPt = NSPoint(
                        x: annotationResizeOrigControlPoint.x + dx,
                        y: annotationResizeOrigControlPoint.y + dy)
                    switch annotationResizeHandle {
                    case .bottomLeft:
                        var newStart = NSPoint(x: origStart.x + dx, y: origStart.y + dy)
                        if shiftHeld {
                            let anchor = annotation.endPoint
                            let ddx = newStart.x - anchor.x
                            let ddy = newStart.y - anchor.y
                            let angle = atan2(ddy, ddx)
                            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
                            let dist = hypot(ddx, ddy)
                            newStart = NSPoint(
                                x: anchor.x + dist * cos(snapped), y: anchor.y + dist * sin(snapped)
                            )
                        }
                        annotation.startPoint = newStart
                        if var anchors = annotation.anchorPoints, !anchors.isEmpty {
                            anchors[0] = newStart
                            annotation.anchorPoints = anchors
                        }
                    case .topRight:
                        var newEnd = NSPoint(x: origEnd.x + dx, y: origEnd.y + dy)
                        if shiftHeld {
                            let anchor = annotation.startPoint
                            let ddx = newEnd.x - anchor.x
                            let ddy = newEnd.y - anchor.y
                            let angle = atan2(ddy, ddx)
                            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
                            let dist = hypot(ddx, ddy)
                            newEnd = NSPoint(
                                x: anchor.x + dist * cos(snapped), y: anchor.y + dist * sin(snapped)
                            )
                        }
                        annotation.endPoint = newEnd
                        if var anchors = annotation.anchorPoints, anchors.count >= 2 {
                            anchors[anchors.count - 1] = newEnd
                            annotation.anchorPoints = anchors
                        }
                    default:
                        // Dragging an anchor point (multi-anchor or legacy controlPoint)
                        if annotationResizeAnchorIndex >= 0, var anchors = annotation.anchorPoints {
                            if annotationResizeAnchorIndex < anchors.count {
                                anchors[annotationResizeAnchorIndex] = newPt
                                annotation.anchorPoints = anchors
                                // Keep start/end in sync
                                annotation.startPoint = anchors.first!
                                annotation.endPoint = anchors.last!
                            }
                        } else {
                            // Legacy single controlPoint
                            annotation.controlPoint = newPt
                        }
                    }
                } else {
                    // Work in bounding-rect space so resize is correct regardless of draw direction
                    let origMinX = min(origStart.x, origEnd.x)
                    let origMaxX = max(origStart.x, origEnd.x)
                    let origMinY = min(origStart.y, origEnd.y)
                    let origMaxY = max(origStart.y, origEnd.y)
                    var newMinX = origMinX
                    var newMaxX = origMaxX
                    var newMinY = origMinY
                    var newMaxY = origMaxY

                    switch annotationResizeHandle {
                    case .topLeft:
                        newMinX = min(origMinX + dx, origMaxX - 10)
                        newMaxY = max(origMaxY + dy, origMinY + 10)
                    case .topRight:
                        newMaxX = max(origMaxX + dx, origMinX + 10)
                        newMaxY = max(origMaxY + dy, origMinY + 10)
                    case .bottomLeft:
                        newMinX = min(origMinX + dx, origMaxX - 10)
                        newMinY = min(origMinY + dy, origMaxY - 10)
                    case .bottomRight:
                        newMaxX = max(origMaxX + dx, origMinX + 10)
                        newMinY = min(origMinY + dy, origMaxY - 10)
                    case .top:
                        newMaxY = max(origMaxY + dy, origMinY + 10)
                    case .bottom:
                        newMinY = min(origMinY + dy, origMaxY - 10)
                    case .left:
                        newMinX = min(origMinX + dx, origMaxX - 10)
                    case .right:
                        newMaxX = max(origMaxX + dx, origMinX + 10)
                    default:
                        break
                    }

                    // Shift constraint: force square/circle for corner handles
                    if shiftHeld {
                        let w = newMaxX - newMinX
                        let h = newMaxY - newMinY
                        let side = max(w, h)
                        switch annotationResizeHandle {
                        case .topLeft:
                            newMinX = newMaxX - side
                            newMaxY = newMinY + side
                        case .topRight:
                            newMaxX = newMinX + side
                            newMaxY = newMinY + side
                        case .bottomLeft:
                            newMinX = newMaxX - side
                            newMinY = newMaxY - side
                        case .bottomRight:
                            newMaxX = newMinX + side
                            newMinY = newMaxY - side
                        default: break
                        }
                    }

                    annotation.startPoint = NSPoint(x: newMinX, y: newMinY)
                    annotation.endPoint = NSPoint(x: newMaxX, y: newMaxY)
                }
                if annotation.tool == .pixelate { annotation.bakedBlurNSImage = nil }
                cachedCompositedImage = nil
                needsDisplay = true
            } else if isLassoSelecting {
                // Update lasso marquee rectangle
                let x = min(lassoStart.x, canvasPoint.x)
                let y = min(lassoStart.y, canvasPoint.y)
                let w = abs(canvasPoint.x - lassoStart.x)
                let h = abs(canvasPoint.y - lassoStart.y)
                lassoRect = NSRect(x: x, y: y, width: w, height: h)
                needsDisplay = true
            } else if isDraggingAnnotation, !selectedAnnotations.isEmpty {
                let rawDx = canvasPoint.x - annotationDragStart.x
                let rawDy = canvasPoint.y - annotationDragStart.y
                // For single selection, apply snap; for multi, just move raw
                let finalDx: CGFloat
                let finalDy: CGFloat
                if selectedAnnotations.count == 1, let annotation = selectedAnnotations.first {
                    let movedRect = annotation.boundingRect.offsetBy(dx: rawDx, dy: rawDy)
                    let snap = snapRectDelta(rect: movedRect, excluding: annotation)
                    finalDx = rawDx + snap.dx
                    finalDy = rawDy + snap.dy
                    annotationDragStart = NSPoint(
                        x: canvasPoint.x + snap.dx, y: canvasPoint.y + snap.dy)
                } else {
                    finalDx = rawDx
                    finalDy = rawDy
                    annotationDragStart = canvasPoint
                }
                for annotation in selectedAnnotations {
                    annotation.move(dx: finalDx, dy: finalDy)
                }
                didMoveAnnotation = true
                cachedCompositedImage = nil
                needsDisplay = true
            } else if isDraggingSelection {
                selectionRect.origin = NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
                needsDisplay = true
            } else if isResizingSelection {
                resizeSelection(to: point)
                overlayDelegate?.overlayViewSelectionDidChange(selectionRect)
                needsDisplay = true
            } else if currentAnnotation != nil {
                if spaceRepositioning {
                    // Space held: reposition the whole shape
                    let dx = canvasPoint.x - spaceRepositionLast.x
                    let dy = canvasPoint.y - spaceRepositionLast.y
                    currentAnnotation!.startPoint.x += dx
                    currentAnnotation!.startPoint.y += dy
                    currentAnnotation!.endPoint.x += dx
                    currentAnnotation!.endPoint.y += dy
                    if let points = currentAnnotation!.points {
                        currentAnnotation!.points = points.map {
                            NSPoint(x: $0.x + dx, y: $0.y + dy)
                        }
                    }
                    spaceRepositionLast = canvasPoint
                } else {
                    let p = event.pressure
                    #if PRESSURE_EMULATION
                    let speed = hypot(event.deltaX, event.deltaY)
                    currentPressure = max(0.2, min(1.0, 1.0 - speed / 40.0))
                    #else
                    currentPressure = p > 0 ? CGFloat(p) : 1.0
                    #endif
                    updateAnnotation(
                        at: canvasPoint, shiftHeld: event.modifierFlags.contains(.shift))
                }
                lastDragPoint = canvasPoint
                if let annotation = currentAnnotation,
                    toolHandlers[annotation.tool]?.requiresDisplayRefreshDuringDrag ?? true
                {
                    needsDisplay = true
                }
            }

        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        spaceRepositioning = false

        // Clean up long-press timer
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressTriggered = false

        // Finish remote selection resize — final sync + transfer focus to the primary
        if isResizingRemoteSelection {
            isResizingRemoteSelection = false
            remoteResizeHandle = .none
            overlayDelegate?.overlayViewRemoteSelectionDidFinish(remoteSelectionFullRect)
            return
        }

        // Crop commit
        if isCropDragging {
            isCropDragging = false
            let rect = cropDragRect
            cropDragRect = .zero
            if rect.width > 4 && rect.height > 4 {
                commitCrop(viewRect: rect)
            }
            needsDisplay = true
            return
        }

        if isResizingTextBox {
            isResizingTextBox = false
            textBoxOrigFontSize = 0
            if let win = window {
                updateCursorForPoint(convert(win.mouseLocationOutsideOfEventStream, from: nil))
            }
            return
        }

        if isDraggingTextBox {
            isDraggingTextBox = false
            if let win = window {
                updateCursorForPoint(convert(win.mouseLocationOutsideOfEventStream, from: nil))
            }
            return
        }
        if isRotatingAnnotation {
            isRotatingAnnotation = false
            invalidateAnnotationCaches()
            NSCursor.openHand.set()
            needsDisplay = true
            return
        }
        if isResizingAnnotation {
            isResizingAnnotation = false
            invalidateAnnotationCaches()
            annotationResizeHandle = .none
            if let ann = selectedAnnotation {
                if ann.tool == .loupe { ann.bakeLoupe() }
                if ann.tool == .pixelate { ann.bakedBlurNSImage = nil; ann.bakePixelate() }
            }
            NSCursor.openHand.set()
            needsDisplay = true
            return
        }
        lastDragPoint = nil
        switch state {
        case .selecting:
            if selectionRect.width > 5 || selectionRect.height > 5 {
                // Real drag — use drawn rect as-is
                state = .selected

                // Hide color sampler magnifier when entering selected state
                hideColorSamplerMagnifier()
                // Re-show magnifier if color sampler is the active tool
                if currentTool == .colorSampler {
                    showColorSamplerMagnifier()
                }

                // Keep the current aspect-ratio lock for drag selections.
                if !autoOCRMode && !autoQuickSaveMode && !autoScrollCaptureMode && !autoConfirmMode { showToolbars = true }
                overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
                clearSelectionSizeSnapState()
            } else if windowSnapEnabled, let snapRect = hoveredWindowRect, !snapRect.isEmpty {
                // Click (no drag) with snap on — snap to hovered window
                selectionRect = snapRect
                selectionIsWindowSnap = true
                snappedWindowID = hoveredWindowID
                // Capture the window independently for beautify (transparent corners)
                if let wid = hoveredWindowID, let screen = window?.screen {
                    Task { [weak self] in
                        guard let self = self else { return }
                        if let cgImage = await ScreenCaptureManager.captureWindow(windowID: wid, screen: screen) {
                            self.snappedWindowImage = NSImage(cgImage: cgImage,
                                size: NSSize(width: CGFloat(cgImage.width) / screen.backingScaleFactor,
                                             height: CGFloat(cgImage.height) / screen.backingScaleFactor))
                            self.needsDisplay = true
                        }
                    }
                }
                state = .selected

                // Hide color sampler magnifier when entering selected state
                hideColorSamplerMagnifier()
                // Re-show magnifier if color sampler is the active tool
                if currentTool == .colorSampler {
                    showColorSamplerMagnifier()
                }

                // Keep the current aspect-ratio lock for snapped window selections.
                if !autoOCRMode && !autoQuickSaveMode && !autoScrollCaptureMode && !autoConfirmMode { showToolbars = true }
                overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
                clearSelectionSizeSnapState()
            } else {
                // Click (no drag), snap off — expand to full screen
                selectionRect = bounds
                state = .selected

                // Hide color sampler magnifier when entering selected state
                hideColorSamplerMagnifier()
                // Re-show magnifier if color sampler is the active tool
                if currentTool == .colorSampler {
                    showColorSamplerMagnifier()
                }

                aspectRatioLock = .none  // Reset the lock for full-screen selection.
                if !autoOCRMode && !autoQuickSaveMode && !autoScrollCaptureMode && !autoConfirmMode { showToolbars = true }
                overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
                clearSelectionSizeSnapState()
            }
            hoveredWindowRect = nil
            // Update cursor to match the selected tool (replaces resize cursor from dragging)
            if let win = window {
                let point = convert(win.mouseLocationOutsideOfEventStream, from: nil)
                updateCursorForPoint(point)
            }
            scheduleBarcodeDetection()
            // Auto-enter recording mode if triggered from "Record Screen"
            if autoEnterRecordingMode {
                autoEnterRecordingMode = false
                overlayDelegate?.overlayViewDidRequestEnterRecordingMode()
            }
            // Auto-trigger OCR if triggered from "Capture OCR"
            if autoOCRMode {
                autoOCRMode = false
                overlayDelegate?.overlayViewDidRequestOCR()
            }
            // Auto-trigger quick save if triggered from "Quick Capture"
            if autoQuickSaveMode {
                autoQuickSaveMode = false
                overlayDelegate?.overlayViewDidRequestQuickSave()
            }
            // Auto-trigger scroll capture if triggered from "Scroll Capture"
            if autoScrollCaptureMode {
                autoScrollCaptureMode = false
                overlayDelegate?.overlayViewDidRequestScrollCapture(rect: selectionRect)
            }
            // Auto-confirm for "Add Capture" — just confirm selection, no save/copy
            if autoConfirmMode {
                autoConfirmMode = false
                overlayDelegate?.overlayViewDidConfirm()
            }
            needsDisplay = true

        case .selected:
            if isLassoSelecting {
                isLassoSelecting = false
                // Select all annotations whose bounding rect intersects the lasso
                if lassoRect.width > 2 && lassoRect.height > 2 {
                    let selected = annotations.filter { $0.isMovable && $0.boundingRect.intersects(lassoRect) }
                    if !selected.isEmpty {
                        selectedAnnotations = selected
                    }
                }
                lassoRect = .zero
                needsDisplay = true
            } else if isDraggingAnnotation {
                // Deferred shift+click deselect: only remove the annotation if
                // the user didn't drag (i.e. it was a click, not a move).
                if let pending = shiftClickPendingDeselect {
                    shiftClickPendingDeselect = nil
                    if !didMoveAnnotation {
                        if let idx = selectedAnnotations.firstIndex(where: { $0 === pending }) {
                            selectedAnnotations.remove(at: idx)
                        }
                    }
                }
                isDraggingAnnotation = false
                didMoveAnnotation = false
                invalidateAnnotationCaches()
                snapGuideX = nil
                snapGuideY = nil
                NSCursor.openHand.set()
                for ann in selectedAnnotations {
                    if ann.tool == .loupe { ann.bakeLoupe() }
                    if ann.tool == .pixelate { ann.bakedBlurNSImage = nil; ann.bakePixelate() }
                }
                // Auto-expand canvas if annotation was dragged outside bounds (editor mode)
                expandCanvasToFitAnnotations()
                needsDisplay = true
            } else if isDraggingSelection {
                isDraggingSelection = false
                scheduleBarcodeDetection()
                if !autoOCRMode && !autoQuickSaveMode && !autoScrollCaptureMode && !autoConfirmMode {
                    showToolbars = true
                }
                needsDisplay = true
            } else if isResizingSelection {
                isResizingSelection = false
                resizeHandle = .none
                clearSelectionSizeSnapState()
                scheduleBarcodeDetection()
                if !autoOCRMode && !autoQuickSaveMode && !autoScrollCaptureMode && !autoConfirmMode {
                    showToolbars = true
                }
                if let win = window {
                    updateCursorForPoint(convert(win.mouseLocationOutsideOfEventStream, from: nil))
                }
                needsDisplay = true
            } else if let annotation = currentAnnotation {
                finishAnnotation(annotation)
            }

        default:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Text Fill/Outline color picking handled by ToolOptionsRowView

        // Toolbar right-clicks handled by ToolbarButtonView.onRightClick → handleToolbarButtonRightClick

        // Right-click on a line/arrow/measure: add anchor point.
        // Auto-selects the annotation if it isn't selected yet.
        if state == .selected {
            let canvasPoint = viewToCanvas(point)
            // Check already-selected annotation first
            if let ann = selectedAnnotation,
                (ann.tool == .arrow || ann.tool == .line || ann.tool == .measure),
                ann.hitTest(point: canvasPoint)
            {
                addAnchorPoint(to: ann, at: canvasPoint)
                cachedCompositedImage = nil
                needsDisplay = true
                return
            }
            // Check any unselected line/arrow/measure under the cursor
            if let ann = annotations.reversed().first(where: {
                ($0.tool == .arrow || $0.tool == .line || $0.tool == .measure)
                && $0.hitTest(point: canvasPoint)
            }) {
                selectedAnnotation = ann
                addAnchorPoint(to: ann, at: canvasPoint)
                cachedCompositedImage = nil
                needsDisplay = true
                return
            }
        }

        if state == .selected && currentTool == .colorSampler {
            // Right-click with color sampler: copy in the currently displayed format
            _ = copySampledColor(at: viewToCanvas(point))
            return
        }

        if state == .selected && pointIsInSelection(point) {
            // Show radial color wheel
            colorWheel.show(at: point)

            colorWheel.hoveredIndex = -1
            needsDisplay = true
            return
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        if colorWheel.isVisible {
            let point = convert(event.locationInWindow, from: nil)
            colorWheel.updateHover(at: point)
            needsDisplay = true
            return
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if colorWheel.isVisible && !colorWheel.isSticky {
            if colorWheel.hoveredColor != nil {
                // User dragged to a color — pick it and dismiss
                currentColor = colorWheel.hoveredColor!
                applyColorToTextIfEditing()
                applyColorToSelectedAnnotation()
                rebuildToolbarLayout()
                colorWheel.dismiss()
            } else {
                // User released without dragging — enter sticky mode
                // so they can click a color (iPad/Sidecar/accessibility)
                colorWheel.isSticky = true
            }
            needsDisplay = true
            return
        }
    }
}
