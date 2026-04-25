import AppKit

extension OverlayView {
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
