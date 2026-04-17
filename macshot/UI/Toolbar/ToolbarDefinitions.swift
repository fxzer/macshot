import Cocoa

extension Notification.Name {
    static let toolbarColorsDidChange = Notification.Name("toolbarColorsDidChange")
}

// Toolbar buttons drawn directly in the OverlayView (not a separate window).
// This avoids window-level z-order issues and matches Flameshot's look.

enum ToolbarButtonAction {
    case sessionCancel
    case sessionUndo
    case sessionRedo
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
    case record  // enters recording mode (shows recording toolbar)
    case startRecord  // actually starts recording
    case stopRecord
    case mouseHighlight
    case systemAudio
    case micAudio
    case detach
    case scrollCapture
    case addCapture  // editor only: capture a new region and append to the canvas
    case showKeystrokes
    case webcam
    case recordSettings  // recording mode: open format/FPS/when-done popover
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
    /// When true, a separator is drawn before this button in the vertical right toolbar (ignored on bottom bar).
    var sectionBreakBefore: Bool = false
    var isEnabled: Bool = true  // Optional: whether the button is enabled (default: true)
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
    static let buttonSpacing: CGFloat = 2
    static let toolbarPadding: CGFloat = 4
    static let cornerRadius: CGFloat = 6

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

    static func topButtons(isRecording: Bool = false, isEditorMode: Bool = false) -> [ToolbarButton] {
        // Top toolbar removed in main interface - only close/detach moved to right side
        // Editor mode uses EditorTopBarView instead
        return []
    }

    // Bottom toolbar items - reorganized into two containers
    // Container 1: Drawing tools (10) + separator + undo/redo (2)
    // Container 2: Heavy operations (4) - separated by 16px spacing
    static func bottomButtons(
        selectedTool: AnnotationTool, selectedColor: NSColor, beautifyEnabled: Bool = false,
        beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false, isRecording: Bool = false,
        effectsActive: Bool = false, canUndo: Bool = false, canRedo: Bool = false,
        isEditorMode: Bool = false
    ) -> [ToolbarButton] {
        // Hide the bottom bar entirely while recording
        if isRecording { return [] }

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

        // Container 1: Drawing tools (10) + separator + undo/redo (2)
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

            // 标注组 (2个) - 移除 colorSampler（移到右侧）
            (.text, "_custom.letterA", L("Text")),
            (.number, "1.circle.fill", L("Number")),
        ]

        for (tool, symbol, tip) in tools {
            // Skip if disabled
            if let enabledRawValues = enabledRawValues, !enabledRawValues.contains(tool.rawValue) {
                continue
            }
            var btn = ToolbarButton(action: .tool(tool), sfSymbol: symbol, label: nil, tooltip: tip)
            btn.isSelected = (tool == selectedTool)
            buttons.append(btn)
        }

        // 添加 stamp 和 measure（如果有启用）
        let additionalTools: [(AnnotationTool, String, String)] = [
            (.stamp, "face.smiling", L("Stamp / Emoji")),
            (.measure, "ruler", L("Measure (px)")),
        ]

        for (tool, symbol, tip) in additionalTools {
            if let enabledRawValues = enabledRawValues, !enabledRawValues.contains(tool.rawValue) {
                continue
            }
            var btn = ToolbarButton(action: .tool(tool), sfSymbol: symbol, label: nil, tooltip: tip)
            btn.isSelected = (tool == selectedTool)
            buttons.append(btn)
        }

        // Container 1: Undo/Redo (after separator)
        var undoBtn = ToolbarButton(action: .undo, sfSymbol: "arrow.uturn.backward", label: nil, tooltip: L("Undo"))
        undoBtn.isEnabled = canUndo
        buttons.append(undoBtn)

        var redoBtn = ToolbarButton(action: .redo, sfSymbol: "arrow.uturn.forward", label: nil, tooltip: L("Redo"))
        redoBtn.isEnabled = canRedo
        buttons.append(redoBtn)

        // Container 2: Heavy operations (4 buttons) - ONLY in editor mode
        // These operations are too heavy for the capture interface
        if isEditorMode {
            var effectsBtn = ToolbarButton(action: .effects, sfSymbol: "slider.horizontal.3", label: nil, tooltip: L("Adjust"))
            effectsBtn.isSelected = effectsActive
            if effectsActive {
                effectsBtn.tintColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            }
            buttons.append(effectsBtn)

            var beautifyBtn = ToolbarButton(action: .beautify, sfSymbol: "sparkles", label: nil, tooltip: L("Share Card"))
            beautifyBtn.isSelected = beautifyEnabled
            if beautifyEnabled {
                beautifyBtn.tintColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
            }
            buttons.append(beautifyBtn)

            var invertBtn = ToolbarButton(action: .invertColors, sfSymbol: "circle.righthalf.filled.inverse", label: nil, tooltip: L("Invert Colors"))
            buttons.append(invertBtn)

            if #available(macOS 14.0, *) {
                var removeBgBtn = ToolbarButton(action: .removeBackground, sfSymbol: "person.crop.circle.dashed", label: nil, tooltip: L("Remove Background"))
                buttons.append(removeBgBtn)
            }
        }

        return buttons
    }

    // Right toolbar items - simplified to only essential actions
    // Main interface: Close, Pin, Editor, Color Sampler
    // Editor mode: Pin, Color Sampler (no Close or Editor buttons)
    static func rightButtons(
        beautifyEnabled: Bool = false, beautifyStyleIndex: Int = 0, hasAnnotations: Bool = false,
        effectsActive: Bool = false, beautifyPanelVisible: Bool = false, translateEnabled: Bool = false, isRecording: Bool = false,
        isEditorMode: Bool = false
    ) -> [ToolbarButton] {
        var buttons: [ToolbarButton] = []

        // Recording setup mode — show start button + toggles, then return early
        if isRecording {
            var startBtn = ToolbarButton(
                action: .startRecord, sfSymbol: "record.circle", label: nil,
                tooltip: L("Start Recording"))
            startBtn.tintColor = .systemRed
            buttons.append(startBtn)

            // Stop/cancel button to exit recording mode without starting
            buttons.append(
                ToolbarButton(action: .stopRecord, sfSymbol: "xmark", label: nil, tooltip: L("Cancel Recording")))

            let mouseHighlightOn = UserDefaults.standard.bool(forKey: "recordMouseHighlight")
            var mouseBtn = ToolbarButton(
                action: .mouseHighlight, sfSymbol: "cursorarrow.click.2", label: nil,
                tooltip: L("Highlight Mouse Clicks"))
            mouseBtn.isSelected = mouseHighlightOn
            mouseBtn.sectionBreakBefore = true
            buttons.append(mouseBtn)

            let keystrokesOn = UserDefaults.standard.bool(forKey: "recordKeystroke")
            var keystrokeBtn = ToolbarButton(
                action: .showKeystrokes, sfSymbol: "keyboard", label: nil,
                tooltip: L("Show Keystrokes"))
            keystrokeBtn.isSelected = keystrokesOn
            keystrokeBtn.hasContextMenu = true
            buttons.append(keystrokeBtn)

            let audioOn = UserDefaults.standard.bool(forKey: "recordSystemAudio")
            var audioBtn = ToolbarButton(
                action: .systemAudio, sfSymbol: audioOn ? "speaker.wave.2.fill" : "speaker.slash",
                label: nil, tooltip: L("Record System Audio"))
            audioBtn.isSelected = audioOn
            buttons.append(audioBtn)

            let micOn = UserDefaults.standard.bool(forKey: "recordMicAudio")
            var micBtn = ToolbarButton(
                action: .micAudio, sfSymbol: micOn ? "mic.fill" : "mic.slash", label: nil,
                tooltip: L("Record Microphone"))
            micBtn.isSelected = micOn
            micBtn.hasContextMenu = true
            buttons.append(micBtn)

            let webcamOn = UserDefaults.standard.bool(forKey: "recordWebcam")
            let webcamSymbol: String = {
                if #available(macOS 14.0, *) {
                    return webcamOn ? "web.camera.fill" : "web.camera"
                }
                return webcamOn ? "camera.fill" : "camera"
            }()
            var webcamBtn = ToolbarButton(
                action: .webcam, sfSymbol: webcamSymbol, label: nil,
                tooltip: L("Webcam Overlay"))
            webcamBtn.isSelected = webcamOn
            webcamBtn.hasContextMenu = true
            buttons.append(webcamBtn)

            // Recording settings gear
            var settingsBtn = ToolbarButton(
                action: .recordSettings, sfSymbol: "gearshape", label: nil,
                tooltip: L("Recording Settings"))
            settingsBtn.sectionBreakBefore = true
            buttons.append(settingsBtn)

            return buttons
        }

        // Main interface: Close, Pin, Editor, Color Sampler
        if !isEditorMode {
            // Close button
            var closeBtn = ToolbarButton(action: .sessionCancel, sfSymbol: "xmark", label: nil, tooltip: L("Close"))
            buttons.append(closeBtn)

            // Pin button
            var pinBtn = ToolbarButton(action: .pin, sfSymbol: "pin.fill", label: nil, tooltip: L("Pin"))
            pinBtn.sectionBreakBefore = true
            buttons.append(pinBtn)

            // Open in Editor button
            var detachBtn = ToolbarButton(
                action: .detach, sfSymbol: "arrow.up.forward.app", label: nil,
                tooltip: L("Open in Editor Window"))
            buttons.append(detachBtn)

            // Color Sampler (moved from bottom toolbar)
            var colorSamplerBtn = ToolbarButton(
                action: .tool(.colorSampler), sfSymbol: "eyedropper", label: nil,
                tooltip: L("Color Picker"))
            colorSamplerBtn.sectionBreakBefore = true
            buttons.append(colorSamplerBtn)
        } else {
            // Editor mode: only Pin and Color Sampler
            // Pin button
            var pinBtn = ToolbarButton(action: .pin, sfSymbol: "pin.fill", label: nil, tooltip: L("Pin"))
            buttons.append(pinBtn)

            // Color Sampler
            var colorSamplerBtn = ToolbarButton(
                action: .tool(.colorSampler), sfSymbol: "eyedropper", label: nil,
                tooltip: L("Color Picker"))
            colorSamplerBtn.sectionBreakBefore = true
            buttons.append(colorSamplerBtn)
        }

        return buttons
    }

    // Layout bottom toolbar rects    // Layout bottom toolbar inside the selection (for full-screen selections)    // Layout right toolbar inside the selection (for full-screen selections)    // Layout right toolbar rects    // Icon cache: [symbolName: [isSelected: tintedImage]]
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
}
