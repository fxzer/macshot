import AppKit

extension OverlayView {
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
}
