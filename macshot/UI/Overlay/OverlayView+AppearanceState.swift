import AppKit

final class OverlayAppearanceState {
    var beautifyEnabled = UserDefaults.standard.bool(forKey: "beautifyEnabled")
    var beautifyEditorOffset: NSPoint = .zero
    var beautifyStyleIndex = UserDefaults.standard.integer(forKey: "beautifyStyleIndex")
    var beautifyMode =
        BeautifyMode(rawValue: UserDefaults.standard.integer(forKey: "beautifyMode")) ?? .window
    var beautifyPadding: CGFloat = {
        let value = UserDefaults.standard.object(forKey: "beautifyPadding") as? Double
        return value != nil ? CGFloat(value!) : 48
    }()
    var beautifyCornerRadius: CGFloat = {
        let value = UserDefaults.standard.object(forKey: "beautifyCornerRadius") as? Double
        return value != nil ? CGFloat(value!) : 10
    }()
    var beautifyShadowRadius: CGFloat = {
        let value = UserDefaults.standard.object(forKey: "beautifyShadowRadius") as? Double
        return value != nil ? CGFloat(value!) : 20
    }()
    var beautifyBgRadius: CGFloat = {
        let value = UserDefaults.standard.object(forKey: "beautifyBgRadius") as? Double
        return value != nil ? CGFloat(value!) : 8
    }()
    var customBeautifyBackground: NSImage?
    var beautifyBackgroundBlur: CGFloat =
        UserDefaults.standard.object(forKey: "beautifyBgBlur") as? CGFloat ?? 0
    var cachedBeautifyBgCGImage: CGImage?
    var effectsPreset =
        ImageEffectPreset(rawValue: UserDefaults.standard.integer(forKey: "effectsPreset")) ?? .none
    var effectsBrightness: Float = {
        let value = UserDefaults.standard.object(forKey: "effectsBrightness") as? Double
        return value != nil ? Float(value!) : 0
    }()
    var effectsContrast: Float = {
        let value = UserDefaults.standard.object(forKey: "effectsContrast") as? Double
        return value != nil ? Float(value!) : 1.0
    }()
    var effectsSaturation: Float = {
        let value = UserDefaults.standard.object(forKey: "effectsSaturation") as? Double
        return value != nil ? Float(value!) : 1.0
    }()
    var effectsSharpness: Float = {
        let value = UserDefaults.standard.object(forKey: "effectsSharpness") as? Double
        return value != nil ? Float(value!) : 0
    }()
    var cachedEffectsScreenshot: NSImage?
    var colorPickerTarget: OverlayView.ColorPickerTarget = .drawColor
    var beautifyToolbarAnimProgress: CGFloat = 1.0
    var beautifyToolbarAnimTimer: Timer?
    var beautifyToolbarAnimTarget = false
    var backgroundRemovalSpinnerPhase: CGFloat = 0
    var backgroundRemovalSpinnerTimer: Timer?
    var currentMeasureInPoints = UserDefaults.standard.bool(forKey: "measureInPoints")
}

extension OverlayView {
    var beautifyEnabled: Bool {
        get { appearanceState.beautifyEnabled }
        set { appearanceState.beautifyEnabled = newValue }
    }

    var beautifyEditorOffset: NSPoint {
        get { appearanceState.beautifyEditorOffset }
        set { appearanceState.beautifyEditorOffset = newValue }
    }

    var beautifyStyleIndex: Int {
        get { appearanceState.beautifyStyleIndex }
        set { appearanceState.beautifyStyleIndex = newValue }
    }

    var beautifyMode: BeautifyMode {
        get { appearanceState.beautifyMode }
        set { appearanceState.beautifyMode = newValue }
    }

    var beautifyPadding: CGFloat {
        get { appearanceState.beautifyPadding }
        set { appearanceState.beautifyPadding = newValue }
    }

    var beautifyCornerRadius: CGFloat {
        get { appearanceState.beautifyCornerRadius }
        set { appearanceState.beautifyCornerRadius = newValue }
    }

    var beautifyShadowRadius: CGFloat {
        get { appearanceState.beautifyShadowRadius }
        set { appearanceState.beautifyShadowRadius = newValue }
    }

    var beautifyBgRadius: CGFloat {
        get { appearanceState.beautifyBgRadius }
        set { appearanceState.beautifyBgRadius = newValue }
    }

    var customBeautifyBackground: NSImage? {
        get { appearanceState.customBeautifyBackground }
        set {
            appearanceState.customBeautifyBackground = newValue
            cachedBeautifyBgCGImage = nil
        }
    }

    var beautifyBackgroundBlur: CGFloat {
        get { appearanceState.beautifyBackgroundBlur }
        set {
            appearanceState.beautifyBackgroundBlur = newValue
            cachedBeautifyBgCGImage = nil
            prepareBeautifyBackgroundCache()
        }
    }

    var cachedBeautifyBgCGImage: CGImage? {
        get { appearanceState.cachedBeautifyBgCGImage }
        set { appearanceState.cachedBeautifyBgCGImage = newValue }
    }

    var effectsPreset: ImageEffectPreset {
        get { appearanceState.effectsPreset }
        set { appearanceState.effectsPreset = newValue }
    }

    var effectsBrightness: Float {
        get { appearanceState.effectsBrightness }
        set { appearanceState.effectsBrightness = newValue }
    }

    var effectsContrast: Float {
        get { appearanceState.effectsContrast }
        set { appearanceState.effectsContrast = newValue }
    }

    var effectsSaturation: Float {
        get { appearanceState.effectsSaturation }
        set { appearanceState.effectsSaturation = newValue }
    }

    var effectsSharpness: Float {
        get { appearanceState.effectsSharpness }
        set { appearanceState.effectsSharpness = newValue }
    }

    var effectsConfig: ImageEffectsConfig {
        ImageEffectsConfig(
            preset: effectsPreset,
            brightness: effectsBrightness,
            contrast: effectsContrast,
            saturation: effectsSaturation,
            sharpness: effectsSharpness)
    }

    var effectsActive: Bool { !effectsConfig.isIdentity }

    var cachedEffectsScreenshot: NSImage? {
        get { appearanceState.cachedEffectsScreenshot }
        set { appearanceState.cachedEffectsScreenshot = newValue }
    }

    var colorPickerTarget: ColorPickerTarget {
        get { appearanceState.colorPickerTarget }
        set { appearanceState.colorPickerTarget = newValue }
    }

    var beautifyToolbarAnimProgress: CGFloat {
        get { appearanceState.beautifyToolbarAnimProgress }
        set { appearanceState.beautifyToolbarAnimProgress = newValue }
    }

    var beautifyToolbarAnimTimer: Timer? {
        get { appearanceState.beautifyToolbarAnimTimer }
        set { appearanceState.beautifyToolbarAnimTimer = newValue }
    }

    var beautifyToolbarAnimTarget: Bool {
        get { appearanceState.beautifyToolbarAnimTarget }
        set { appearanceState.beautifyToolbarAnimTarget = newValue }
    }

    var backgroundRemovalSpinnerPhase: CGFloat {
        get { appearanceState.backgroundRemovalSpinnerPhase }
        set { appearanceState.backgroundRemovalSpinnerPhase = newValue }
    }

    var backgroundRemovalSpinnerTimer: Timer? {
        get { appearanceState.backgroundRemovalSpinnerTimer }
        set { appearanceState.backgroundRemovalSpinnerTimer = newValue }
    }

    var currentMeasureInPoints: Bool {
        get { appearanceState.currentMeasureInPoints }
        set { appearanceState.currentMeasureInPoints = newValue }
    }
}
