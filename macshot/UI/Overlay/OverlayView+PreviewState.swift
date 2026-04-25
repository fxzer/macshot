import AppKit

private let overlayLineStyleKeys: [AnnotationTool: String] = [
    .pencil: "pencilLineStyle",
    .line: "lineLineStyle",
    .arrow: "arrowLineStyle",
    .rectangle: "rectangleLineStyle",
    .ellipse: "ellipseLineStyle",
]

private let overlayRectFillStyleKeys: [AnnotationTool: String] = [
    .rectangle: "rectangleFillStyle",
    .ellipse: "ellipseFillStyle",
]

private let overlayCornerRadiusKeys: [AnnotationTool: String] = [
    .rectangle: "rectangleCornerRadius",
]

private let overlayOutlineEnabledKeys: [AnnotationTool: String] = [
    .line: "lineOutlineEnabled",
    .arrow: "arrowOutlineEnabled",
    .rectangle: "rectangleOutlineEnabled",
    .ellipse: "ellipseOutlineEnabled",
    .number: "numberOutlineEnabled",
]

final class OverlayPreviewState {
    var lineStylePerTool: [AnnotationTool: LineStyle] = [:]
    var rectFillStylePerTool: [AnnotationTool: RectFillStyle] = [:]
    var rectCornerRadiusPerTool: [AnnotationTool: CGFloat] = [:]
    var outlineEnabledPerTool: [AnnotationTool: Bool] = [:]
    var currentArrowStyle =
        ArrowStyle(rawValue: UserDefaults.standard.integer(forKey: "currentArrowStyle")) ?? .single
    var arrowReversed = UserDefaults.standard.bool(forKey: "arrowReversed")
    var currentStampImage: NSImage?
    var currentStampEmoji: String?
    var stampPreviewPoint: NSPoint?
    let stampPreviewRadius: CGFloat = 40
    var pencilSmoothMode: Int = {
        if let old = UserDefaults.standard.object(forKey: "pencilSmoothEnabled") as? Bool {
            UserDefaults.standard.removeObject(forKey: "pencilSmoothEnabled")
            let mode = old ? 1 : 0
            UserDefaults.standard.set(mode, forKey: "pencilSmoothMode")
            return mode
        }
        return UserDefaults.standard.object(forKey: "pencilSmoothMode") as? Int ?? 1
    }()
    var pencilPressureEnabled =
        UserDefaults.standard.object(forKey: "pencilPressureEnabled") as? Bool ?? false
    var currentPressure: CGFloat = 1.0
    var smartMarkerEnabled =
        UserDefaults.standard.object(forKey: "smartMarkerEnabled") as? Bool ?? false
    var currentLoupeSize: CGFloat = {
        let value = UserDefaults.standard.object(forKey: "loupeSize") as? Double
        return value != nil ? CGFloat(value!) : 120.0
    }()
    let magnifiedCalloutPreview: MagnifiedCalloutPreviewController
    let numberedCalloutPreview: NumberedCalloutPreviewController
    var loupeCursorPoint: NSPoint = .zero
    var drawingCursorPoint: NSPoint = .zero
    var smartMarkerLineHeight: CGFloat?
    var cursorVisualMode: OverlayView.CursorVisualMode = .system
    var autoMeasurePreview: Annotation?
    var autoMeasureVertical = true
    var autoMeasureKeyHeld = false
    var autoMeasureBitmapCtx: CGContext?
    var autoMeasureBitmapW = 0
    var autoMeasureBitmapH = 0
    var snapGuideX: CGFloat?
    var snapGuideY: CGFloat?
    let snapThreshold: CGFloat = 5
    var selectionSizeSnapActive = false
    var selectionSizeSnapWidthActive = false
    var selectionSizeSnapHeightActive = false
    var selectionSizeSnapGuideX: CGFloat?
    var selectionSizeSnapGuideY: CGFloat?
    let selectionSizeSnapThresholdPx: CGFloat = 10
    var customColors: [NSColor?] = Array(repeating: nil, count: 7)
    var selectedColorSlot = 0
    var currentColorOpacity = OverlayView.lastUsedOpacity

    init(hostView: OverlayView) {
        magnifiedCalloutPreview = MagnifiedCalloutPreviewController(hostView: hostView)
        numberedCalloutPreview = NumberedCalloutPreviewController(hostView: hostView)
    }
}

extension OverlayView {
    func lineStyle(for tool: AnnotationTool) -> LineStyle {
        if let style = previewState.lineStylePerTool[tool] {
            return style
        }
        guard let key = overlayLineStyleKeys[tool] else { return .solid }
        let hasSavedValue = UserDefaults.standard.object(forKey: key) != nil
        let rawValue = hasSavedValue
            ? UserDefaults.standard.integer(forKey: key)
            : UserDefaults.standard.integer(forKey: "currentLineStyle")
        let saved = LineStyle(rawValue: rawValue) ?? .solid
        previewState.lineStylePerTool[tool] = saved
        return saved
    }

    func setLineStyle(_ style: LineStyle, for tool: AnnotationTool) {
        previewState.lineStylePerTool[tool] = style
        if let key = overlayLineStyleKeys[tool] {
            UserDefaults.standard.set(style.rawValue, forKey: key)
        }
        refreshToolCursorPreview()
    }

    var currentLineStyle: LineStyle {
        get { lineStyle(for: currentTool) }
        set { setLineStyle(newValue, for: currentTool) }
    }

    func arrowStyle(for tool: AnnotationTool) -> ArrowStyle {
        tool == .arrow ? previewState.currentArrowStyle : .single
    }

    func setArrowStyle(_ style: ArrowStyle, for tool: AnnotationTool) {
        guard tool == .arrow else { return }
        previewState.currentArrowStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "currentArrowStyle")
        refreshToolCursorPreview()
    }

    var currentArrowStyle: ArrowStyle {
        get { arrowStyle(for: currentTool) }
        set { setArrowStyle(newValue, for: currentTool) }
    }

    func arrowReversed(for tool: AnnotationTool) -> Bool {
        tool == .arrow ? previewState.arrowReversed : false
    }

    func setArrowReversed(_ isReversed: Bool, for tool: AnnotationTool) {
        guard tool == .arrow else { return }
        previewState.arrowReversed = isReversed
        UserDefaults.standard.set(isReversed, forKey: "arrowReversed")
        refreshToolCursorPreview()
    }

    var arrowReversed: Bool {
        get { arrowReversed(for: currentTool) }
        set { setArrowReversed(newValue, for: currentTool) }
    }

    func outlineEnabled(for tool: AnnotationTool) -> Bool {
        if let isEnabled = previewState.outlineEnabledPerTool[tool] {
            return isEnabled
        }
        guard let key = overlayOutlineEnabledKeys[tool] else { return false }
        let isEnabled =
            (UserDefaults.standard.object(forKey: key) as? Bool)
            ?? (UserDefaults.standard.object(forKey: "annotationOutlineEnabled") as? Bool)
            ?? false
        previewState.outlineEnabledPerTool[tool] = isEnabled
        return isEnabled
    }

    func setOutlineEnabled(_ isEnabled: Bool, for tool: AnnotationTool) {
        previewState.outlineEnabledPerTool[tool] = isEnabled
        if let key = overlayOutlineEnabledKeys[tool] {
            UserDefaults.standard.set(isEnabled, forKey: key)
        }
        refreshToolCursorPreview()
    }

    var defaultAnnotationOutlineColor: NSColor? {
        guard outlineEnabled(for: currentTool) else { return nil }
        if let data = UserDefaults.standard.data(forKey: "annotationOutlineColor"),
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        {
            return color
        }
        return .white
    }

    func rectFillStyle(for tool: AnnotationTool) -> RectFillStyle {
        if let style = previewState.rectFillStylePerTool[tool] {
            return style
        }
        guard let key = overlayRectFillStyleKeys[tool] else { return .stroke }
        let hasSavedValue = UserDefaults.standard.object(forKey: key) != nil
        let rawValue = hasSavedValue
            ? UserDefaults.standard.integer(forKey: key)
            : UserDefaults.standard.integer(forKey: "currentRectFillStyle")
        let saved = RectFillStyle(rawValue: rawValue) ?? .stroke
        previewState.rectFillStylePerTool[tool] = saved
        return saved
    }

    func setRectFillStyle(_ style: RectFillStyle, for tool: AnnotationTool) {
        previewState.rectFillStylePerTool[tool] = style
        if let key = overlayRectFillStyleKeys[tool] {
            UserDefaults.standard.set(style.rawValue, forKey: key)
        }
        refreshToolCursorPreview()
    }

    var currentRectFillStyle: RectFillStyle {
        get { rectFillStyle(for: currentTool) }
        set { setRectFillStyle(newValue, for: currentTool) }
    }

    var currentStampImage: NSImage? {
        get { previewState.currentStampImage }
        set {
            previewState.currentStampImage = newValue
            refreshToolCursorPreview()
        }
    }

    var currentStampEmoji: String? {
        get { previewState.currentStampEmoji }
        set { previewState.currentStampEmoji = newValue }
    }

    var stampPreviewPoint: NSPoint? {
        get { previewState.stampPreviewPoint }
        set { previewState.stampPreviewPoint = newValue }
    }

    var stampPreviewRadius: CGFloat { previewState.stampPreviewRadius }

    func rectCornerRadius(for tool: AnnotationTool) -> CGFloat {
        if let radius = previewState.rectCornerRadiusPerTool[tool] {
            return radius
        }
        guard let key = overlayCornerRadiusKeys[tool] else { return 0 }
        let value = CGFloat(
            (UserDefaults.standard.object(forKey: key) as? Double)
            ?? (UserDefaults.standard.object(forKey: "currentRectCornerRadius") as? Double)
            ?? 0
        )
        previewState.rectCornerRadiusPerTool[tool] = value
        return value
    }

    func setRectCornerRadius(_ radius: CGFloat, for tool: AnnotationTool) {
        previewState.rectCornerRadiusPerTool[tool] = radius
        if let key = overlayCornerRadiusKeys[tool] {
            UserDefaults.standard.set(Double(radius), forKey: key)
        }
        refreshToolCursorPreview()
    }

    var currentRectCornerRadius: CGFloat {
        get { rectCornerRadius(for: currentTool) }
        set { setRectCornerRadius(newValue, for: currentTool) }
    }

    var pencilSmoothMode: Int {
        get { previewState.pencilSmoothMode }
        set { previewState.pencilSmoothMode = newValue }
    }

    var pencilPressureEnabled: Bool {
        get { previewState.pencilPressureEnabled }
        set { previewState.pencilPressureEnabled = newValue }
    }

    var currentPressure: CGFloat {
        get { previewState.currentPressure }
        set { previewState.currentPressure = newValue }
    }

    var smartMarkerEnabled: Bool {
        get { previewState.smartMarkerEnabled }
        set {
            previewState.smartMarkerEnabled = newValue
            refreshToolCursorPreview()
        }
    }

    var currentLoupeSize: CGFloat {
        get { previewState.currentLoupeSize }
        set {
            previewState.currentLoupeSize = newValue
            refreshToolCursorPreview()
        }
    }

    var magnifiedCalloutPreview: MagnifiedCalloutPreviewController {
        previewState.magnifiedCalloutPreview
    }

    var numberedCalloutPreview: NumberedCalloutPreviewController {
        previewState.numberedCalloutPreview
    }

    var loupeCursorPoint: NSPoint {
        get { previewState.loupeCursorPoint }
        set { previewState.loupeCursorPoint = newValue }
    }

    var drawingCursorPoint: NSPoint {
        get { previewState.drawingCursorPoint }
        set { previewState.drawingCursorPoint = newValue }
    }

    var smartMarkerLineHeight: CGFloat? {
        get { previewState.smartMarkerLineHeight }
        set { previewState.smartMarkerLineHeight = newValue }
    }

    var cursorVisualMode: OverlayView.CursorVisualMode {
        get { previewState.cursorVisualMode }
        set { previewState.cursorVisualMode = newValue }
    }

    var autoMeasurePreview: Annotation? {
        get { previewState.autoMeasurePreview }
        set { previewState.autoMeasurePreview = newValue }
    }

    var autoMeasureVertical: Bool {
        get { previewState.autoMeasureVertical }
        set { previewState.autoMeasureVertical = newValue }
    }

    var autoMeasureKeyHeld: Bool {
        get { previewState.autoMeasureKeyHeld }
        set { previewState.autoMeasureKeyHeld = newValue }
    }

    var autoMeasureBitmapCtx: CGContext? {
        get { previewState.autoMeasureBitmapCtx }
        set { previewState.autoMeasureBitmapCtx = newValue }
    }

    var autoMeasureBitmapW: Int {
        get { previewState.autoMeasureBitmapW }
        set { previewState.autoMeasureBitmapW = newValue }
    }

    var autoMeasureBitmapH: Int {
        get { previewState.autoMeasureBitmapH }
        set { previewState.autoMeasureBitmapH = newValue }
    }

    var snapGuideX: CGFloat? {
        get { previewState.snapGuideX }
        set { previewState.snapGuideX = newValue }
    }

    var snapGuideY: CGFloat? {
        get { previewState.snapGuideY }
        set { previewState.snapGuideY = newValue }
    }

    var snapThreshold: CGFloat { previewState.snapThreshold }

    var selectionSizeSnapActive: Bool {
        get { previewState.selectionSizeSnapActive }
        set { previewState.selectionSizeSnapActive = newValue }
    }

    var selectionSizeSnapWidthActive: Bool {
        get { previewState.selectionSizeSnapWidthActive }
        set { previewState.selectionSizeSnapWidthActive = newValue }
    }

    var selectionSizeSnapHeightActive: Bool {
        get { previewState.selectionSizeSnapHeightActive }
        set { previewState.selectionSizeSnapHeightActive = newValue }
    }

    var selectionSizeSnapGuideX: CGFloat? {
        get { previewState.selectionSizeSnapGuideX }
        set { previewState.selectionSizeSnapGuideX = newValue }
    }

    var selectionSizeSnapGuideY: CGFloat? {
        get { previewState.selectionSizeSnapGuideY }
        set { previewState.selectionSizeSnapGuideY = newValue }
    }

    var selectionSizeSnapThresholdPx: CGFloat { previewState.selectionSizeSnapThresholdPx }

    var customColors: [NSColor?] {
        get { previewState.customColors }
        set { previewState.customColors = newValue }
    }

    var selectedColorSlot: Int {
        get { previewState.selectedColorSlot }
        set { previewState.selectedColorSlot = newValue }
    }

    var currentColorOpacity: CGFloat {
        get { previewState.currentColorOpacity }
        set {
            previewState.currentColorOpacity = newValue
            refreshToolCursorPreview()
        }
    }

    var snapGuidesEnabled: Bool {
        UserDefaults.standard.object(forKey: "snapGuidesEnabled") as? Bool ?? true
    }

    private var selectionSizeSnapMode: SelectionSizeSnapMode {
        let rawValue =
            UserDefaults.standard.object(forKey: "selectionSizeSnapMode") as? Int
            ?? SelectionSizeSnapMode.lockedAspectRatioOnly.rawValue
        return SelectionSizeSnapMode(rawValue: rawValue) ?? .lockedAspectRatioOnly
    }

    var allowsLockedAspectRatioSizeSnap: Bool {
        switch selectionSizeSnapMode {
        case .off:
            return false
        case .lockedAspectRatioOnly, .allSelections:
            return true
        }
    }

    var allowsFreeformSizeSnap: Bool {
        selectionSizeSnapMode == .allSelections
    }
}
