//
//  OverlayView+ToolbarActions.swift
//  macshot
//
//  Toolbar hover, tooltip, menus, and actions for OverlayView.
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
        rebuildToolbarLayout()
    }

    @objc private func micMenuSelectDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: "selectedMicDeviceUID")
        UserDefaults.standard.set(true, forKey: "recordMicAudio")
        rebuildToolbarLayout()
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
        switch action {
        case .tool(let tool):
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
            toolOptionsRowView?.rebuild(for: currentTool)
            needsDisplay = true
        case .loupe:
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
            guard let win = window else { break }
            clearStampPreview()
            clearLoupePreview()
            clearDrawingCursorPreview()
            if selectionIsWindowSnap {
                selectionIsWindowSnap = false
                snappedWindowID = nil
                snappedWindowImage = nil
                rebuildToolbarLayout()
            }
            hoveredTooltip = L("Drag to reposition")
            needsDisplay = true
            displayIfNeeded()
            let startPoint = convert(win.mouseLocationOutsideOfEventStream, from: nil)
            let offset = NSPoint(
                x: startPoint.x - selectionRect.origin.x, y: startPoint.y - selectionRect.origin.y)
            let hasWebcam = webcamSetupPreview != nil
            while true {
                guard let event = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                    break
                }
                let point = convert(event.locationInWindow, from: nil)
                selectionRect.origin = NSPoint(x: point.x - offset.x, y: point.y - offset.y)
                if hasWebcam { repositionWebcamSetupPreview() }
                needsDisplay = true
                displayIfNeeded()
                if event.type == .leftMouseUp { break }
            }
            hoveredTooltip = (hoveredTooltipButtonView as? ToolbarButtonView)?.tooltipText
            if let moveBtn = rightStripView?.buttonViews.first(where: {
                if case .moveSelection = $0.action { return true }
                return false
            }) {
                moveBtn.isPressed = false
                moveBtn.needsDisplay = true
            }
            scheduleBarcodeDetection()
            needsDisplay = true
        case .undo:
            undo()
        case .redo:
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
            UserDefaults.standard.set(!current, forKey: "recordMouseHighlight")
            rebuildToolbarLayout()
        case .showKeystrokes:
            toggleKeystrokeOverlay()
        case .systemAudio:
            let current = UserDefaults.standard.bool(forKey: "recordSystemAudio")
            UserDefaults.standard.set(!current, forKey: "recordSystemAudio")
            rebuildToolbarLayout()
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

        rebuildToolbarLayout()
    }
}
