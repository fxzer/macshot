//
//  OverlayView+Toolbar.swift
//  macshot
//
//  Toolbar hover, tooltip, menus, actions, and layout for OverlayView.
//

import AVFoundation
import AppKit

extension OverlayView {

    // MARK: - Toolbar Actions

    /// Handle right-click on a toolbar button (context menus, popovers).
    func handleToolbarButtonHover(
        _ action: ToolbarButtonAction,
        hovered: Bool,
        strip: ToolbarStripView?
    ) {
        if hovered {
            let btn = strip?.buttonViews.first { bv in
                if case .tool(let t1) = bv.action, case .tool(let t2) = action { return t1 == t2 }
                return "\(bv.action)" == "\(action)"
            }
            hoveredTooltip = btn?.tooltipText
            hoveredTooltipButtonView = btn
        } else {
            hoveredTooltip = nil
            hoveredTooltipButtonView = nil
        }
        needsDisplay = true
    }

    func drawHoveredTooltip() {
        if isEditorMode {
            updateEditorTooltipView()
            return
        }

        guard let tooltip = hoveredTooltip, !tooltip.isEmpty,
            let btn = hoveredTooltipButtonView,
            !PopoverHelper.isVisible
        else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ToolbarLayout.iconColor,
        ]
        let str = tooltip as NSString
        let textSize = str.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let tipW = textSize.width + pad * 2
        let tipH = textSize.height + pad

        let btnFrame = btn.convert(btn.bounds, to: self)
        let isBottomBar = btn.superview === bottomStripView
        let tipRect: NSRect

        if isBottomBar {
            var tipY = bottomBarRect.maxY + 4
            if tipY + tipH > bounds.maxY - 2 { tipY = bottomBarRect.minY - tipH - 4 }
            tipRect = NSRect(x: btnFrame.midX - tipW / 2, y: tipY, width: tipW, height: tipH)
        } else {
            tipRect = NSRect(
                x: btnFrame.minX - tipW - 6, y: btnFrame.midY - tipH / 2, width: tipW,
                height: tipH)
        }

        let clamped = NSRect(
            x: max(bounds.minX + 2, min(tipRect.minX, bounds.maxX - tipW - 2)),
            y: max(bounds.minY + 2, min(tipRect.minY, bounds.maxY - tipH - 2)),
            width: tipW, height: tipH)

        ToolbarLayout.bgColor.setFill()
        NSBezierPath(roundedRect: clamped, xRadius: 4, yRadius: 4).fill()
        str.draw(
            at: NSPoint(x: clamped.minX + pad, y: clamped.minY + pad / 2), withAttributes: attrs)
    }

    private func toolbarButtonView(for action: ToolbarButtonAction) -> ToolbarButtonView? {
        for strip in [bottomStripView, rightStripView] {
            if let button = strip?.buttonViews.first(where: { $0.action == action }) {
                return button
            }
        }
        return nil
    }

    private func updateToolbarButton(
        _ action: ToolbarButtonAction,
        isOn: Bool,
        sfSymbol: String? = nil
    ) {
        guard let button = toolbarButtonView(for: action) else { return }
        button.isOn = isOn
        if let sfSymbol {
            button.sfSymbol = sfSymbol
        }
        button.needsDisplay = true
    }

    /// In editor mode, show tooltip as a floating NSView in the chrome parent (container),
    /// since EditorView's draw() can only paint within the image bounds.
    private func updateEditorTooltipView() {
        guard let parent = chromeParentView else {
            editorTooltipView?.removeFromSuperview()
            editorTooltipView = nil
            return
        }

        guard let tooltip = hoveredTooltip, !tooltip.isEmpty,
            let btn = hoveredTooltipButtonView,
            !PopoverHelper.isVisible
        else {
            editorTooltipView?.removeFromSuperview()
            editorTooltipView = nil
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = tooltip as NSString
        let textSize = str.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let tipW = textSize.width + pad * 2
        let tipH = textSize.height + pad

        let btnFrame = btn.convert(btn.bounds, to: parent)
        let isTopBar = btn.superview is EditorTopBarView
        let isBottomBar = btn.superview === bottomStripView
        let tipRect: NSRect

        if isTopBar {
            let stripFrame = btn.superview?.frame ?? .zero
            var tipY = stripFrame.minY - tipH - 4
            if tipY < parent.bounds.minY + 2 { tipY = stripFrame.maxY + 4 }
            tipRect = NSRect(x: btnFrame.midX - tipW / 2, y: tipY, width: tipW, height: tipH)
        } else if isBottomBar {
            let stripFrame = bottomStripView?.frame ?? .zero
            var tipY = stripFrame.maxY + 4
            if tipY + tipH > parent.bounds.maxY - 2 { tipY = stripFrame.minY - tipH - 4 }
            tipRect = NSRect(x: btnFrame.midX - tipW / 2, y: tipY, width: tipW, height: tipH)
        } else {
            tipRect = NSRect(
                x: btnFrame.minX - tipW - 6, y: btnFrame.midY - tipH / 2, width: tipW,
                height: tipH)
        }

        let clamped = NSRect(
            x: max(parent.bounds.minX + 2, min(tipRect.minX, parent.bounds.maxX - tipW - 2)),
            y: max(parent.bounds.minY + 2, min(tipRect.minY, parent.bounds.maxY - tipH - 2)),
            width: tipW, height: tipH)

        let tip: TooltipBackgroundView
        if let existing = editorTooltipView as? TooltipBackgroundView {
            tip = existing
        } else {
            editorTooltipView?.removeFromSuperview()
            tip = TooltipBackgroundView(frame: clamped)
            parent.addSubview(tip)
            editorTooltipView = tip
        }
        tip.frame = clamped
        tip.text = tooltip
        tip.needsDisplay = true
    }

    func handleToolbarButtonRightClick(_ action: ToolbarButtonAction, anchorView: NSView) {
        switch action {
        case .autoRedact:
            showRedactTypePopover(
                anchorRect: anchorView.convert(anchorView.bounds, to: self), anchorView: anchorView)
        case .save:
            let menu = NSMenu()
            let saveAsItem = NSMenuItem(
                title: L("Save As..."), action: #selector(saveAsMenuAction), keyEquivalent: "")
            saveAsItem.target = self
            menu.addItem(saveAsItem)
            menu.popUp(
                positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
        case .upload:
            showUploadConfirmPopover(
                anchorRect: anchorView.convert(anchorView.bounds, to: self), anchorView: anchorView)
        case .translate:
            showTranslatePopover(
                anchorRect: anchorView.convert(anchorView.bounds, to: self), anchorView: anchorView)
        case .micAudio:
            showMicDeviceMenu(anchorView: anchorView)
        case .showKeystrokes:
            showKeystrokeModeMenu(anchorView: anchorView)
        case .webcam:
            showWebcamDeviceMenu(anchorView: anchorView)
        default:
            break
        }
    }

    private func showKeystrokeModeMenu(anchorView: NSView) {
        let menu = NSMenu()
        let allKeys = UserDefaults.standard.bool(forKey: "keystrokeShowAll")

        let shortcutsItem = NSMenuItem(
            title: L("Shortcuts Only"), action: #selector(keystrokeModeShortcuts),
            keyEquivalent: "")
        shortcutsItem.target = self
        if !allKeys { shortcutsItem.state = .on }
        menu.addItem(shortcutsItem)

        let allItem = NSMenuItem(
            title: L("All Keystrokes"), action: #selector(keystrokeModeAll), keyEquivalent: "")
        allItem.target = self
        if allKeys { allItem.state = .on }
        menu.addItem(allItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
    }

    @objc private func keystrokeModeShortcuts() {
        UserDefaults.standard.set(false, forKey: "keystrokeShowAll")
    }

    @objc private func keystrokeModeAll() {
        UserDefaults.standard.set(true, forKey: "keystrokeShowAll")
    }

    private func showMicDeviceMenu(anchorView: NSView) {
        let menu = NSMenu()
        let savedUID = UserDefaults.standard.string(forKey: "selectedMicDeviceUID")
        let micOn = UserDefaults.standard.bool(forKey: "recordMicAudio")

        let noneItem = NSMenuItem(title: L("None"), action: #selector(micMenuNone), keyEquivalent: "")
        noneItem.target = self
        if !micOn { noneItem.state = .on }
        menu.addItem(noneItem)
        menu.addItem(NSMenuItem.separator())

        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio, position: .unspecified).devices
            .filter { !$0.uniqueID.contains("CADefaultDeviceAggregate") }
        for device in devices {
            let item = NSMenuItem(
                title: device.localizedName, action: #selector(micMenuSelectDevice(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            if micOn
                && (savedUID == device.uniqueID
                    || (savedUID == nil && device == AVCaptureDevice.default(for: .audio)))
            {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
    }

    @objc private func micMenuNone() {
        UserDefaults.standard.set(false, forKey: "recordMicAudio")
        stopMicLevelMonitor()
        requestToolbarRebuild(reason: "micMenu")
    }

    @objc private func micMenuSelectDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: "selectedMicDeviceUID")
        UserDefaults.standard.set(true, forKey: "recordMicAudio")
        requestToolbarRebuild(reason: "micMenu")
        startMicLevelMonitor()
    }

    /// Update the color swatch on the main toolbar's color button without a full rebuild.
    func updateToolbarColorSwatch() {
        if let idx = bottomButtons.firstIndex(where: {
            if case .color = $0.action { return true } else { return false }
        }) {
            bottomButtons[idx].bgColor = currentColor
            bottomStripView?.updateState(from: bottomButtons)
            if idx < (bottomStripView?.buttonViews.count ?? 0) {
                let buttonView = bottomStripView?.buttonViews[idx]
                DispatchQueue.main.async {
                    buttonView?.needsDisplay = true
                }
            }
        }
    }

    func beautifyToolbarAnchorView() -> NSView? {
        rightStripView?.buttonViews.first {
            if case .beautify = $0.action { return true } else { return false }
        }
    }

    func handleToolbarAction(_ action: ToolbarButtonAction, mousePoint: NSPoint = .zero) {
        var shouldRebuildToolbar = false
        defer {
            if shouldRebuildToolbar {
                requestToolbarRebuild(reason: "toolbarAction")
            }
        }

        switch action {
        case .tool(let tool):
            shouldRebuildToolbar = true
            isMoveSelectionTemporary = false
            commitTextFieldIfNeeded()
            if currentTool == tool {
                currentTool = .select
            } else {
                currentTool = tool
            }
            if !selectedAnnotations.isEmpty {
                selectedAnnotations = []
                cachedCompositedImage = nil
            }
            if tool == .stamp && currentStampImage == nil {
                currentStampImage = StampEmojis.renderEmoji(StampEmojis.common[0])
                currentStampEmoji = StampEmojis.common[0]
            }
            if currentTool == .colorSampler && state == .selected {
                showColorSamplerMagnifier()
            } else if currentTool != .colorSampler {
                hideColorSamplerMagnifier()
            }
            if currentTool != .stamp {
                clearStampPreview()
            }
            if currentTool != .loupe {
                clearLoupePreview()
            }
            if currentTool != .select && currentTool != .marker {
                clearDrawingCursorPreview()
            }
            needsDisplay = true
        case .loupe:
            shouldRebuildToolbar = true
            isMoveSelectionTemporary = false
            currentTool = .loupe
            needsDisplay = true
        case .color:
            if PopoverHelper.isVisible { PopoverHelper.dismiss(); break }
            let colorBtn = bottomStripView?.buttonViews.first {
                if case .color = $0.action { return true }
                return false
            }
            showColorPickerPopover(target: .drawColor, anchorView: colorBtn)
        case .sizeDisplay:
            break
        case .moveSelection:
            guard !isEditorMode else { break }
            commitTextFieldIfNeeded()
            clearStampPreview()
            clearLoupePreview()
            clearDrawingCursorPreview()
            if selectionIsWindowSnap {
                selectionIsWindowSnap = false
                snappedWindowID = nil
                snappedWindowImage = nil
                shouldRebuildToolbar = true
            }
            isMoveSelectionTemporary = true
            moveSelectionRestoreTool = currentTool
            currentTool = .select
            shouldRebuildToolbar = true
            hoveredTooltip = L("Drag to reposition the selection")
            needsDisplay = true
        case .undo:
            shouldRebuildToolbar = true
            undo()
        case .redo:
            shouldRebuildToolbar = true
            redo()
        case .copy:
            overlayDelegate?.overlayViewDidConfirm()
        case .save:
            overlayDelegate?.overlayViewDidRequestFileSave()
        case .upload:
            let confirmEnabled = UserDefaults.standard.bool(forKey: "uploadConfirmEnabled")
            if confirmEnabled {
                let provider = UserDefaults.standard.string(forKey: "uploadProvider") ?? "imgbb"
                let title: String
                switch provider {
                case "gdrive":
                    title = L("Upload to Google Drive?")
                case "s3":
                    title = L("Upload to S3?")
                case "smms":
                    title = L("Upload to SM.MS?")
                case "cfimgbed":
                    title = L("Upload to CloudFlare ImgBed?")
                default:
                    title = L("Upload to imgbb.com?")
                }
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = L("Your screenshot will be uploaded.")
                alert.addButton(withTitle: L("Upload"))
                alert.addButton(withTitle: L("Cancel"))
                alert.alertStyle = .informational
                let originalLevel = window?.level ?? .statusBar
                window?.level = .normal
                let response = alert.runModal()
                window?.level = originalLevel
                if response == .alertFirstButtonReturn {
                    overlayDelegate?.overlayViewDidRequestUpload()
                }
            } else {
                overlayDelegate?.overlayViewDidRequestUpload()
            }
        case .share:
            let shareBtn = rightStripView?.buttonViews.first {
                if case .share = $0.action { return true }
                return false
            }
            overlayDelegate?.overlayViewDidRequestShare(anchorView: shareBtn)
        case .pin:
            overlayDelegate?.overlayViewDidRequestPin()
        case .ocr:
            overlayDelegate?.overlayViewDidRequestOCR()
        case .autoRedact:
            performAutoRedact()
        case .removeBackground:
            if #available(macOS 14.0, *) {
                overlayDelegate?.overlayViewDidRequestRemoveBackground()
            }
        case .invertColors:
            invertImageColors()
        case .effects:
            let btn = rightStripView?.buttonViews.first {
                if case .effects = $0.action { return true }
                return false
            }
            showEffectsPopover(anchorView: btn)
        case .beautify:
            let btn = rightStripView?.buttonViews.first {
                if case .beautify = $0.action { return true } else { return false }
            }
            showBeautifyPopover(anchorView: btn)
        case .beautifyStyle:
            beautifyStyleIndex = (beautifyStyleIndex + 1) % beautifyStyles.count
            UserDefaults.standard.set(beautifyStyleIndex, forKey: "beautifyStyleIndex")
            needsDisplay = true
        case .delayCapture:
            break
        case .translate:
            shouldRebuildToolbar = true
            if translateEnabled {
                translateEnabled = false
                annotations.removeAll { $0.tool == .translateOverlay }
                isTranslating = false
            } else {
                translateEnabled = true
                performTranslate(targetLang: TranslationService.targetLanguage)
            }
            needsDisplay = true
        case .record:
            overlayDelegate?.overlayViewDidRequestEnterRecordingMode()
        case .startRecord:
            overlayDelegate?.overlayViewDidRequestStartRecording(rect: selectionRect)
        case .stopRecord:
            isRecording = false
            overlayDelegate?.overlayViewDidCancel()
        case .mouseHighlight:
            let current = UserDefaults.standard.bool(forKey: "recordMouseHighlight")
            let next = !current
            UserDefaults.standard.set(next, forKey: "recordMouseHighlight")
            updateToolbarButton(.mouseHighlight, isOn: next)
        case .showKeystrokes:
            toggleKeystrokeOverlay()
        case .systemAudio:
            let current = UserDefaults.standard.bool(forKey: "recordSystemAudio")
            let next = !current
            UserDefaults.standard.set(next, forKey: "recordSystemAudio")
            updateToolbarButton(
                .systemAudio,
                isOn: next,
                sfSymbol: next ? "speaker.wave.2.fill" : "speaker.slash"
            )
        case .micAudio:
            toggleMicAudio()
        case .webcam:
            toggleWebcamOverlay()
        case .cancel:
            overlayDelegate?.overlayViewDidCancel()
        case .detach:
            overlayDelegate?.overlayViewDidRequestDetach()
        case .scrollCapture:
            overlayDelegate?.overlayViewDidRequestScrollCapture(rect: selectionRect)
        case .addCapture:
            overlayDelegate?.overlayViewDidRequestAddCapture()
        case .recordSettings:
            let gearBtn = rightStripView?.buttonViews.first {
                if case .recordSettings = $0.action { return true }
                return false
            }
            showRecordingSettingsPopover(anchorView: gearBtn)
        }
    }

    // MARK: - Toolbar Layout

    /// Rebuild toolbar button content. Call when tool, color, or state changes — NOT on every draw.
    func rebuildToolbarLayout(reason explicitReason: String? = nil) {
        let t0 = CFAbsoluteTimeGetCurrent()
        toolbarRebuildSequence += 1
        let rebuildID = toolbarRebuildSequence
        let reason = explicitReason ?? pendingToolbarRebuildReason ?? "direct"
        pendingToolbarRebuildReason = nil
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild BEGIN id=\(rebuildID) reason=\(reason) tool=\(String(describing: currentTool)) state=\(String(describing: state)) annotations=\(annotations.count) selected=\(selectedAnnotations.count) showToolbars=\(showToolbars)"
        )
        hoveredTooltip = nil
        hoveredTooltipButtonView = nil

        let buttonModelT0 = CFAbsoluteTimeGetCurrent()
        let movableAnnotations = annotations.contains { $0.isMovable }
        bottomButtons = ToolbarLayout.bottomButtons(
            selectedTool: currentTool, selectedColor: currentColor,
            beautifyEnabled: beautifyEnabled, beautifyStyleIndex: beautifyStyleIndex,
            hasAnnotations: movableAnnotations, isRecording: isRecording,
            effectsActive: effectsActive,
            isEditorMode: isEditorMode
        )
        rightButtons = ToolbarLayout.rightButtons(
            selectedTool: currentTool,
            beautifyEnabled: beautifyEnabled, beautifyStyleIndex: beautifyStyleIndex,
            hasAnnotations: movableAnnotations, effectsActive: effectsActive,
            translateEnabled: translateEnabled,
            isRecording: isRecording,
            isEditorMode: isEditorMode)
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) buttonModels elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - buttonModelT0) * 1000))ms bottomCount=\(bottomButtons.count) rightCount=\(rightButtons.count)"
        )

        let parent = chromeParentView ?? self
        let stripCreationT0 = CFAbsoluteTimeGetCurrent()
        if bottomStripView == nil {
            let strip = ToolbarStripView(orientation: .horizontal)
            parent.addSubview(strip)
            bottomStripView = strip
        }
        if rightStripView == nil {
            let strip = ToolbarStripView(orientation: .vertical)
            parent.addSubview(strip)
            rightStripView = strip
        }
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) ensureStrips elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - stripCreationT0) * 1000))ms parent=\(chromeParentView == nil ? "overlay" : "chromeParent")"
        )

        var bottomMode = "noop"
        let bottomStripT0 = CFAbsoluteTimeGetCurrent()
        if bottomStripView?.buttonViews.count == bottomButtons.count
            && bottomStripView?.buttonViews.count ?? 0 > 0
        {
            bottomMode = "updateState"
            bottomStripView?.updateState(from: bottomButtons)
        } else {
            bottomMode = "setButtons"
            bottomStripView?.setButtons(bottomButtons)
            bottomStripView?.onClick = { [weak self] action in self?.handleToolbarAction(action) }
            bottomStripView?.onRightClick = { [weak self] action, view in
                self?.handleToolbarButtonRightClick(action, anchorView: view)
            }
            bottomStripView?.onHover = { [weak self] action, hovered in
                self?.handleToolbarButtonHover(action, hovered: hovered, strip: self?.bottomStripView)
            }
        }
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) bottomStrip elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - bottomStripT0) * 1000))ms mode=\(bottomMode)"
        )

        var rightMode = "noop"
        let rightStripT0 = CFAbsoluteTimeGetCurrent()
        if rightStripView?.buttonViews.count == rightButtons.count
            && rightStripView?.buttonViews.count ?? 0 > 0
        {
            rightMode = "updateState"
            rightStripView?.updateState(from: rightButtons)
        } else {
            rightMode = "setButtons"
            rightStripView?.setButtons(rightButtons)
            rightStripView?.onClick = { [weak self] action in self?.handleToolbarAction(action) }
            rightStripView?.onRightClick = { [weak self] action, view in
                self?.handleToolbarButtonRightClick(action, anchorView: view)
            }
            rightStripView?.onHover = { [weak self] action, hovered in
                self?.handleToolbarButtonHover(action, hovered: hovered, strip: self?.rightStripView)
            }
        }
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) rightStrip elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - rightStripT0) * 1000))ms mode=\(rightMode)"
        )

        let moveButtonT0 = CFAbsoluteTimeGetCurrent()
        for bv in rightStripView?.buttonViews ?? [] {
            if case .moveSelection = bv.action, bv.onMouseDown == nil {
                bv.onMouseDown = { [weak self] _ in self?.handleToolbarAction(.moveSelection) }
            }
        }

        for strip in [topStripView, rightStripView] {
            for bv in strip?.buttonViews ?? [] {
                if case .moveSelection = bv.action, bv.onMouseDown == nil {
                    bv.onMouseDown = { [weak self] _ in self?.handleToolbarAction(.moveSelection) }
                }
            }
        }
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) moveHook elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - moveButtonT0) * 1000))ms"
        )

        var optionsMode = "hidden"
        let optionsT0 = CFAbsoluteTimeGetCurrent()
        if toolHasOptionsRow {
            if toolOptionsRowView == nil {
                let row = ToolOptionsRowView(
                    frame: NSRect(
                        x: 0,
                        y: 0,
                        width: ToolOptionsRowView.defaultWidth,
                        height: ToolOptionsRowView.defaultHeight
                    )
                )
                row.overlayView = self
                parent.addSubview(row)
                toolOptionsRowView = row
                optionsMode = "create"
            }
            if let ann = selectedAnnotation, toolOptionsRowView?.editingAnnotation === ann {
                optionsMode = optionsMode == "create" ? "create+updateSwatch" : "updateSwatch"
                toolOptionsRowView?.updateSwatchColors()
            } else {
                optionsMode = optionsMode == "create" ? "create+rebuild" : "rebuild"
                toolOptionsRowView?.rebuild(for: currentTool)
            }
        }
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) toolOptions elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - optionsT0) * 1000))ms mode=\(optionsMode)"
        )

        let positioningT0 = CFAbsoluteTimeGetCurrent()
        repositionToolbars()
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) reposition elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - positioningT0) * 1000))ms"
        )

        let undoT0 = CFAbsoluteTimeGetCurrent()
        updateUndoRedoButtonStates()
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild STEP id=\(rebuildID) undoRedo elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - undoT0) * 1000))ms"
        )
        CaptureDiagnostics.log(
            "[macshot-perf][toolbar] rebuild DONE id=\(rebuildID) elapsed=\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms reason=\(reason) bottomMode=\(bottomMode) rightMode=\(rightMode) options=\(optionsMode)"
        )
        CaptureDiagnostics.log(
            "[macshot-mem][toolbar] rebuild DONE id=\(rebuildID) reason=\(reason) cacheEstimate=\(MemoryDiagnostics.format(bytes: UInt64(estimatedCacheMemory))) \(MemoryDiagnostics.currentSummary())"
        )
    }

    /// Update undo/redo button enabled states based on stack availability.
    func updateUndoRedoButtonStates() {
        let canUndo = !undoStack.isEmpty
        let canRedo = !redoStack.isEmpty

        for strip in [bottomStripView, rightStripView].compactMap({ $0 }) {
            for bv in strip.buttonViews {
                switch bv.action {
                case .undo:
                    bv.isEnabled = canUndo
                case .redo:
                    bv.isEnabled = canRedo
                default:
                    break
                }
            }
        }
    }

    func requestToolbarRebuild(reason: String = "deferred") {
        guard showToolbars else { return }
        scheduleDeferredToolbarRebuild(reason: reason)
    }

    /// Coalesced async toolbar rebuild — avoids blocking event handling (e.g. mouseUp after marquee).
    func scheduleDeferredToolbarRebuild(reason: String = "deferred") {
        guard showToolbars else {
            CaptureDiagnostics.log(
                "[macshot-perf][toolbar] schedule SKIP reason=\(reason) showToolbars=false"
            )
            return
        }
        guard !pendingToolbarRebuild else {
            if let existingReason = pendingToolbarRebuildReason,
               !existingReason.contains(reason) {
                pendingToolbarRebuildReason = "\(existingReason)|\(reason)"
            } else if pendingToolbarRebuildReason == nil {
                pendingToolbarRebuildReason = reason
            }
            CaptureDiagnostics.log(
                "[macshot-perf][toolbar] schedule COALESCE reason=\(reason) pendingReason=\(pendingToolbarRebuildReason ?? reason)"
            )
            return
        }
        pendingToolbarRebuild = true
        pendingToolbarRebuildReason = reason
        CaptureDiagnostics.log("[macshot-perf][toolbar] schedule reason=\(reason)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let rebuildReason = self.pendingToolbarRebuildReason ?? reason
            self.pendingToolbarRebuild = false
            self.pendingToolbarRebuildReason = nil
            guard self.showToolbars, self.window != nil else { return }
            self.rebuildToolbarLayout(reason: rebuildReason)
        }
    }

    /// Reposition toolbar strips based on current selection/bounds. Cheap — safe to call from draw().
    func repositionToolbars() {
        guard let bottomStrip = bottomStripView, let rightStrip = rightStripView else { return }

        bottomStrip.passesThrough = isEditorMode
        rightStrip.passesThrough = isEditorMode

        let visible = showToolbars && state == .selected && !isScrollCapturing
        let bottomHasButtons = bottomStrip.buttonViews.count > 0
        bottomStrip.isHidden = !visible || !bottomHasButtons
        let rightHasButtons = rightStrip.buttonViews.count > 0
        rightStrip.isHidden = !visible || !rightHasButtons
        toolOptionsRowView?.isHidden = !visible || !toolHasOptionsRow || !bottomHasButtons
        guard visible else { return }

        let config = beautifyConfig
        let bPad = config.padding
        let titleBarH: CGFloat = config.mode == .window ? 28 : 0
        let expandedAnchor = NSRect(
            x: selectionRect.minX - bPad, y: selectionRect.minY - bPad,
            width: selectionRect.width + bPad * 2,
            height: selectionRect.height + titleBarH + bPad * 2)
        let anchorRect: NSRect
        if beautifyToolbarAnimProgress < 1.0 {
            let t = beautifyToolbarAnimProgress
            let eased = 1.0 - (1.0 - t) * (1.0 - t)
            let fromRect = beautifyToolbarAnimTarget ? selectionRect : expandedAnchor
            let toRect = beautifyToolbarAnimTarget ? expandedAnchor : selectionRect
            anchorRect = NSRect(
                x: fromRect.minX + (toRect.minX - fromRect.minX) * eased,
                y: fromRect.minY + (toRect.minY - fromRect.minY) * eased,
                width: fromRect.width + (toRect.width - fromRect.width) * eased,
                height: fromRect.height + (toRect.height - fromRect.height) * eased
            )
        } else if beautifyEnabled && !isScrollCapturing && !isRecording {
            anchorRect = expandedAnchor
        } else {
            anchorRect = selectionRect
        }

        let rightSize = rightStrip.frame.size
        let bottomSize = bottomStrip.frame.size

        if isEditorMode {
            let cb = chromeParentView?.bounds ?? bounds
            bottomStrip.frame.origin = NSPoint(x: cb.midX - bottomSize.width / 2, y: 8)
            bottomStrip.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]

            if let topStrip = topStripView {
                let topBarBottom = topStrip.frame.minY
                rightStrip.frame.origin = NSPoint(
                    x: cb.maxX - rightSize.width - 8,
                    y: topBarBottom - 24 - rightSize.height)
            } else {
                rightStrip.frame.origin = NSPoint(
                    x: cb.maxX - rightSize.width - 8,
                    y: cb.maxY - EditorTopBarView.height - 20 - 8 - rightSize.height)
            }
            rightStrip.autoresizingMask = [.minXMargin, .minYMargin]
        } else {
            let optRowH: CGFloat = 38

            let rightMargin: CGFloat = 50
            let rightFitsRight = anchorRect.maxX < bounds.maxX - rightMargin
            let rightFitsLeft = anchorRect.minX > bounds.minX + rightMargin
            let selectionTooNarrow = !rightFitsRight && !rightFitsLeft
                && anchorRect.width < bounds.width * 0.5

            var rx: CGFloat
            var ry: CGFloat

            if selectionTooNarrow {
                rx = anchorRect.maxX - rightSize.width
                rx = max(bounds.minX + 4, min(rx, bounds.maxX - rightSize.width - 4))
                ry = anchorRect.minY - rightSize.height - 6
                ry = max(bounds.minY + 4, min(ry, bounds.maxY - rightSize.height - 4))
            } else {
                if rightFitsRight {
                    rx = anchorRect.maxX + 6
                } else if rightFitsLeft {
                    rx = anchorRect.minX - rightSize.width - 6
                } else {
                    rx = selectionRect.maxX - rightSize.width - 6
                }
                rx = max(bounds.minX + 4, min(rx, bounds.maxX - rightSize.width - 4))

                ry = anchorRect.maxY - rightSize.height
                ry = max(bounds.minY + 4, min(ry, bounds.maxY - rightSize.height - 4))
            }

            let belowY = anchorRect.minY - bottomSize.height - 6
            let belowFits = (belowY - optRowH) >= bounds.minY + 4
            let aboveY = anchorRect.maxY + optRowH + 6
            let aboveFits = (aboveY + bottomSize.height) <= bounds.maxY - 4

            let centeredBx = anchorRect.midX - bottomSize.width / 2
            let clampedCenteredBx =
                max(bounds.minX + 4, min(centeredBx, bounds.maxX - bottomSize.width - 4))
            func wouldOverlapRight(candidateY: CGFloat) -> Bool {
                let bMinY = candidateY - optRowH
                let bMaxY = candidateY + bottomSize.height
                guard bMaxY > ry && bMinY < ry + rightSize.height else { return false }
                let bMaxX = clampedCenteredBx + bottomSize.width
                let bMinX = clampedCenteredBx
                return bMaxX > rx && bMinX < rx + rightSize.width
            }

            var by: CGFloat
            if belowFits && !wouldOverlapRight(candidateY: belowY) {
                by = belowY
            } else if aboveFits && !wouldOverlapRight(candidateY: aboveY) {
                by = aboveY
            } else if belowFits {
                by = belowY
            } else if aboveFits {
                by = aboveY
            } else {
                by = selectionRect.minY + optRowH + 6
                by = max(
                    bounds.minY + optRowH + 4,
                    min(by, bounds.maxY - bottomSize.height - 4))
            }

            var bx = clampedCenteredBx
            let bottomMinY = by - optRowH
            let bottomMaxY = by + bottomSize.height
            let overlapsVertically = bottomMaxY > ry && bottomMinY < ry + rightSize.height

            if overlapsVertically {
                if bx + bottomSize.width <= rx - 4 || bx >= rx + rightSize.width + 4 {
                    // No overlap.
                } else {
                    let pushRight = bx + bottomSize.width + 4
                    let pushLeft = bx - rightSize.width - 4

                    if pushRight + rightSize.width <= bounds.maxX - 4 {
                        rx = pushRight
                    } else if pushLeft >= bounds.minX + 4 {
                        rx = pushLeft
                    } else {
                        let rightPushDown = by - optRowH - rightSize.height - 4
                        if rightPushDown >= bounds.minY + 4 {
                            ry = rightPushDown
                        } else {
                            let rightPushUp = by + bottomSize.height + 4
                            if rightPushUp + rightSize.height <= bounds.maxY - 4 {
                                ry = rightPushUp
                            }
                        }
                    }
                }
            }
            bx = max(bounds.minX + 4, min(bx, bounds.maxX - bottomSize.width - 4))

            bottomStrip.frame.origin = NSPoint(x: bx, y: by)
            rightStrip.frame.origin = NSPoint(x: rx, y: ry)
        }

        bottomBarRect = bottomStrip.frame
        rightBarRect = rightStrip.frame

        if let row = toolOptionsRowView, !row.isHidden {
            let rowW = max(bottomBarRect.width, row.contentWidth)
            row.frame.size.width = rowW
            if isEditorMode {
                let alignmentRect = bottomBarRect
                let rowX = max(4, alignmentRect.midX - rowW / 2)
                row.frame.origin = NSPoint(x: rowX, y: bottomBarRect.maxY + 2)
                row.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            } else {
                var rowX = bottomBarRect.midX - rowW / 2
                rowX = max(4, min(rowX, bounds.maxX - rowW - 4))
                let rowY = bottomBarRect.minY - row.frame.height - 2
                row.frame.origin = NSPoint(x: rowX, y: rowY)
            }
        }
    }
}
