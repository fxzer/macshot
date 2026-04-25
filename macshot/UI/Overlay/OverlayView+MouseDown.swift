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
}
