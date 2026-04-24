import Cocoa
import UniformTypeIdentifiers

extension OverlayView {

    func showBeautifyPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = BeautifyPopoverView(overlayView: self)
        let size = picker.preferredSize
        if let anchor = anchorView {
            PopoverHelper.show(
                picker, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX, type: .beautify)
        } else {
            PopoverHelper.showAtPoint(
                picker, size: size,
                at: NSPoint(x: anchorRect.midX, y: anchorRect.midY),
                in: self, preferredEdge: .minX, type: .beautify)
        }
    }

    func showUploadConfirmPopover(anchorRect: NSRect, anchorView: NSView? = nil) {

        let current = UserDefaults.standard.bool(forKey: "uploadConfirmEnabled")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 32))

        let toggle = NSButton(checkboxWithTitle: L("Confirm before upload"), target: nil, action: nil)
        toggle.state = current ? .on : .off
        toggle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        toggle.sizeToFit()
        toggle.frame.origin = NSPoint(x: 10, y: (32 - toggle.frame.height) / 2)
        toggle.target = toggle  // self-target via associated handler
        container.addSubview(toggle)

        class ToggleHandler: NSObject {
            @objc func toggled(_ sender: NSButton) {
                UserDefaults.standard.set(sender.state == .on, forKey: "uploadConfirmEnabled")
            }
        }
        let handler = ToggleHandler()
        toggle.target = handler
        toggle.action = #selector(ToggleHandler.toggled(_:))
        objc_setAssociatedObject(toggle, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

        let size = NSSize(width: max(180, toggle.frame.width + 20), height: 32)
        container.frame.size = size

        if let anchor = anchorView {
            PopoverHelper.show(
                container, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY, type: .uploadConfirm)
        } else {
            PopoverHelper.showAtPoint(
                container, size: size, at: NSPoint(x: anchorRect.maxX + 4, y: anchorRect.midY),
                in: self, preferredEdge: .maxX, type: .uploadConfirm)
        }
    }

    func showRedactTypePopover(anchorRect: NSRect, anchorView: NSView? = nil) {
        let types = AutoRedactor.redactTypeNames
        let picker = ListPickerView()
        picker.items = types.map { item in
            .init(
                title: item.label,
                isSelected: UserDefaults.standard.object(forKey: item.key) as? Bool ?? true)
        }
        picker.onSelect = { [weak self] idx in
            let key = types[idx].key
            let current = UserDefaults.standard.object(forKey: key) as? Bool ?? true
            UserDefaults.standard.set(!current, forKey: key)
            picker.items = types.map { item in
                .init(
                    title: item.label,
                    isSelected: UserDefaults.standard.object(forKey: item.key) as? Bool ?? true)
            }
            self?.needsDisplay = true
        }
        let size = picker.preferredSize
        if let anchor = anchorView {
            PopoverHelper.show(
                picker, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY, type: .redactType)
        } else {
            PopoverHelper.showAtPoint(
                picker, size: size, at: NSPoint(x: anchorRect.maxX + 4, y: anchorRect.midY),
                in: self, preferredEdge: .maxX, type: .redactType)
        }
    }

    func showTranslatePopover(anchorRect: NSRect, anchorView: NSView? = nil) {
        let languages = TranslationService.availableLanguages
        let currentCode = TranslationService.targetLanguage

        let showPopover: ([String: Bool]?) -> Void = { [weak self] appleAvailability in
            guard let self = self else { return }
            // When Apple Translation is active, only show installed languages
            let filteredLanguages: [(code: String, name: String)]
            if let avail = appleAvailability {
                filteredLanguages = languages.filter { avail[$0.code] == true }
            } else {
                filteredLanguages = languages
            }
            let picker = ListPickerView()
            let pickerW: CGFloat = 220
            picker.frame.size.width = pickerW
            picker.items = filteredLanguages.map { lang in
                return .init(title: lang.name, isSelected: lang.code == currentCode,
                             isEnabled: true, subtitle: nil)
            }
            picker.onSelect = { [weak self] idx in
                let newCode = filteredLanguages[idx].code
                TranslationService.targetLanguage = newCode
                PopoverHelper.dismiss()
                if let self = self, self.translateEnabled {
                    self.performTranslate(targetLang: newCode)
                }
                self?.needsDisplay = true
            }

            let contentH = picker.frame.height
            let maxH: CGFloat = 350
            let popoverSize = NSSize(width: pickerW, height: min(maxH, contentH))

            let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: popoverSize))
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = false
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.documentView = picker

            if let anchor = anchorView {
                PopoverHelper.show(
                    scrollView, size: popoverSize, relativeTo: anchor.bounds, of: anchor,
                    preferredEdge: .maxY, type: .translate)
            } else {
                PopoverHelper.showAtPoint(
                    scrollView, size: popoverSize,
                    at: NSPoint(x: anchorRect.maxX + 4, y: anchorRect.midY),
                    in: self, preferredEdge: .maxX, type: .translate)
            }

            DispatchQueue.main.async {
                picker.scrollToSelected()
            }
        }

        showPopover(nil)
    }

    func showBeautifyGradientPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = GradientPickerView(selectedIndex: beautifyStyleIndex)
        picker.onSelect = { [weak self] idx in
            guard let self = self else { return }
            self.beautifyStyleIndex = idx
            UserDefaults.standard.set(idx, forKey: "beautifyStyleIndex")
            if idx >= 0 {
                // Gradient selected — clear custom background
                self.customBeautifyBackground = nil
            } else {
                // Custom image selected — load from storage
                self.loadCustomBeautifyBackground()
            }
            self.cachedCompositedImage = nil
            self.needsDisplay = true
            self.updateBeautifySwatch(styleIndex: idx)
            // Rebuild options row so blur slider appears/disappears
            self.rebuildToolbarLayout()
        }
        picker.onCustomImage = { [weak self] in
            PopoverHelper.dismiss()
            self?.pickCustomBeautifyBackground()
        }
        picker.onRemoveCustomImage = { [weak self] in
            guard let self = self else { return }
            self.removeCustomBeautifyBackgroundSelection()
            PopoverHelper.dismiss()
        }
        if let anchor = anchorView {
            PopoverHelper.show(
                picker, size: picker.preferredSize, relativeTo: anchor.bounds, of: anchor,
                preferredEdge: .minY, type: .beautifyGradient)
        } else {
            PopoverHelper.showAtPoint(
                picker, size: picker.preferredSize,
                at: NSPoint(x: anchorRect.midX, y: anchorRect.midY),
                in: self, preferredEdge: .minY, type: .beautifyGradient)
        }
    }

    func pickCustomBeautifyBackground() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        // Lower overlay window level temporarily so the open panel is interactive
        let savedLevel = window?.level
        window?.level = .normal
        panel.beginSheetModal(for: window!) { [weak self] response in
            self?.window?.level = savedLevel ?? .normal
            guard let self = self, response == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url) else { return }
            // Store image data (PNG) in UserDefaults for persistence
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                UserDefaults.standard.set(pngData, forKey: "beautifyCustomBgImageData")
            }
            self.customBeautifyBackground = image
            self.prepareBeautifyBackgroundCache()
            self.beautifyStyleIndex = -1
            UserDefaults.standard.set(-1, forKey: "beautifyStyleIndex")
            self.cachedCompositedImage = nil
            self.needsDisplay = true
            self.updateBeautifySwatch(styleIndex: -1)
            self.rebuildToolbarLayout()
        }
    }

    func loadCustomBeautifyBackground() {
        guard let data = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData"),
              let image = NSImage(data: data) else { return }
        customBeautifyBackground = image
        prepareBeautifyBackgroundCache()
    }

    func removeCustomBeautifyBackgroundSelection() {
        let fallbackIndex = max(0, beautifyStyles.count - 1)
        UserDefaults.standard.removeObject(forKey: "beautifyCustomBgImageData")
        customBeautifyBackground = nil
        beautifyStyleIndex = fallbackIndex
        UserDefaults.standard.set(fallbackIndex, forKey: "beautifyStyleIndex")
        cachedCompositedImage = nil
        needsDisplay = true
        updateBeautifySwatch(styleIndex: fallbackIndex)
        rebuildToolbarLayout()
    }

    func showEmojiPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = EmojiPickerView()
        picker.onSelectEmoji = { [weak self] emoji in
            self?.currentStampImage = StampEmojis.renderEmoji(emoji)
            self?.currentStampEmoji = emoji
            self?.needsDisplay = true
        }
        if let anchor = anchorView {
            PopoverHelper.show(
                picker, size: picker.preferredSize, relativeTo: anchor.bounds, of: anchor,
                preferredEdge: .maxY, type: .emoji)
        } else {
            PopoverHelper.showAtPoint(
                picker, size: picker.preferredSize,
                at: NSPoint(x: anchorRect.midX, y: anchorRect.midY),
                in: self, preferredEdge: .maxY, type: .emoji)
        }
    }

    // MARK: - Recording Settings Popover

    func showRecordingSettingsPopover(anchorView: NSView?) {

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 72))
        var y: CGFloat = 8
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let labelColor = NSColor.secondaryLabelColor

        func addRow(label: String, control: NSView, controlWidth: CGFloat = 140) {
            let lbl = NSTextField(labelWithString: label)
            lbl.font = labelFont
            lbl.textColor = labelColor
            lbl.frame = NSRect(x: 10, y: y + 2, width: 76, height: 18)
            container.addSubview(lbl)
            control.frame = NSRect(x: 88, y: y, width: controlWidth, height: 22)
            container.addSubview(control)
            y += 28
        }

        // Read current effective values (session override > UserDefaults default)
        let effectiveFPS =
            sessionRecordingFPS
            ?? (UserDefaults.standard.integer(forKey: "recordingFPS") > 0
                ? UserDefaults.standard.integer(forKey: "recordingFPS") : 30)
        // FPS popup
        let fpsPopup = NSPopUpButton()
        fpsPopup.controlSize = .small
        fpsPopup.font = NSFont.systemFont(ofSize: 11)
        fpsPopup.addItems(withTitles: ["15", "30", "60", "120"])
        if effectiveFPS <= 15 {
            fpsPopup.selectItem(at: 0)
        } else if effectiveFPS <= 30 {
            fpsPopup.selectItem(at: 1)
        } else if effectiveFPS <= 60 {
            fpsPopup.selectItem(at: 2)
        } else {
            fpsPopup.selectItem(at: 3)
        }

        // Handlers write to session overrides, not UserDefaults
        class FPSHandler: NSObject {
            weak var overlayView: OverlayView?
            init(overlayView: OverlayView?) {
                self.overlayView = overlayView
                super.init()
            }
            @objc func changed(_ sender: NSPopUpButton) {
                if let title = sender.selectedItem?.title, let fps = Int(title) {
                    overlayView?.sessionRecordingFPS = fps
                }
            }
        }

        let fpsHandler = FPSHandler(overlayView: self)
        fpsPopup.target = fpsHandler
        fpsPopup.action = #selector(FPSHandler.changed(_:))
        objc_setAssociatedObject(fpsPopup, "handler", fpsHandler, .OBJC_ASSOCIATION_RETAIN)

        // Delay popup
        let delayPopup = NSPopUpButton()
        delayPopup.controlSize = .small
        delayPopup.font = NSFont.systemFont(ofSize: 11)
        let delayOptions = [0, 3, 5, 10, 30]
        for s in delayOptions {
            delayPopup.addItem(withTitle: s == 0 ? L("None") : String(format: L("%d seconds"), s))
        }
        let effectiveDelay = sessionRecordingDelay ?? UserDefaults.standard.integer(forKey: "captureDelaySeconds")
        if let idx = delayOptions.firstIndex(of: effectiveDelay) {
            delayPopup.selectItem(at: idx)
        }

        class DelayHandler: NSObject {
            weak var overlayView: OverlayView?
            let options: [Int]
            init(overlayView: OverlayView?, options: [Int]) {
                self.overlayView = overlayView
                self.options = options
                super.init()
            }
            @objc func changed(_ sender: NSPopUpButton) {
                overlayView?.sessionRecordingDelay = options[sender.indexOfSelectedItem]
            }
        }
        let delayHandler = DelayHandler(overlayView: self, options: delayOptions)
        delayPopup.target = delayHandler
        delayPopup.action = #selector(DelayHandler.changed(_:))
        objc_setAssociatedObject(delayPopup, "handler", delayHandler, .OBJC_ASSOCIATION_RETAIN)

        // Recording controls popup
        let effectiveControlsMode =
            RecordingControlsMode.resolved(raw: sessionRecordingControlsMode) ?? .current
        let controlsPopup = NSPopUpButton()
        controlsPopup.addItems(withTitles: [L("Floating HUD"), L("Menu Bar")])
        controlsPopup.controlSize = .small
        controlsPopup.font = NSFont.systemFont(ofSize: 11)
        controlsPopup.selectItem(at: effectiveControlsMode == .menuBar ? 1 : 0)

        class ControlsModeHandler: NSObject {
            weak var overlayView: OverlayView?
            init(overlayView: OverlayView?) { self.overlayView = overlayView; super.init() }
            @objc func changed(_ sender: NSPopUpButton) {
                let values = [
                    RecordingControlsMode.floatingHUD.rawValue,
                    RecordingControlsMode.menuBar.rawValue,
                ]
                overlayView?.sessionRecordingControlsMode = values[sender.indexOfSelectedItem]
            }
        }
        let controlsModeHandler = ControlsModeHandler(overlayView: self)
        controlsPopup.target = controlsModeHandler
        controlsPopup.action = #selector(ControlsModeHandler.changed(_:))
        objc_setAssociatedObject(controlsPopup, "handler", controlsModeHandler, .OBJC_ASSOCIATION_RETAIN)

        addRow(label: L("FPS:"), control: fpsPopup)
        addRow(label: L("Delay:"), control: delayPopup)
        addRow(label: L("Controls:"), control: controlsPopup)

        // Webcam settings (only when webcam is enabled)
        if UserDefaults.standard.bool(forKey: "recordWebcam") {
            // Separator
            let sep = NSBox()
            sep.boxType = .separator
            sep.frame = NSRect(x: 10, y: y + 2, width: 220, height: 1)
            container.addSubview(sep)
            y += 10

            // Position
            let posSeg = NSSegmentedControl(labels: ["↙", "↘", "↖", "↗"], trackingMode: .selectOne, target: nil, action: nil)
            let currentPos = UserDefaults.standard.string(forKey: "webcamPosition") ?? "bottomRight"
            switch currentPos {
            case "bottomLeft": posSeg.selectedSegment = 0
            case "bottomRight": posSeg.selectedSegment = 1
            case "topLeft": posSeg.selectedSegment = 2
            case "topRight": posSeg.selectedSegment = 3
            default: posSeg.selectedSegment = 1
            }

            class PosHandler: NSObject {
                weak var overlayView: OverlayView?
                init(overlayView: OverlayView?) { self.overlayView = overlayView; super.init() }
                @objc func changed(_ sender: NSSegmentedControl) {
                    let values = ["bottomLeft", "bottomRight", "topLeft", "topRight"]
                    UserDefaults.standard.set(values[sender.selectedSegment], forKey: "webcamPosition")
                    overlayView?.updateWebcamSetupPreview()
                }
            }
            let posHandler = PosHandler(overlayView: self)
            posSeg.target = posHandler
            posSeg.action = #selector(PosHandler.changed(_:))
            objc_setAssociatedObject(posSeg, "handler", posHandler, .OBJC_ASSOCIATION_RETAIN)

            // Size
            let sizeSeg = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne, target: nil, action: nil)
            let currentSize = UserDefaults.standard.string(forKey: "webcamSize") ?? "medium"
            switch currentSize {
            case "small": sizeSeg.selectedSegment = 0
            case "medium": sizeSeg.selectedSegment = 1
            case "large": sizeSeg.selectedSegment = 2
            default: sizeSeg.selectedSegment = 1
            }

            class SizeHandler: NSObject {
                weak var overlayView: OverlayView?
                init(overlayView: OverlayView?) { self.overlayView = overlayView; super.init() }
                @objc func changed(_ sender: NSSegmentedControl) {
                    let values = ["small", "medium", "large"]
                    UserDefaults.standard.set(values[sender.selectedSegment], forKey: "webcamSize")
                    overlayView?.updateWebcamSetupPreview()
                }
            }
            let sizeHandler = SizeHandler(overlayView: self)
            sizeSeg.target = sizeHandler
            sizeSeg.action = #selector(SizeHandler.changed(_:))
            objc_setAssociatedObject(sizeSeg, "handler", sizeHandler, .OBJC_ASSOCIATION_RETAIN)

            // Shape
            let shapeSeg = NSSegmentedControl(labels: ["●", "▢"], trackingMode: .selectOne, target: nil, action: nil)
            let currentShape = UserDefaults.standard.string(forKey: "webcamShape") ?? "circle"
            shapeSeg.selectedSegment = currentShape == "roundedRect" ? 1 : 0

            class ShapeHandler: NSObject {
                weak var overlayView: OverlayView?
                init(overlayView: OverlayView?) { self.overlayView = overlayView; super.init() }
                @objc func changed(_ sender: NSSegmentedControl) {
                    let values = ["circle", "roundedRect"]
                    UserDefaults.standard.set(values[sender.selectedSegment], forKey: "webcamShape")
                    overlayView?.updateWebcamSetupPreview()
                }
            }
            let shapeHandler = ShapeHandler(overlayView: self)
            shapeSeg.target = shapeHandler
            shapeSeg.action = #selector(ShapeHandler.changed(_:))
            objc_setAssociatedObject(shapeSeg, "handler", shapeHandler, .OBJC_ASSOCIATION_RETAIN)

            addRow(label: L("Cam pos:"), control: posSeg)
            addRow(label: L("Cam size:"), control: sizeSeg)
            addRow(label: L("Cam shape:"), control: shapeSeg)
        }

        let size = NSSize(width: 240, height: y + 4)
        container.frame.size = size

        if let anchor = anchorView {
            PopoverHelper.show(
                container, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY, type: .recordingSettings)
        } else {
            PopoverHelper.showAtPoint(
                container, size: size,
                at: NSPoint(x: bounds.midX, y: bounds.midY),
                in: self, preferredEdge: .maxY, type: .recordingSettings)
        }
    }

    // MARK: - Auto-redact & Translate actions

    func performAutoRedact() {
        guard state == .selected, let screenshot = screenshotImage else { return }
        let tool: AnnotationTool = currentTool == .pixelate ? .pixelate : .rectangle
        let sourceImg = tool == .pixelate ? screenshotImage : nil
        AutoRedactor.redactPII(
            screenshot: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect,
            redactTool: tool, color: currentColor, sourceImage: sourceImg,
            sourceImageBounds: captureDrawRect
        ) { [weak self] anns in
            guard let self = self, !anns.isEmpty else { return }
            self.annotations.append(contentsOf: anns)
            self.undoStack.append(contentsOf: anns.map { .added($0) })
            self.redoStack.removeAll()
            self.cachedCompositedImage = nil
            self.needsDisplay = true
        }
    }

    func performRedactAllText() {
        guard state == .selected, let screenshot = screenshotImage else { return }
        let tool: AnnotationTool = currentTool == .pixelate ? .pixelate : .rectangle
        let sourceImg = tool == .pixelate ? screenshotImage : nil
        AutoRedactor.redactAllText(
            screenshot: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect,
            redactTool: tool, color: currentColor, sourceImage: sourceImg,
            sourceImageBounds: captureDrawRect
        ) { [weak self] anns in
            guard let self = self, !anns.isEmpty else { return }
            self.annotations.append(contentsOf: anns)
            self.undoStack.append(contentsOf: anns.map { .added($0) })
            self.redoStack.removeAll()
            self.cachedCompositedImage = nil
            self.needsDisplay = true
        }
    }

    func performRedactFaces() {
        guard state == .selected, let screenshot = screenshotImage else { return }
        let tool: AnnotationTool = currentTool == .pixelate ? .pixelate : .rectangle
        let sourceImg = tool == .pixelate ? screenshotImage : nil
        AutoRedactor.redactFaces(
            screenshot: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect,
            redactTool: tool, color: currentColor, sourceImage: sourceImg,
            sourceImageBounds: captureDrawRect
        ) { [weak self] anns in
            guard let self = self, !anns.isEmpty else { return }
            self.annotations.append(contentsOf: anns)
            self.undoStack.append(contentsOf: anns.map { .added($0) })
            self.redoStack.removeAll()
            self.cachedCompositedImage = nil
            self.needsDisplay = true
        }
    }

    func performRedactPeople() {
        guard state == .selected, let screenshot = screenshotImage else { return }
        let tool: AnnotationTool = currentTool == .pixelate ? .pixelate : .rectangle
        let sourceImg = tool == .pixelate ? screenshotImage : nil
        AutoRedactor.redactPeople(
            screenshot: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect,
            redactTool: tool, color: currentColor, sourceImage: sourceImg,
            sourceImageBounds: captureDrawRect
        ) { [weak self] anns in
            guard let self = self, !anns.isEmpty else { return }
            self.annotations.append(contentsOf: anns)
            self.undoStack.append(contentsOf: anns.map { .added($0) })
            self.redoStack.removeAll()
            self.cachedCompositedImage = nil
            self.needsDisplay = true
        }
    }

    func showEffectsPopover(anchorView: NSView? = nil, anchorRect: NSRect = .zero) {
        let picker = EffectsPickerView(config: effectsConfig)
        picker.onConfigChanged = { [weak self] config in
            guard let self = self else { return }
            self.effectsPreset = config.preset
            self.effectsBrightness = config.brightness
            self.effectsContrast = config.contrast
            self.effectsSaturation = config.saturation
            self.effectsSharpness = config.sharpness
            UserDefaults.standard.set(config.preset.rawValue, forKey: "effectsPreset")
            UserDefaults.standard.set(Double(config.brightness), forKey: "effectsBrightness")
            UserDefaults.standard.set(Double(config.contrast), forKey: "effectsContrast")
            UserDefaults.standard.set(Double(config.saturation), forKey: "effectsSaturation")
            UserDefaults.standard.set(Double(config.sharpness), forKey: "effectsSharpness")
            self.cachedCompositedImage = nil
            self.cachedEffectsScreenshot = nil
            self.rebuildToolbarLayout()
            self.needsDisplay = true
        }
        let size = picker.preferredSize
        if let anchor = anchorView {
            PopoverHelper.show(
                picker, size: size, relativeTo: anchor.bounds, of: anchor, preferredEdge: .minX, type: .effects)
        } else {
            PopoverHelper.showAtPoint(
                picker, size: size,
                at: NSPoint(x: anchorRect.midX, y: anchorRect.midY),
                in: self, preferredEdge: .minX, type: .effects)
        }
    }

    func performTranslate(targetLang: String) {
        guard state == .selected, let screenshot = screenshotImage else { return }
        annotations.removeAll { $0.tool == .translateOverlay }
        isTranslating = true
        needsDisplay = true

        TranslateOverlay.translate(
            screenshot: screenshot, selectionRect: selectionRect, captureDrawRect: captureDrawRect,
            targetLang: targetLang,
            onError: { [weak self] msg in
                self?.isTranslating = false
                self?.showOverlayError(msg)
                self?.needsDisplay = true
            },
            completion: { [weak self] anns in
                guard let self = self else { return }
                self.isTranslating = false
                self.annotations.removeAll { $0.tool == .translateOverlay }
                self.annotations.append(contentsOf: anns)
                self.undoStack.append(contentsOf: anns.map { .added($0) })
                self.redoStack.removeAll()
                self.needsDisplay = true
            }
        )
    }
}

private final class BeautifyPopoverView: NSView {
    weak var overlayView: OverlayView?
    private let contentWidth: CGFloat = 280
    private var currentY: CGFloat = 0

    override var isFlipped: Bool { true }
    var preferredSize: NSSize { frame.size }

    init(overlayView: OverlayView) {
        self.overlayView = overlayView
        super.init(frame: .zero)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let ov = overlayView else {
            frame.size = NSSize(width: contentWidth, height: 120)
            return
        }

        subviews.forEach { $0.removeFromSuperview() }
        currentY = 12

        addSectionTitle(L("Wrap"), isOn: ov.beautifyEnabled, action: #selector(toggleChanged(_:)))

        if !ov.selectionIsWindowSnap {
            addSegmentedControl(
                labels: [L("Window"), L("Rounded")],
                selectedIndex: ov.beautifyMode == .window ? 0 : 1,
                action: #selector(modeChanged(_:)))
        }

        addSliderRow(
            title: L("Padding"),
            value: ov.beautifyPadding,
            min: 16,
            max: 96,
            tag: 900,
            action: #selector(sliderChanged(_:)))

        if !ov.selectionIsWindowSnap {
            addSliderRow(
                title: L("Radius"),
                value: ov.beautifyCornerRadius,
                min: 0,
                max: 100,
                tag: 901,
                action: #selector(sliderChanged(_:)))
        }

        addSliderRow(
            title: L("Shadow"),
            value: ov.beautifyShadowRadius,
            min: 0,
            max: 100,
            tag: 902,
            action: #selector(sliderChanged(_:)))

        if ov.beautifyStyleIndex == -1 {
            addSliderRow(
                title: L("Blur"),
                value: ov.beautifyBackgroundBlur,
                min: 0,
                max: 50,
                tag: 903,
                action: #selector(sliderChanged(_:)))
        }

        addGradientPicker()

        frame.size = NSSize(width: contentWidth, height: currentY + 12)
    }

    private func addSectionTitle(_ text: String, isOn: Bool = false, action: Selector? = nil) {
        // 左侧标题
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = ToolbarLayout.iconColor
        label.frame = NSRect(x: 14, y: currentY + 2, width: 200, height: 18)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        addSubview(label)

        // 右侧复选框
        if let action = action {
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: action)
            toggle.state = isOn ? .on : .off
            toggle.frame = NSRect(x: contentWidth - 28, y: currentY + 2, width: 24, height: 18)
            addSubview(toggle)
        }

        currentY += 28
    }

    private func addSegmentedControl(labels: [String], selectedIndex: Int, action: Selector) {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: action)
        control.selectedSegment = selectedIndex
        control.frame = NSRect(x: 14, y: currentY, width: contentWidth - 28, height: 24)
        addSubview(control)
        currentY += 34
    }

    private func addSliderRow(title: String, value: CGFloat, min: CGFloat, max: CGFloat, tag: Int, action: Selector) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.78)
        titleLabel.frame = NSRect(x: 14, y: currentY + 2, width: 60, height: 16)
        addSubview(titleLabel)

        let slider = NSSlider(value: Double(value), minValue: Double(min), maxValue: Double(max), target: self, action: action)
        slider.tag = tag
        slider.frame = NSRect(x: 78, y: currentY, width: 140, height: 20)
        slider.isContinuous = true
        addSubview(slider)

        let valueLabel = NSTextField(labelWithString: "\(Int(value))")
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.textColor = ToolbarLayout.iconColor.withAlphaComponent(0.62)
        valueLabel.tag = tag + 100
        valueLabel.frame = NSRect(x: 224, y: currentY + 2, width: 40, height: 16)
        addSubview(valueLabel)

        currentY += 28
    }

    private func addGradientPicker() {
        guard let ov = overlayView else { return }

        // 创建8列的渐变选择器
        let picker = InlineGradientPickerView(selectedIndex: ov.beautifyStyleIndex)
        picker.onSelect = { [unowned self] idx in
            guard let ov = self.overlayView else { return }
            ov.beautifyStyleIndex = idx
            UserDefaults.standard.set(idx, forKey: "beautifyStyleIndex")
            if idx >= 0 {
                ov.customBeautifyBackground = nil
            } else {
                ov.loadCustomBeautifyBackground()
            }
            ov.cachedCompositedImage = nil
            ov.needsDisplay = true
            // 重建UI以显示/隐藏模糊滑块
            self.buildUI()
        }
        picker.onCustomImage = { [unowned self] in
            self.pickCustomImage()
        }
        picker.onRemoveCustomImage = { [unowned self] in
            guard let ov = self.overlayView else { return }
            ov.removeCustomBeautifyBackgroundSelection()
            self.buildUI()
        }
        picker.frame.origin = NSPoint(x: 14, y: currentY)
        addSubview(picker)
        currentY += picker.frame.height + 12
    }

    private func pickCustomImage() {
        guard let ov = overlayView else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        let savedLevel = ov.window?.level
        ov.window?.level = .normal
        panel.beginSheetModal(for: ov.window!) { [weak self] response in
            ov.window?.level = savedLevel ?? .normal
            guard let self = self, response == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url) else { return }
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                UserDefaults.standard.set(png, forKey: "beautifyCustomBgImageData")
            }
            ov.beautifyStyleIndex = -1
            UserDefaults.standard.set(-1, forKey: "beautifyStyleIndex")
            ov.customBeautifyBackground = image
            ov.cachedCompositedImage = nil
            ov.needsDisplay = true
            self.buildUI()
        }
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        guard let ov = overlayView else { return }
        ov.beautifyEnabled = sender.state == .on
        UserDefaults.standard.set(ov.beautifyEnabled, forKey: "beautifyEnabled")
        ov.cachedCompositedImage = nil
        ov.rebuildToolbarLayout()
        ov.needsDisplay = true
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        guard let ov = overlayView else { return }
        ov.beautifyMode = sender.selectedSegment == 0 ? .window : .rounded
        UserDefaults.standard.set(ov.beautifyMode.rawValue, forKey: "beautifyMode")
        ov.cachedCompositedImage = nil
        ov.rebuildToolbarLayout()
        ov.needsDisplay = true
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let ov = overlayView else { return }
        let value = CGFloat(sender.floatValue)
        switch sender.tag {
        case 900:
            ov.beautifyPadding = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyPadding")
        case 901:
            ov.beautifyCornerRadius = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyCornerRadius")
        case 902:
            ov.beautifyShadowRadius = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyShadowRadius")
        case 903:
            ov.beautifyBackgroundBlur = value
            UserDefaults.standard.set(sender.doubleValue, forKey: "beautifyBgBlur")
        default:
            break
        }
        if let label = viewWithTag(sender.tag + 100) as? NSTextField {
            label.stringValue = "\(Int(sender.floatValue))"
        }
        ov.cachedCompositedImage = nil
        ov.needsDisplay = true
    }
}

/// 8列的内嵌渐变选择器，用于BeautifyPopoverView内部
private class InlineGradientPickerView: NSView {
    var selectedIndex: Int = 0
    var onSelect: ((Int) -> Void)?
    var onCustomImage: (() -> Void)?
    var onRemoveCustomImage: (() -> Void)?

    private let styles = beautifyStyles
    private let cols = 8  // 改为8列
    private let swSize: CGFloat = 28
    /// 仅上下内边距；水平不设 padding，总宽与 `BeautifyPopoverView` 内分段控件一致（x:14、宽 `contentWidth - 28` = 252），避免相对 280 内容区右缘裁切
    private let paddingV: CGFloat = 8
    private let gap: CGFloat = 4

    private var hasCustomImage: Bool {
        UserDefaults.standard.data(forKey: "beautifyCustomBgImageData") != nil
    }

    init(selectedIndex: Int) {
        self.selectedIndex = selectedIndex
        let hasCustom = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData") != nil
        let total = beautifyStyles.count + (hasCustom ? 1 : 0) + 1
        let rows = (total + 7) / 8  // 8列
        let w = CGFloat(cols) * swSize + CGFloat(cols - 1) * gap
        let h = paddingV * 2 + CGFloat(rows) * swSize + CGFloat(max(0, rows - 1)) * gap
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    private func rectForIndex(_ i: Int) -> NSRect {
        let col = i % cols
        let row = i / cols
        let sx = CGFloat(col) * (swSize + gap)
        let sy = paddingV + CGFloat(row) * (swSize + gap)
        return NSRect(x: sx, y: sy, width: swSize, height: swSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        var idx = 0

        // Draw gradient swatches
        for (i, style) in styles.enumerated() {
            let sr = rectForIndex(idx)
            let path = NSBezierPath(roundedRect: sr, xRadius: 6, yRadius: 6)
            if #available(macOS 15.0, *), let mesh = style.meshDef,
               let img = BeautifyRenderer.renderMeshSwatch(mesh, size: swSize) {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                img.draw(in: sr, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
            } else if let grad = NSGradient(colors: style.stops.map { $0.0 }, atLocations: style.stops.map { $0.1 }, colorSpace: .deviceRGB) {
                grad.draw(in: path, angle: style.angle - 90)
            }
            if i == selectedIndex {
                ToolbarLayout.accentColor.setStroke()
                let ring = NSBezierPath(roundedRect: sr.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
            idx += 1
        }

        // Custom image thumbnail swatch
        if let thumb = customBackgroundThumbnail() {
            let sr = rectForIndex(idx)
            let path = NSBezierPath(roundedRect: sr, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            thumb.draw(in: sr, from: .zero, operation: .sourceOver, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
            if selectedIndex == -1 {
                ToolbarLayout.accentColor.setStroke()
                let ring = NSBezierPath(roundedRect: sr.insetBy(dx: -2, dy: -2), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
            idx += 1
        }

        // "Choose Image" button swatch
        let btnRect = rectForIndex(idx)
        let btnPath = NSBezierPath(roundedRect: btnRect, xRadius: 6, yRadius: 6)
        ToolbarLayout.iconColor.withAlphaComponent(0.15).setFill()
        btnPath.fill()

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let plusIcon = NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            let tinted = plusIcon.copy() as! NSImage
            tinted.lockFocus()
            ToolbarLayout.iconColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let iconSize = tinted.size
            let iconRect = NSRect(
                x: btnRect.midX - iconSize.width / 2,
                y: btnRect.midY - iconSize.height / 2,
                width: iconSize.width, height: iconSize.height)
            tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.7)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let hasCustom = hasCustomImage
        let total = beautifyStyles.count + (hasCustom ? 1 : 0) + 1

        for i in 0..<total {
            if rectForIndex(i).contains(point) {
                let styleCount = beautifyStyles.count
                if i == styleCount && hasCustom {
                    // Clicked custom image swatch
                    selectedIndex = -1
                    onSelect?(-1)
                } else if i == total - 1 {
                    // Clicked "Choose Image" button
                    onCustomImage?()
                } else if i < styleCount {
                    // Clicked gradient swatch
                    selectedIndex = i
                    onSelect?(i)
                }
                needsDisplay = true
                return
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
        if isDeleteKey, selectedIndex == -1, hasCustomImage {
            onRemoveCustomImage?()
            return
        }
        if moveSelection(with: event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }

    @discardableResult
    private func moveSelection(with keyCode: UInt16) -> Bool {
        let selectableCount = styles.count + (hasCustomImage ? 1 : 0)
        guard selectableCount > 0 else { return false }

        let currentSlot = selectedIndex == -1 ? styles.count : max(0, min(selectedIndex, styles.count - 1))
        let targetSlot: Int?

        switch keyCode {
        case 123: // left
            targetSlot = currentSlot > 0 ? currentSlot - 1 : nil
        case 124: // right
            targetSlot = currentSlot < selectableCount - 1 ? currentSlot + 1 : nil
        case 125: // down
            targetSlot = verticalMove(from: currentSlot, offset: 1, count: selectableCount)
        case 126: // up
            targetSlot = verticalMove(from: currentSlot, offset: -1, count: selectableCount)
        default:
            targetSlot = nil
        }

        guard let slot = targetSlot else { return false }
        let newIndex = hasCustomImage && slot == styles.count ? -1 : slot
        selectedIndex = newIndex
        onSelect?(newIndex)
        needsDisplay = true
        return true
    }

    private func verticalMove(from currentSlot: Int, offset: Int, count: Int) -> Int? {
        let currentRow = currentSlot / cols
        let currentCol = currentSlot % cols
        let targetRow = currentRow + offset
        let totalRows = Int(ceil(Double(count) / Double(cols)))
        guard targetRow >= 0, targetRow < totalRows else { return nil }

        let rowStart = targetRow * cols
        let rowCount = min(cols, count - rowStart)
        guard rowCount > 0 else { return nil }
        let targetCol = min(currentCol, rowCount - 1)
        return rowStart + targetCol
    }

    private func customBackgroundThumbnail() -> NSImage? {
        guard let data = UserDefaults.standard.data(forKey: "beautifyCustomBgImageData"),
              let image = NSImage(data: data) else { return nil }
        let size = NSSize(width: swSize, height: swSize)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}
