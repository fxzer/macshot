import AppKit

private var overlayLastUsedTool: AnnotationTool = .arrow
private var overlayUserClosedTool = false
private var overlayLastUsedOpacityStorage: CGFloat = {
    let saved = UserDefaults.standard.object(forKey: "lastUsedColorOpacity") as? Double
    return saved.map { CGFloat($0) } ?? 1.0
}()

private func overlayStoredCGFloat(_ key: String, defaultValue: CGFloat) -> CGFloat {
    let saved = UserDefaults.standard.object(forKey: key) as? Double
    return saved.map { CGFloat($0) } ?? defaultValue
}

private func overlayStoredColor() -> NSColor {
    guard
        let data = UserDefaults.standard.data(forKey: "lastUsedColor"),
        let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    else {
        return .systemRed
    }
    return color
}

private func overlayInitialTool() -> AnnotationTool {
    let rememberLastTool = UserDefaults.standard.object(forKey: "rememberLastTool") as? Bool ?? true
    if overlayUserClosedTool {
        return .select
    }
    return rememberLastTool ? overlayLastUsedTool : .arrow
}

private func overlayInitialMarkerSize() -> CGFloat {
    guard let saved = UserDefaults.standard.object(forKey: "markerStrokeWidth") as? Double else {
        UserDefaults.standard.set(true, forKey: "markerStrokeWidthV2")
        return 18.0
    }

    if !UserDefaults.standard.bool(forKey: "markerStrokeWidthV2") {
        let migrated = saved * 6
        UserDefaults.standard.set(migrated, forKey: "markerStrokeWidth")
        UserDefaults.standard.set(true, forKey: "markerStrokeWidthV2")
        return CGFloat(migrated)
    }

    return CGFloat(saved)
}

let overlayPerToolStrokeWidthKeys: [AnnotationTool: String] = [
    .rectangle: "rectangleStrokeWidth",
    .filledRectangle: "filledRectangleStrokeWidth",
    .ellipse: "ellipseStrokeWidth",
    .pixelate: "pixelateStrokeWidth",
    .blur: "blurStrokeWidth",
    .measure: "measureStrokeWidth",
    .text: "textStrokeWidth",
]

private func overlayInitialGenericStrokeWidths() -> [AnnotationTool: CGFloat] {
    let legacyDefault = overlayStoredCGFloat("currentStrokeWidth", defaultValue: 3.0)
    return Dictionary(uniqueKeysWithValues: overlayPerToolStrokeWidthKeys.map { tool, key in
        (tool, overlayStoredCGFloat(key, defaultValue: legacyDefault))
    })
}

final class OverlayToolState {
    var currentTool: AnnotationTool = overlayInitialTool()
    var currentColor: NSColor = overlayStoredColor()
    var currentStrokeWidth: CGFloat = overlayStoredCGFloat("currentStrokeWidth", defaultValue: 3.0)
    var currentPencilStrokeWidth: CGFloat = overlayStoredCGFloat("pencilStrokeWidth", defaultValue: 3.0)
    var currentLineStrokeWidth: CGFloat = overlayStoredCGFloat("lineStrokeWidth", defaultValue: 3.0)
    var currentArrowStrokeWidth: CGFloat = overlayStoredCGFloat("arrowStrokeWidth", defaultValue: 3.0)
    var currentNumberSize: CGFloat = overlayStoredCGFloat("numberStrokeWidth", defaultValue: 3.0)
    var currentMarkerSize: CGFloat = overlayInitialMarkerSize()
    var genericStrokeWidths: [AnnotationTool: CGFloat] = overlayInitialGenericStrokeWidths()
    var numberCounter = 0
    var numberStartAt = NumberToolConfiguration.clampedStartValue(
        UserDefaults.standard.object(forKey: "numberStartAt") as? Int ?? 1)
    var currentNumberFormat =
        NumberFormat(rawValue: UserDefaults.standard.integer(forKey: "numberFormat")) ?? .decimal
}

extension OverlayView {
    static var lastUsedOpacity: CGFloat {
        get { overlayLastUsedOpacityStorage }
        set { overlayLastUsedOpacityStorage = newValue }
    }

    var currentTool: AnnotationTool {
        get { toolState.currentTool }
        set {
            let oldValue = toolState.currentTool
            toolState.currentTool = newValue

            if newValue == .select && oldValue != .select {
                overlayUserClosedTool = true
            } else if newValue != .select && newValue != .loupe {
                overlayUserClosedTool = false
                overlayLastUsedTool = newValue
            }

            refreshToolCursorPreview()
        }
    }

    var currentColor: NSColor {
        get { toolState.currentColor }
        set {
            toolState.currentColor = newValue
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: newValue,
                requiringSecureCoding: true
            ) {
                UserDefaults.standard.set(data, forKey: "lastUsedColor")
            }
            updateToolbarColorSwatch()
            refreshToolCursorPreview()
        }
    }

    func storedStrokeWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .select:
            currentPencilStrokeWidth
        case .pencil:
            currentPencilStrokeWidth
        case .line:
            currentLineStrokeWidth
        case .arrow:
            currentArrowStrokeWidth
        case .number:
            currentNumberSize
        case .marker:
            currentMarkerSize
        case .loupe:
            currentLoupeSize
        default:
            toolState.genericStrokeWidths[tool] ?? toolState.currentStrokeWidth
        }
    }

    func updateStoredStrokeWidth(_ value: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .select:
            currentPencilStrokeWidth = value
        case .pencil:
            currentPencilStrokeWidth = value
        case .line:
            currentLineStrokeWidth = value
        case .arrow:
            currentArrowStrokeWidth = value
        case .number:
            currentNumberSize = value
        case .marker:
            currentMarkerSize = value
        case .loupe:
            currentLoupeSize = value
        default:
            toolState.genericStrokeWidths[tool] = value
            toolState.currentStrokeWidth = value
        }
    }

    var currentStrokeWidth: CGFloat {
        get { storedStrokeWidth(for: currentTool) }
        set { updateStoredStrokeWidth(newValue, for: currentTool) }
    }

    var currentPencilStrokeWidth: CGFloat {
        get { toolState.currentPencilStrokeWidth }
        set { toolState.currentPencilStrokeWidth = newValue }
    }

    var currentLineStrokeWidth: CGFloat {
        get { toolState.currentLineStrokeWidth }
        set { toolState.currentLineStrokeWidth = newValue }
    }

    var currentArrowStrokeWidth: CGFloat {
        get { toolState.currentArrowStrokeWidth }
        set { toolState.currentArrowStrokeWidth = newValue }
    }

    var currentNumberSize: CGFloat {
        get { toolState.currentNumberSize }
        set { toolState.currentNumberSize = newValue }
    }

    var currentMarkerSize: CGFloat {
        get { toolState.currentMarkerSize }
        set { toolState.currentMarkerSize = newValue }
    }

    var numberCounter: Int {
        get { toolState.numberCounter }
        set { toolState.numberCounter = newValue }
    }

    var numberStartAt: Int {
        get { toolState.numberStartAt }
        set { toolState.numberStartAt = NumberToolConfiguration.clampedStartValue(newValue) }
    }

    var currentNumberFormat: NumberFormat {
        get { toolState.currentNumberFormat }
        set { toolState.currentNumberFormat = newValue }
    }
}
