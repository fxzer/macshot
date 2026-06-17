import AppKit

extension OverlayView {
    func shouldHandleEscapeFromMonitor() -> Bool {
        guard let window else { return true }
        guard let responder = window.firstResponder else { return true }
        guard let textView = responder as? NSTextView else { return true }
        if let activeTextEditView = textEditView, textView === activeTextEditView {
            return true
        }
        return false
    }

    @discardableResult
    func handleEscapeKey() -> Bool {
        if isRecording {
            handleToolbarAction(.stopRecord)
            return true
        }
        if isScrollCapturing {
            overlayDelegate?.overlayViewDidRequestStopScrollCapture()
            return true
        }
        if colorWheel.isVisible && colorWheel.isSticky {
            colorWheel.dismiss()
            needsDisplay = true
            return true
        }
        if textEditView != nil {
            cancelTextEditing()
            return true
        }
        if PopoverHelper.isVisible {
            PopoverHelper.dismiss()
            if state == .idle {
                overlayDelegate?.overlayViewDidCancel()
            }
            return true
        }
        if !selectedAnnotations.isEmpty {
            selectedAnnotations = []
            needsDisplay = true
            return true
        }
        overlayDelegate?.overlayViewDidCancel()
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        // Re-apply shift constraint immediately when Shift is pressed/released during annotation drag
        if currentAnnotation != nil, let lastPoint = lastDragPoint {
            let shiftHeld = event.modifierFlags.contains(.shift)
            updateAnnotation(at: lastPoint, shiftHeld: shiftHeld)
            needsDisplay = true
        }

        // Handle Shift key for color sampler format toggle
        overlayViewFlagsChanged(with: event)
    }

    /// Called by the Character Palette when the user selects an emoji.
    override func insertText(_ insertString: Any) {
        guard currentTool == .stamp, let str = insertString as? String, !str.isEmpty else { return }
        currentStampImage = StampEmojis.renderEmoji(str)
        currentStampEmoji = str
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Forward Cmd shortcuts to the text view when editing — the main menu
        // intercepts these before keyDown reaches the overlay window.
        // Use keyCode (hardware-based) instead of charactersIgnoringModifiers
        // so shortcuts work regardless of keyboard layout (e.g. Russian, Arabic).
        if event.modifierFlags.contains(.command) {
            let key = event.keyCode
            // Text editing: forward to NSTextView (only when text is actively selected)
            if let tv = textEditView {
                switch key {
                case 8:  // C
                    if tv.selectedRange().length > 0 {
                        tv.copy(nil)
                    } else {
                        // No text selected — commit, copy annotation, then deselect
                        // so the purple selection chrome doesn't flash
                        commitTextFieldIfNeeded()
                        if selectedAnnotations.isEmpty, let last = annotations.last, last.tool == .text {
                            selectedAnnotation = last
                        }
                        copySelectedAnnotations()
                        selectedAnnotations = []
                        needsDisplay = true
                    }
                    return true
                case 9:  // V
                    if NSPasteboard.general.data(forType: Self.annotationPasteboardType) != nil {
                        commitTextFieldIfNeeded()
                        pasteAnnotations()
                        selectedAnnotations = []
                        needsDisplay = true
                    } else {
                        tv.paste(nil)
                    }
                    return true
                case 7: tv.cut(nil); return true  // X
                case 0: tv.selectAll(nil); return true  // A
                case 6:  // Z
                    if event.modifierFlags.contains(.shift) { tv.undoManager?.redo() }
                    else { tv.undoManager?.undo() }
                    return true
                default: break
                }
            }

            // Annotation copy/paste (no text editing active)
            if state == .selected {
                switch key {
                case 8:  // C
                    if !selectedAnnotations.isEmpty {
                        copySelectedAnnotations()
                    } else {
                        overlayDelegate?.overlayViewDidConfirm()
                    }
                    return true
                case 9:  // V
                    if NSPasteboard.general.data(forType: Self.annotationPasteboardType) != nil {
                        pasteAnnotations()
                        return true
                    }
                default: break
                }
            }

            // Canvas undo/redo — intercept before main menu consumes the event
            if state == .selected {
                switch key {
                case 6:  // Z
                    if event.modifierFlags.contains(.shift) { redo() }
                    else { undo() }
                    return true
                case 16:  // Y
                    redo()
                    return true
                default: break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isSharingActive {
            return
        }
        // In recording mode, only allow Escape (to exit recording mode)
        if isRecording {
            if event.keyCode == 53 { // Escape
                _ = handleEscapeKey()
            }
            return
        }

        // Space: reposition shape/selection mid-drag (design tool convention)
        if event.keyCode == 49 {
            // Swallow all repeats while repositioning to prevent system beep
            if spaceRepositioning { return }

            if !event.isARepeat {
                let isDraggingAnnotation =
                    currentAnnotation != nil && currentAnnotation!.tool != .select
                    && currentAnnotation!.tool != .marker
                let isDraggingNewSelection = state == .selecting

                if isDraggingAnnotation || isDraggingNewSelection {
                    spaceRepositioning = true
                    if isDraggingAnnotation {
                        spaceRepositionLast = lastDragPoint ?? .zero
                    } else if let windowPoint = window?.mouseLocationOutsideOfEventStream {
                        spaceRepositionLast = convert(windowPoint, from: nil)
                    }
                    return
                }
            }
        }

        switch event.keyCode {
        case 53:  // Escape
            _ = handleEscapeKey()
        case 48:  // Tab
            if state == .idle {
                // Toggle window snapping in idle state
                windowSnapEnabled = !windowSnapEnabled
                hoveredWindowRect = nil
                // Notify all other overlays to redraw (they will check if mouse is on their screen)
                overlayDelegate?.overlayViewDidChangeWindowSnapState()
                needsDisplay = true
                // Notify other overlays to redraw (for multi-monitor setups)
                overlayDelegate?.overlayViewDidChangeWindowSnapState()
            }
        case 3:  // F — full screen capture (only in idle state with snap on)
            if state == .idle && windowSnapEnabled {
                selectionRect = bounds
                state = .selected

                // Hide color sampler magnifier when entering selected state
                hideColorSamplerMagnifier()
                // Re-show magnifier if color sampler is the active tool
                if currentTool == .colorSampler {
                    showColorSamplerMagnifier()
                }

                aspectRatioLock = .none  // 全屏时重置锁定
                hoveredWindowRect = nil
                if autoQuickSaveMode {
                    autoQuickSaveMode = false
                    overlayDelegate?.overlayViewDidRequestQuickSave()
                } else {
                    showToolbars = true
                    scheduleBarcodeDetection()
                    overlayDelegate?.overlayViewDidFinishSelection(selectionRect)
                    needsDisplay = true
                }
            }
        case 36:  // Return/Enter — quick capture using the configured post-capture actions
            if textEditView == nil, state == .selected {
                overlayDelegate?.overlayViewDidRequestQuickSave()
            }
        case 51:  // Backspace/Delete — remove selected annotation(s)
            guard textEditView == nil, state == .selected, !selectedAnnotations.isEmpty else { break }
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
        case 50:  // ` (backtick) - toggle "remember last selection area"
            if state == .selected || state == .idle {
                toggleRememberLastSelection()
                return
            }
        default:
            // Handle arrow keys for pixel-perfect movement
            if handleArrowKeys(with: event) {
                return
            }
            // Handle color sampler keys (C for copy, WASD for pixel movement)
            if overlayViewKeyDown(with: event) {
                return
            }
            // Auto-measure: hold "1" = vertical preview, hold "2" = horizontal preview
            if state == .selected && currentTool == .measure && textEditView == nil
                && !event.modifierFlags.contains(.command)
            {
                if let char = event.charactersIgnoringModifiers {
                    if char == "1" || char == "2" {
                        autoMeasureVertical = (char == "1")
                        if !autoMeasureKeyHeld {
                            autoMeasureKeyHeld = true
                            updateAutoMeasurePreview()
                        }
                        return
                    }
                }
            }

            // 宽高比锁定快捷键（动态从 AspectRatioShortcutManager 获取）
            if state == .idle || state == .selecting || state == .selected {
                if let char = event.charactersIgnoringModifiers?.lowercased(), !event.modifierFlags.contains(.command) {

                    // 检查特殊快捷键：取消锁定
                    if char == AspectRatioShortcutManager.cancelKeyValue {
                        if aspectRatioLock != .none {
                            aspectRatioLock = .none
                            showStateHint(
                                message: L("Aspect ratio lock") + " ",
                                statusText: L("Status disabled"),
                                state: .disabled
                            )
                            needsDisplay = true
                            return
                        }
                    }

                    // 检查特殊快捷键：反转比例
                    if char == AspectRatioShortcutManager.invertKeyValue {
                        if aspectRatioLock != .none && aspectRatioLock != .oneToOne {
                            aspectRatioLock = aspectRatioLock.inverted
                            // 显示反转后的锁定提示
                            showStateHint(
                                message: L("Aspect ratio lock") + " (" + aspectRatioLock.displayName + ") ",
                                statusText: L("Status enabled"),
                                state: .enabled
                            )
                            needsDisplay = true
                            return
                        }
                    }

                    // 查找用户自定义的快捷键
                    if let ratio = AspectRatioShortcutManager.lookupRatio(for: char) {
                        let newLock = AspectRatioLock(from: ratio)
                        toggleAspectRatioLock(newLock)
                        return
                    }
                }
            }

            // Single-key tool shortcuts (only when selected, not editing text/inline fields, no modifiers)
            if state == .selected && textEditView == nil
                && !event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.control)
            {
                if let char = event.charactersIgnoringModifiers?.lowercased(),
                   let action = ToolShortcutManager.lookupAction(for: char) {
                    if case .detach = action {
                        if shouldAllowDetach() { handleToolbarAction(.detach) }
                    } else {
                        handleToolbarAction(action)
                    }
                    return
                }
            }
            if event.modifierFlags.contains(.command) {
                // Cmd+C, Cmd+V, Cmd+X, Cmd+A, Cmd+Z are handled in performKeyEquivalent.
                // Only Cmd+S and zoom shortcuts remain here.
                // Use keyCode for letters so shortcuts work with any keyboard layout.
                if event.keyCode == 1 {  // S
                    if state == .selected {
                        overlayDelegate?.overlayViewDidRequestSave()
                    }
                    return
                }
                if event.charactersIgnoringModifiers == "0" {
                    if isInsideScrollView, let sv = enclosingScrollView {
                        sv.magnification = 1.0
                        findTopBar()?.updateZoom(1.0)
                    } else if state == .selected && zoomLevel != 1.0 {
                        resetZoom()
                        showZoomLabel()
                        needsDisplay = true
                    }
                    return
                }
                if isInsideScrollView {
                    if event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+" {
                        if let sv = enclosingScrollView, let doc = sv.documentView {
                            let newMag = min(sv.maxMagnification, sv.magnification * 1.25)
                            sv.setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
                            findTopBar()?.updateZoom(newMag)
                        }
                        return
                    }
                    if event.charactersIgnoringModifiers == "-" {
                        if let sv = enclosingScrollView, let doc = sv.documentView {
                            let newMag = max(sv.minMagnification, sv.magnification / 1.25)
                            sv.setMagnification(newMag, centeredAt: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
                            findTopBar()?.updateZoom(newMag)
                        }
                        return
                    }
                    if event.charactersIgnoringModifiers == "1" {
                        if let sv = enclosingScrollView, let doc = sv.documentView {
                            let unscaledW = doc.frame.width / sv.magnification
                            let unscaledH = doc.frame.height / sv.magnification
                            guard unscaledW > 0, unscaledH > 0 else { return }
                            let clipSize = sv.contentView.bounds.size
                            let fitMag = min(clipSize.width / unscaledW, clipSize.height / unscaledH)
                            let clamped = max(sv.minMagnification, min(sv.maxMagnification, fitMag))
                            sv.magnification = clamped
                            findTopBar()?.updateZoom(clamped)
                        }
                        return
                    }
                }
            }
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 && spaceRepositioning {
            spaceRepositioning = false
            return
        }
        // Clear auto-measure preview on key release (click to commit instead)
        if let char = event.charactersIgnoringModifiers, char == "1" || char == "2" {
            if autoMeasureKeyHeld {
                autoMeasureKeyHeld = false
                autoMeasurePreview = nil
                autoMeasureBitmapCtx = nil  // free cached bitmap
                needsDisplay = true
                return
            }
        }
        super.keyUp(with: event)
    }
}
