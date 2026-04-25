import Cocoa

private var overlayControlActionKey: UInt8 = 0

enum OverlayPopoverPalette {
    static let label = ToolbarLayout.iconColor.withAlphaComponent(0.78)
    static let value = ToolbarLayout.iconColor.withAlphaComponent(0.62)
    static let controlFont = NSFont.systemFont(ofSize: 11)
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
}

let recordingFPSOptions = [15, 24, 30, 60, 120]

func normalizedRecordingFPS(_ fps: Int?, fallback: Int = 30) -> Int {
    guard let fps, recordingFPSOptions.contains(fps) else { return fallback }
    return fps
}

func recordingFPSTitle(_ fps: Int) -> String {
    switch fps {
    case 15: return L("15 fps")
    case 24: return L("24 fps")
    case 30: return L("30 fps")
    case 60: return L("60 fps")
    case 120: return L("120 fps")
    default: return "\(fps) fps"
    }
}

typealias OverlayRedactionAction = (
    _ screenshot: NSImage,
    _ selectionRect: NSRect,
    _ captureDrawRect: NSRect,
    _ redactTool: AnnotationTool,
    _ color: NSColor,
    _ sourceImage: NSImage?,
    _ sourceImageBounds: NSRect,
    _ completion: @escaping ([Annotation]) -> Void
) -> Void

final class OverlayControlAction: NSObject {
    private let handler: (NSControl) -> Void

    init(_ handler: @escaping (NSControl) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func invoke(_ sender: NSControl) {
        handler(sender)
    }
}

final class OverlayPopoverFormView: NSView {
    private let contentWidth: CGFloat
    private let labelWidth: CGFloat
    private let controlX: CGFloat
    private let defaultControlWidth: CGFloat
    private var y: CGFloat = 8

    init(width: CGFloat, labelWidth: CGFloat = 76, controlX: CGFloat = 88, controlWidth: CGFloat = 140) {
        self.contentWidth = width
        self.labelWidth = labelWidth
        self.controlX = controlX
        self.defaultControlWidth = controlWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
    }

    required init?(coder: NSCoder) { fatalError() }

    var preferredSize: NSSize { frame.size }

    func addRow(_ title: String, control: NSView, width: CGFloat? = nil) {
        let label = NSTextField(labelWithString: title)
        label.font = OverlayPopoverPalette.labelFont
        label.textColor = OverlayPopoverPalette.label
        label.frame = NSRect(x: 10, y: y + 2, width: labelWidth, height: 18)
        addSubview(label)

        control.frame = NSRect(x: controlX, y: y, width: width ?? defaultControlWidth, height: 22)
        addSubview(control)
        y += 28
    }

    func addSeparator() {
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 10, y: y + 2, width: contentWidth - 20, height: 1)
        addSubview(separator)
        y += 10
    }

    func finish(bottom: CGFloat = 4) {
        frame.size.height = y + bottom
    }
}

extension NSControl {
    func bindOverlayAction(_ handler: @escaping (NSControl) -> Void) {
        let action = OverlayControlAction(handler)
        target = action
        self.action = #selector(OverlayControlAction.invoke(_:))
        objc_setAssociatedObject(self, &overlayControlActionKey, action, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

func makeOverlayPopup(_ titles: [String], selected: Int, onChange: @escaping (Int) -> Void) -> NSPopUpButton {
    let control = NSPopUpButton()
    control.controlSize = .small
    control.font = OverlayPopoverPalette.controlFont
    control.addItems(withTitles: titles)
    if !titles.isEmpty {
        control.selectItem(at: max(0, min(selected, titles.count - 1)))
    }
    control.bindOverlayAction { onChange(($0 as? NSPopUpButton)?.indexOfSelectedItem ?? 0) }
    return control
}

func makeOverlaySegmented(_ labels: [String], selected: Int, onChange: @escaping (Int) -> Void) -> NSSegmentedControl {
    let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
    control.selectedSegment = selected
    control.bindOverlayAction { onChange(($0 as? NSSegmentedControl)?.selectedSegment ?? selected) }
    return control
}

func makeOverlayCheckbox(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> NSButton {
    let control = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    control.state = isOn ? .on : .off
    control.font = NSFont.systemFont(ofSize: 12, weight: .medium)

    // Use attributed title to apply custom foreground color
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: ToolbarLayout.iconColor
    ]
    control.attributedTitle = NSAttributedString(string: title, attributes: attrs)

    control.bindOverlayAction { onChange(($0 as? NSButton)?.state == .on) }
    return control
}

extension OverlayView {
    struct OverlayRedactionContext {
        let screenshot: NSImage
        let selectionRect: NSRect
        let captureDrawRect: NSRect
        let redactTool: AnnotationTool
        let color: NSColor
        let sourceImage: NSImage?
    }

    var currentRedactionContext: OverlayRedactionContext? {
        guard state == .selected, let screenshotImage else { return nil }
        let redactTool: AnnotationTool = currentTool == .pixelate ? .pixelate : .rectangle
        return .init(
            screenshot: screenshotImage,
            selectionRect: selectionRect,
            captureDrawRect: captureDrawRect,
            redactTool: redactTool,
            color: currentColor,
            sourceImage: currentTool == .pixelate ? screenshotImage : nil
        )
    }

    var effectiveRecordingFPS: Int {
        if let sessionRecordingFPS { return sessionRecordingFPS }
        return normalizedRecordingFPS(UserDefaults.standard.integer(forKey: "recordingFPS"))
    }

    var effectiveRecordingDelay: Int {
        sessionRecordingDelay ?? UserDefaults.standard.integer(forKey: "captureDelaySeconds")
    }

    var effectiveRecordingControlsMode: RecordingControlsMode {
        RecordingControlsMode.resolved(raw: sessionRecordingControlsMode) ?? .current
    }

    func presentOverlayPopover(
        _ content: NSView,
        size: NSSize,
        type: PopoverHelper.PopoverType,
        edge: NSRectEdge,
        anchorView: NSView? = nil,
        anchorRect: NSRect = .zero,
        fallbackPoint: NSPoint
    ) {
        if let anchorView {
            PopoverHelper.show(content, size: size, relativeTo: anchorView.bounds, of: anchorView, preferredEdge: edge, type: type)
        } else {
            PopoverHelper.showAtPoint(content, size: size, at: fallbackPoint, in: self, preferredEdge: edge, type: type)
        }
    }

    func appendAnnotations(_ annotations: [Annotation]) {
        guard !annotations.isEmpty else { return }
        self.annotations.append(contentsOf: annotations)
        undoStack.append(contentsOf: annotations.map { .added($0) })
        redoStack.removeAll()
        cachedCompositedImage = nil
        needsDisplay = true
    }

    func replaceAnnotations(of tool: AnnotationTool, with annotations: [Annotation]) {
        self.annotations.removeAll { $0.tool == tool }
        self.annotations.append(contentsOf: annotations)
        if !annotations.isEmpty {
            undoStack.append(contentsOf: annotations.map { .added($0) })
        }
        redoStack.removeAll()
        cachedCompositedImage = nil
        needsDisplay = true
    }

    func applyEffects(_ config: ImageEffectsConfig) {
        effectsPreset = config.preset
        effectsBrightness = config.brightness
        effectsContrast = config.contrast
        effectsSaturation = config.saturation
        effectsSharpness = config.sharpness
        UserDefaults.standard.set(config.preset.rawValue, forKey: "effectsPreset")
        UserDefaults.standard.set(Double(config.brightness), forKey: "effectsBrightness")
        UserDefaults.standard.set(Double(config.contrast), forKey: "effectsContrast")
        UserDefaults.standard.set(Double(config.saturation), forKey: "effectsSaturation")
        UserDefaults.standard.set(Double(config.sharpness), forKey: "effectsSharpness")
        cachedCompositedImage = nil
        cachedEffectsScreenshot = nil
        rebuildToolbarLayout()
        needsDisplay = true
    }

    func refreshBeautifyRendering() {
        cachedCompositedImage = nil
        // In editor mode, skip frame/bounds updates for parameter tweaks to avoid jitter.
        // Frame/bounds are only updated for structural changes (enable/disable, mode change, style change).
        rebuildToolbarLayout()
        needsDisplay = true
    }

    func applyBeautifyStyleSelection(_ index: Int) {
        beautifyStyleIndex = index
        UserDefaults.standard.set(index, forKey: "beautifyStyleIndex")
        if index >= 0 {
            customBeautifyBackground = nil
        } else {
            loadCustomBeautifyBackground()
        }
        // Structural change: update frame/bounds
        if isEditorMode {
            updateEditorFrameForBeautify()
        } else {
            refreshBeautifyRendering()
        }
    }

    func applyCustomBeautifyBackground(_ image: NSImage) {
        _ = BeautifyBackgroundStore.saveImage(image)
        customBeautifyBackground = image
        prepareBeautifyBackgroundCache()
        beautifyStyleIndex = -1
        UserDefaults.standard.set(-1, forKey: "beautifyStyleIndex")
        // Structural change: update frame/bounds
        if isEditorMode {
            updateEditorFrameForBeautify()
        } else {
            refreshBeautifyRendering()
        }
    }
}
