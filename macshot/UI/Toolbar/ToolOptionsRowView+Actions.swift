//
//  ToolOptionsRowView+Actions.swift
//  macshot
//
//  Action handlers for tool options controls.
//

import Cocoa

extension ToolOptionsRowView {

    // Dead code removed
    @objc func drawColorClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .drawColor, anchorView: sender)
    }

    @objc func strokeSliderChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        let val = CGFloat(sender.floatValue)
        let tool = editingAnnotation?.tool ?? currentTool
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.strokeWidth = val
            ov.invalidateCommittedAnnotationRendering()
        }
        if let tool { ov.setActiveStrokeWidth(val, for: tool) }
        if let label = viewWithTag(ToolOptionTag.strokeValueLabel.rawValue) as? NSTextField {
            label.stringValue = tool == .loupe ? "\(Int(val))" : "\(Int(val))px"
        }
        ov.needsDisplay = true
    }

    @objc func lineStyleChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        guard let style = LineStyle(rawValue: sender.selectedSegment) else { return }
        let tool = editingAnnotation?.tool ?? currentTool ?? .line
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.lineStyle = style
            ov.invalidateCommittedAnnotationRendering()
        }
        ov.setLineStyle(style, for: tool)
        ov.needsDisplay = true
    }

    @objc func arrowStyleChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        guard let style = ArrowStyle(rawValue: sender.selectedSegment) else { return }
        let tool = editingAnnotation?.tool ?? currentTool ?? .arrow
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.arrowStyle = style
            if style == .thick {
                ann.lineStyle = .solid
            }
            ov.invalidateCommittedAnnotationRendering()
        }
        ov.setArrowStyle(style, for: tool)
        if style == .thick {
            ov.setLineStyle(.solid, for: tool)
        }
        if let ann = editingAnnotation {
            rebuild(forAnnotation: ann)
        } else {
            rebuild(for: tool)
        }
        ov.needsDisplay = true
    }

    @objc func shapeFillChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        guard let style = RectFillStyle(rawValue: sender.selectedSegment) else { return }
        let tool = editingAnnotation?.tool ?? currentTool ?? .rectangle
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.rectFillStyle = style
            ov.invalidateCommittedAnnotationRendering()
        }
        ov.setRectFillStyle(style, for: tool)
        ov.needsDisplay = true
    }

    @objc func cornerRadiusChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        let val = CGFloat(sender.floatValue)
        let tool = editingAnnotation?.tool ?? currentTool ?? .rectangle
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.rectCornerRadius = val
            ov.invalidateCommittedAnnotationRendering()
        }
        ov.setRectCornerRadius(val, for: tool)
        if let label = viewWithTag(ToolOptionTag.cornerRadiusLabel.rawValue) as? NSTextField {
            label.stringValue = "\(Int(val))px"
        }
        ov.needsDisplay = true
    }

    @objc func censorModeChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView,
              let mode = CensorMode(rawValue: sender.selectedSegment) else { return }
        UserDefaults.standard.set(mode.rawValue, forKey: "censorMode")
        guard let ann = editingAnnotation,
              ann.tool == .pixelate || ann.tool == .blur
        else {
            ov.needsDisplay = true
            return
        }

        ensureSnapshot()
        ann.censorMode = mode
        if mode != .solid {
            ann.sourceImage = ann.sourceImage ?? ov.screenshotImage
            ann.sourceImageBounds = ov.captureDrawRect
        }
        ann.bakedBlurNSImage = nil
        ann.bakePixelate()
        ov.invalidateCommittedAnnotationRendering()
        ov.needsDisplay = true
    }

    @objc func numberFormatChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        if let fmt = NumberFormat(rawValue: sender.selectedSegment) {
            ov.currentNumberFormat = fmt
            UserDefaults.standard.set(fmt.rawValue, forKey: "numberFormat")
            if let label = viewWithTag(ToolOptionTag.numberStartValueLabel.rawValue) as? NSTextField {
                label.stringValue = fmt.format(ov.numberStartAt)
                label.sizeToFit()
            }
            ov.needsDisplay = true
        }
    }

    @objc func numberStartChanged(_ sender: NSStepper) {
        guard let ov = overlayView else { return }
        ov.numberStartAt = sender.integerValue
        UserDefaults.standard.set(sender.integerValue, forKey: "numberStartAt")
        if let label = viewWithTag(ToolOptionTag.numberStartValueLabel.rawValue) as? NSTextField {
            label.stringValue = ov.currentNumberFormat.format(sender.integerValue)
            label.sizeToFit()
        }
        ov.needsDisplay = true
    }

    @objc func boldToggled() {
        overlayView?.textEditor.toggleBold()
        overlayView.map { ov in
            ov.applyTextFormattingToSelectedAnnotations()
            ov.needsDisplay = true
            updateFormattingButtons()
        }
    }

    @objc func italicToggled() {
        overlayView?.textEditor.toggleItalic()
        overlayView.map { ov in
            ov.applyTextFormattingToSelectedAnnotations()
            ov.needsDisplay = true
            updateFormattingButtons()
        }
    }

    @objc func underlineToggled() {
        overlayView?.textEditor.toggleUnderline()
        overlayView.map { ov in
            ov.applyTextFormattingToSelectedAnnotations()
            ov.needsDisplay = true
            updateFormattingButtons()
        }
    }

    @objc func strikethroughToggled() {
        overlayView?.textEditor.toggleStrikethrough()
        overlayView.map { ov in
            ov.applyTextFormattingToSelectedAnnotations()
            ov.needsDisplay = true
            updateFormattingButtons()
        }
    }

    @objc func measureUnitChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        ov.currentMeasureInPoints = sender.selectedSegment == 1
        UserDefaults.standard.set(ov.currentMeasureInPoints, forKey: "measureInPoints")
        if let ann = editingAnnotation, ann.tool == .measure {
            ensureSnapshot()
            ann.measureInPoints = ov.currentMeasureInPoints
            ov.invalidateCommittedAnnotationRendering()
        }
        ov.needsDisplay = true
    }

    @objc func quickEmojiClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.currentStampImage = StampEmojis.renderEmoji(sender.title)
        ov.currentStampEmoji = sender.title
        ov.needsDisplay = true
    }

    @objc func moreEmojisClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.showEmojiPopover(anchorView: sender)
    }

    @objc func loadImageClicked() {
        guard let ov = overlayView else { return }
        StampEmojis.loadStampImage { [weak ov] image in
            ov?.currentStampImage = image
            ov?.currentStampEmoji = nil
            ov?.needsDisplay = true
        }
    }

    @objc func drawModeChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        let textOnly = sender.selectedSegment == 1
        UserDefaults.standard.set(textOnly, forKey: "censorTextOnly")
        guard let ann = editingAnnotation,
              ann.tool == .pixelate || ann.tool == .blur
        else {
            ov.needsDisplay = true
            return
        }

        ensureSnapshot()
        ann.censorDrawScope = textOnly ? .textOnly : .all
        if ann.censorMode != .solid {
            ann.sourceImage = ann.sourceImage ?? ov.screenshotImage
            ann.sourceImageBounds = ov.captureDrawRect
        }
        ann.bakedBlurNSImage = nil
        ann.bakePixelate()
        ov.invalidateCommittedAnnotationRendering()
        ov.needsDisplay = true
    }

    @objc func pencilSmoothModeChanged(_ sender: NSSegmentedControl) {
        let mode = sender.selectedSegment
        overlayView?.pencilSmoothMode = mode
        UserDefaults.standard.set(mode, forKey: "pencilSmoothMode")
    }

    @objc func redactAllTextClicked() {
        overlayView?.performRedactAllText()
    }

    @objc func redactPIIClicked() {
        overlayView?.performAutoRedact()
    }

    @objc func redactFacesClicked() {
        overlayView?.performRedactFaces()
    }

    @objc func redactPeopleClicked() {
        overlayView?.performRedactPeople()
    }

    @objc func redactTypesClicked(_ sender: NSView) {
        guard let ov = overlayView else { return }
        ov.showRedactTypePopover(anchorRect: .zero, anchorView: sender)
    }

    @objc func fontFamilyClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        let picker = FontPickerView(selectedFamily: ov.textEditor.fontFamily)
        picker.onSelect = { [weak ov] family in
            guard let ov = ov else { return }
            ov.textEditor.fontFamily = family
            UserDefaults.standard.set(family, forKey: "textFontFamily")
            ov.textEditor.applyFontSizeChange()
            ov.applyTextFormattingToSelectedAnnotations()
            ov.requestToolbarRebuild(reason: "fontFamily")
            ov.needsDisplay = true
            PopoverHelper.dismiss()
        }
        PopoverHelper.show(picker, size: picker.preferredSize, relativeTo: sender.bounds, of: sender, preferredEdge: .maxY, type: .fontFamily)
        DispatchQueue.main.async {
            picker.scrollToSelected()
        }
    }

    @objc func alignmentChanged(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        if let align = NSTextAlignment(rawValue: sender.tag) {
            ov.textEditor.alignment = align
            ov.textEditor.applyAlignment()
            ov.applyTextFormattingToSelectedAnnotations()
            updateFormattingButtons()
            ov.needsDisplay = true
        }
    }

    @objc func fontSizeDecreased() {
        guard let ov = overlayView else { return }
        ov.textEditor.fontSize = max(8, ov.textEditor.fontSize - 1)
        UserDefaults.standard.set(Double(ov.textEditor.fontSize), forKey: "textFontSize")
        ov.textEditor.applyFontSizeChange()
        ov.textEditor.resizeToFit()
        ov.applyTextFormattingToSelectedAnnotations()
        if let label = viewWithTag(ToolOptionTag.textFontSizeLabel.rawValue) as? NSTextField { label.stringValue = "\(Int(ov.textEditor.fontSize))" }
        ov.needsDisplay = true
    }

    @objc func fontSizeIncreased() {
        guard let ov = overlayView else { return }
        ov.textEditor.fontSize = min(200, ov.textEditor.fontSize + 1)
        UserDefaults.standard.set(Double(ov.textEditor.fontSize), forKey: "textFontSize")
        ov.textEditor.applyFontSizeChange()
        ov.textEditor.resizeToFit()
        ov.applyTextFormattingToSelectedAnnotations()
        if let label = viewWithTag(ToolOptionTag.textFontSizeLabel.rawValue) as? NSTextField { label.stringValue = "\(Int(ov.textEditor.fontSize))" }
        ov.needsDisplay = true
    }

    @objc func textBgToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.textEditor.bgEnabled = sender.state == .on
        UserDefaults.standard.set(ov.textEditor.bgEnabled, forKey: "textBgEnabled")
        if let swatch = viewWithTag(ToolOptionTag.textBgColorSwatch.rawValue) { swatch.layer?.opacity = ov.textEditor.bgEnabled ? 1.0 : 0.3 }
        ov.applyTextBgOutlineToSelectedAnnotations()
        ov.needsDisplay = true
    }

    @objc func textOutlineToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.textEditor.outlineEnabled = sender.state == .on
        UserDefaults.standard.set(ov.textEditor.outlineEnabled, forKey: "textOutlineEnabled")
        if let swatch = viewWithTag(ToolOptionTag.textOutlineColorSwatch.rawValue) { swatch.layer?.opacity = ov.textEditor.outlineEnabled ? 1.0 : 0.3 }
        ov.applyTextBgOutlineToSelectedAnnotations()
        ov.needsDisplay = true
    }

    @objc func textBgColorClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .textBg, anchorView: sender)
    }

    @objc func textOutlineColorClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .textOutline, anchorView: sender)
    }

    @objc func fpsChanged(_ sender: NSSlider) {
        let fps = Int(sender.floatValue)
        UserDefaults.standard.set(fps, forKey: "recordingFPS")
        if let label = viewWithTag(ToolOptionTag.fpsValueLabel.rawValue) as? NSTextField {
            label.stringValue = "\(fps)"
        }
    }

    @objc func recordingFormatChanged(_ sender: NSSegmentedControl) {
        let format = sender.selectedSegment == 0 ? "mp4" : "gif"
        UserDefaults.standard.set(format, forKey: "recordingFormat")
    }

    @objc func highlightClicksToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "highlightMouseClicks")
    }

    @objc func annotationOutlineToggled(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        let isOn = sender.state == .on
        let tool = editingAnnotation?.tool ?? ov.currentTool
        ov.setOutlineEnabled(isOn, for: tool)
        if let swatch = viewWithTag(ToolOptionTag.annotationOutlineColorSwatch.rawValue) { swatch.layer?.opacity = isOn ? 1.0 : 0.3 }
        if let ann = editingAnnotation {
            ensureSnapshot()
            ann.outlineColor = isOn ? ToolOptionsRowView.savedOutlineColor : nil
            ov.invalidateCommittedAnnotationRendering()
        }
        if tool == .rectangle || tool == .ellipse {
            if let ann = editingAnnotation {
                rebuild(forAnnotation: ann)
            } else {
                rebuild(for: tool)
            }
        }
        ov.needsDisplay = true
    }

    @objc func annotationOutlineColorClicked(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.showColorPickerPopover(target: .annotationOutline, anchorView: sender)
    }

    @objc func textCancelClicked() {
        overlayView?.cancelTextEditing()
    }

    @objc func textConfirmClicked() {
        overlayView?.commitTextFieldIfNeeded()
    }
}

// MARK: - Static Properties

extension ToolOptionsRowView {
    static var savedOutlineColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "annotationOutlineColor"),
           let c = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) { return c }
        return .white
    }
}

// Helper for toggle closures
class ToggleHandler: NSObject {
    let action: (Bool) -> Void
    init(action: @escaping (Bool) -> Void) { self.action = action }
    @objc func toggled(_ sender: NSButton) { action(sender.state == .on) }
}
