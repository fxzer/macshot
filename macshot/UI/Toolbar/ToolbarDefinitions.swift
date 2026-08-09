import Cocoa

extension Notification.Name {
    static let toolbarColorsDidChange = Notification.Name("toolbarColorsDidChange")
}

// Toolbar buttons drawn directly in the OverlayView (not a separate window).
// This avoids window-level z-order issues and matches Flameshot's look.

enum ToolbarButtonAction: Equatable {
    case tool(AnnotationTool)
    case color
    case sizeDisplay
    case undo
    case redo
    case copy
    case save
    case pin
    case ocr
    case autoRedact
    case beautify
    case beautifyStyle
    case cancel
    case moveSelection
    case delayCapture
    case upload
    case share
    case removeBackground
    case invertColors
    case loupe
    case translate
    case detach
    case scrollCapture
    case addCapture  // editor only: capture a new region and append to the canvas
    case effects  // image effects (CIFilter adjustments + presets)
}

struct ToolbarButton {
    let action: ToolbarButtonAction
    let sfSymbol: String?
    let label: String?
    let tooltip: String
    var rect: NSRect = .zero
    var isSelected: Bool = false
    var isHovered: Bool = false
    var isPressed: Bool = false
    var tintColor: NSColor = ToolbarLayout.iconColor
    var bgColor: NSColor? = nil  // for color swatches
    var hasContextMenu: Bool = false  // draw small corner triangle to indicate right-click options
    /// When true, a separator is drawn before this button in any toolbar strip.
    var sectionBreakBefore: Bool = false
}

class ToolbarLayout {

    // Accent color follows the current macOS system setting unless the user overrides it.
    static var defaultAccentColor: NSColor { .controlAccentColor }
    static let defaultIconColor = NSColor.white
    static let defaultBgColor = NSColor(white: 0.12, alpha: 1.0)

    // User-customizable colors — read from UserDefaults with defaults matching the original look
    static var accentColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "toolbarAccentColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return defaultAccentColor
    }
    static var iconColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "toolbarIconColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return defaultIconColor
    }
    static var bgColor: NSColor {
        if let data = UserDefaults.standard.data(forKey: "toolbarBgColor"),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return color
        }
        return defaultBgColor
    }
    static var handleColor: NSColor { accentColor }
    static var selectedBg: NSColor { accentColor }
    static let buttonSize: CGFloat = 32
    static let iconPointSize: CGFloat = 14
    static let buttonSpacing: CGFloat = 2
    static let toolbarPadding: CGFloat = 4
    static let cornerRadius: CGFloat = 6
    static var stripThickness: CGFloat { buttonSize + toolbarPadding * 2 }

    /// Save accent color to UserDefaults.
    static func saveAccentColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "toolbarAccentColor")
        }
    }

    /// Remove the user override so accent color follows the current system setting again.
    static func resetAccentColor() {
        UserDefaults.standard.removeObject(forKey: "toolbarAccentColor")
    }

    /// Save icon color to UserDefaults.
    static func saveIconColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "toolbarIconColor")
        }
    }

    /// Appearance matching the toolbar background brightness.
    /// Dark background uses `.darkAqua`; light background uses `.aqua`.
    static var appearance: NSAppearance? {
        let color = bgColor.usingColorSpace(.deviceRGB) ?? bgColor
        var brightness: CGFloat = 0
        color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return NSAppearance(named: brightness > 0.5 ? .aqua : .darkAqua)
    }

    /// Save background color to UserDefaults.
    static func saveBgColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: "toolbarBgColor")
        }
    }

    /// Reset all colors to defaults.
    static func resetColors() {
        resetAccentColor()
        UserDefaults.standard.removeObject(forKey: "toolbarIconColor")
        UserDefaults.standard.removeObject(forKey: "toolbarBgColor")
    }

    static func topButtons(isEditorMode: Bool = false) -> [ToolbarButton] {
        // 截图界面移除顶部工具栏，编辑器保持顶部工具栏由 EditorTopBarView 处理
        return []
    }


    // Bottom toolbar items (drawing tools + colors + undo/redo + processing actions)
    static func bottomButtons(
        selectedTool: AnnotationTool, selectedColor: NSColor, beautifyEnabled: Bool = false,
        beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false,
        effectsActive: Bool = false, isEditorMode: Bool = false
    ) -> [ToolbarButton] {
        var buttons: [ToolbarButton] = []

        // Get enabled tools from UserDefaults — migrate: only add tools that are brand-new.
        // Track introduced tools in `knownToolRawValues` so user-disabled tools are never re-enabled.
        let allKnownToolRawValues = AnnotationTool.allCases
            .filter { $0 != .select && $0 != .translateOverlay }
            .map { $0.rawValue }
        var enabledRawValues = UserDefaults.standard.array(forKey: "enabledTools") as? [Int]
        let knownToolRawValues = UserDefaults.standard.array(forKey: "knownToolRawValues") as? [Int]
        let newToolRaws = allKnownToolRawValues.filter { !(knownToolRawValues ?? []).contains($0) }
        if !newToolRaws.isEmpty {
            if enabledRawValues == nil {
                // Fresh install: enable everything.
                enabledRawValues = allKnownToolRawValues
            } else if knownToolRawValues == nil {
                // Upgrading from a version before knownToolRawValues tracking was added.
                // Respect the existing enabledTools as-is; just mark all current tools as known.
            } else {
                // Normal upgrade: new tools introduced — add them enabled by default.
                enabledRawValues = (enabledRawValues! + newToolRaws)
            }
            UserDefaults.standard.set(enabledRawValues, forKey: "enabledTools")
            UserDefaults.standard.set(allKnownToolRawValues, forKey: "knownToolRawValues")
        }

        // 工具按钮按分组排列：画笔 | 形状 | 标注
        let tools: [(AnnotationTool, String, String)] = [
            // 画笔组 (4个)
            (.pencil, "scribble", L("Pencil (Draw)")),
            (.line, "line.diagonal", L("Line")),
            (.arrow, "arrow.up.right", L("Arrow")),
            (.marker, {
                if #available(macOS 14.0, *) { return "highlighter" }
                return "paintbrush.pointed.fill"
            }(), L("Marker")),

            // 形状组 (4个)
            (.rectangle, "rectangle", L("Rectangle")),
            (.ellipse, "oval", L("Ellipse")),
            (.pixelate, "_custom.checkerboard", L("Censor (Pixelate / Blur / Solid)")),
            (.loupe, "magnifyingglass", L("Magnify (Loupe)")),

            // 标注组 (4个)
            (.text, "_custom.letterA", L("Text")),
            (.number, "1.circle.fill", L("Number")),
            (.stamp, "face.smiling", L("Stamp / Emoji")),
            (.measure, "ruler", L("Measure (px)")),
        ]

        var hasPlacedDrawingSection = false
        var hasPlacedShapesSection = false
        var hasPlacedAnnotationSection = false

        func beginSection(_ flag: inout Bool, button: inout ToolbarButton) {
            if !flag {
                button.sectionBreakBefore = true
                flag = true
            }
        }

        for (tool, symbol, tip) in tools {
            // Skip if disabled
            if let enabledRawValues = enabledRawValues, !enabledRawValues.contains(tool.rawValue) {
                continue
            }
            var btn = ToolbarButton(action: .tool(tool), sfSymbol: symbol, label: nil, tooltip: tip)
            btn.isSelected = (tool == selectedTool)

            // 根据工具类型确定分组
            switch tool {
            case .pencil, .line, .arrow, .marker:
                beginSection(&hasPlacedDrawingSection, button: &btn)
            case .rectangle, .ellipse, .pixelate, .loupe:
                beginSection(&hasPlacedShapesSection, button: &btn)
            case .text, .number, .stamp, .measure:
                beginSection(&hasPlacedAnnotationSection, button: &btn)
            default:
                break
            }

            buttons.append(btn)
        }

        // 撤销/重做按钮
        var undoBtn = ToolbarButton(action: .undo, sfSymbol: "arrow.uturn.backward", label: nil, tooltip: L("Undo"))
        undoBtn.sectionBreakBefore = true
        buttons.append(undoBtn)
        let redoBtn = ToolbarButton(action: .redo, sfSymbol: "arrow.uturn.forward", label: nil, tooltip: L("Redo"))
        buttons.append(redoBtn)

        // Get enabled actions from UserDefaults
        let allKnownActionTags: [Int] = [
            1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018,
        ]
        var enabledActions = UserDefaults.standard.array(forKey: "enabledActions") as? [Int]
        let knownActionTags = UserDefaults.standard.array(forKey: "knownActionTags") as? [Int]
        let newTags = allKnownActionTags.filter { !(knownActionTags ?? []).contains($0) }
        if !newTags.isEmpty {
            if enabledActions == nil {
                enabledActions = allKnownActionTags
            } else if knownActionTags == nil {
                // Upgrading from a version before knownActionTags tracking was added.
            } else {
                enabledActions = (enabledActions! + newTags)
            }
            UserDefaults.standard.set(enabledActions, forKey: "enabledActions")
            UserDefaults.standard.set(allKnownActionTags, forKey: "knownActionTags")
        }
        func actionEnabled(_ tag: Int) -> Bool {
            return enabledActions == nil || enabledActions!.contains(tag)
        }

        // 快捷操作按钮（取色、固定、保存、复制）- 支持启用/禁用
        var hasPlacedQuickActionSection = false

        func beginQuickActionSection(_ button: inout ToolbarButton) {
            if !hasPlacedQuickActionSection {
                button.sectionBreakBefore = true
                hasPlacedQuickActionSection = true
            }
        }

        // Color Picker (1016)
        if actionEnabled(1016) {
            var colorSamplerBtn = ToolbarButton(
                action: .tool(.colorSampler), sfSymbol: "eyedropper", label: nil,
                tooltip: L("Color Picker"))
            colorSamplerBtn.isSelected = (selectedTool == .colorSampler)
            beginQuickActionSection(&colorSamplerBtn)
            buttons.append(colorSamplerBtn)
        }

        // Pin (1002)
        if actionEnabled(1002) {
            var pinBtn = ToolbarButton(action: .pin, sfSymbol: "pin.fill", label: nil, tooltip: L("Pin"))
            beginQuickActionSection(&pinBtn)
            buttons.append(pinBtn)
        }

        // Save (1014)
        if actionEnabled(1014) {
            var saveBtn = ToolbarButton(
                action: .save, sfSymbol: "square.and.arrow.down.fill", label: nil,
                tooltip: String(
                    format: L("Save to %@"),
                    URL(fileURLWithPath: SaveDirectoryAccess.displayPath).lastPathComponent
                )
            )
            saveBtn.hasContextMenu = true
            beginQuickActionSection(&saveBtn)
            buttons.append(saveBtn)
        }

        // Copy (1015)
        if actionEnabled(1015) {
            var copyBtn = ToolbarButton(action: .copy, sfSymbol: "doc.on.doc", label: nil, tooltip: L("Copy"))
            beginQuickActionSection(&copyBtn)
            buttons.append(copyBtn)
        }

        return buttons
    }

    // Right toolbar items (output actions + cancel + delay)
    static func rightButtons(
        selectedTool: AnnotationTool = .pencil,
        beautifyEnabled: Bool = false, beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false,
        effectsActive: Bool = false, translateEnabled: Bool = false,
        isEditorMode: Bool = false
    ) -> [ToolbarButton] {
        var buttons: [ToolbarButton] = []

        let allKnownActionTags: [Int] = [
            1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 1015, 1016, 1017, 1018,
        ]
        // Migrate: only add action tags that are brand-new (never seen before).
        // knownActionTags tracks which tags have been introduced so user-disabled tags are
        // never silently re-enabled when future versions add new action tags.
        var enabledActions = UserDefaults.standard.array(forKey: "enabledActions") as? [Int]
        let knownActionTags = UserDefaults.standard.array(forKey: "knownActionTags") as? [Int]
        let newTags = allKnownActionTags.filter { !(knownActionTags ?? []).contains($0) }
        if !newTags.isEmpty {
            if enabledActions == nil {
                // Fresh install: enable everything.
                enabledActions = allKnownActionTags
            } else if knownActionTags == nil {
                // Upgrading from a version before knownActionTags tracking was added.
                // Respect existing enabledActions as-is; just mark all current tags as known.
            } else {
                // Normal upgrade path: newly added tags — enable by default.
                enabledActions = (enabledActions! + newTags)
            }
            UserDefaults.standard.set(enabledActions, forKey: "enabledActions")
            UserDefaults.standard.set(allKnownActionTags, forKey: "knownActionTags")
        }
        func actionEnabled(_ tag: Int) -> Bool {
            return enabledActions == nil || enabledActions!.contains(tag)
        }

        var hasPlacedSessionSection = false
        var hasPlacedContentSection = false
        var hasPlacedImageEffectsSection = false
        var hasPlacedAdvancedSection = false

        func beginSection(_ flag: inout Bool, button: inout ToolbarButton) {
            if !flag {
                button.sectionBreakBefore = true
                flag = true
            }
        }

        // 右侧第一组：会话操作（关闭、在编辑器打开、上传、分享）
        if !isEditorMode && actionEnabled(1017) {
            var closeBtn = ToolbarButton(action: .cancel, sfSymbol: "xmark", label: nil, tooltip: L("Cancel"))
            beginSection(&hasPlacedSessionSection, button: &closeBtn)
            buttons.append(closeBtn)
        }

        if !isEditorMode && actionEnabled(1018) {
            var detachBtn = ToolbarButton(
                action: .detach, sfSymbol: "arrow.up.forward.app", label: nil,
                tooltip: L("Open in Editor"))
            beginSection(&hasPlacedSessionSection, button: &detachBtn)
            buttons.append(detachBtn)
        }

        if actionEnabled(1001) {
            var uploadBtn = ToolbarButton(
                action: .upload, sfSymbol: "icloud.and.arrow.up", label: nil, tooltip: L("Upload"))
            uploadBtn.hasContextMenu = true
            beginSection(&hasPlacedSessionSection, button: &uploadBtn)
            buttons.append(uploadBtn)
        }

        if actionEnabled(1012) {
            var shareBtn = ToolbarButton(
                action: .share, sfSymbol: "square.and.arrow.up", label: nil, tooltip: L("Share"))
            beginSection(&hasPlacedSessionSection, button: &shareBtn)
            buttons.append(shareBtn)
        }

        // Image effects — above translate/OCR (same order in capture + editor)
        if actionEnabled(1004) {
            var beautifyBtn = ToolbarButton(
                action: .beautify, sfSymbol: "sparkles", label: nil, tooltip: L("Beautify"))
            beginSection(&hasPlacedImageEffectsSection, button: &beautifyBtn)
            buttons.append(beautifyBtn)
        }

        if actionEnabled(1013) {
            var effectsBtn = ToolbarButton(
                action: .effects, sfSymbol: "slider.horizontal.3", label: nil, tooltip: L("Adjust"))
            effectsBtn.isSelected = effectsActive
            if effectsActive {
                effectsBtn.tintColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            }
            beginSection(&hasPlacedImageEffectsSection, button: &effectsBtn)
            buttons.append(effectsBtn)
        }

        if actionEnabled(1011) {
            var invertBtn = ToolbarButton(
                action: .invertColors, sfSymbol: "circle.righthalf.filled.inverse", label: nil,
                tooltip: L("Invert Colors"))
            beginSection(&hasPlacedImageEffectsSection, button: &invertBtn)
            buttons.append(invertBtn)
        }

        if #available(macOS 14.0, *), actionEnabled(1005) {
            var removeBackgroundBtn = ToolbarButton(
                action: .removeBackground, sfSymbol: "person.crop.circle.dashed", label: nil,
                tooltip: L("Remove Background"))
            beginSection(&hasPlacedImageEffectsSection, button: &removeBackgroundBtn)
            buttons.append(removeBackgroundBtn)
        }

        if actionEnabled(1006) {
            var autoRedactBtn = ToolbarButton(
                action: .autoRedact, sfSymbol: "checkerboard.rectangle", label: nil,
                tooltip: L("Auto-Redact"))
            autoRedactBtn.hasContextMenu = true
            beginSection(&hasPlacedImageEffectsSection, button: &autoRedactBtn)
            buttons.append(autoRedactBtn)
        }

        // 内容处理（翻译、OCR — 在图像效果组下方）
        if actionEnabled(1008) {
            var translateBtn = ToolbarButton(
                action: .translate, sfSymbol: "translate", label: nil, tooltip: L("Translate"))
            translateBtn.isSelected = translateEnabled
            translateBtn.hasContextMenu = true
            beginSection(&hasPlacedContentSection, button: &translateBtn)
            buttons.append(translateBtn)
        }

        if actionEnabled(1003) {
            var ocrBtn = ToolbarButton(
                action: .ocr, sfSymbol: "doc.text.viewfinder", label: nil, tooltip: L("OCR"))
            beginSection(&hasPlacedContentSection, button: &ocrBtn)
            buttons.append(ocrBtn)
        }

        // Screenshot-only advanced actions
        if !isEditorMode && actionEnabled(1010) {
            var scrollBtn = ToolbarButton(
                action: .scrollCapture, sfSymbol: "scroll", label: nil,
                tooltip: L("Scroll Capture"))
            beginSection(&hasPlacedAdvancedSection, button: &scrollBtn)
            buttons.append(scrollBtn)
        }

        return buttons
    }

    // Layout bottom toolbar rects    // Layout bottom toolbar inside the selection (for full-screen selections)    // Layout right toolbar inside the selection (for full-screen selections)    // Layout right toolbar rects    // Icon cache: [symbolName: [isSelected: tintedImage]]
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
}
