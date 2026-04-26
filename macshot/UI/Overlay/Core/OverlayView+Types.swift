import AppKit

@MainActor
protocol OverlayViewDelegate: AnyObject {
    func overlayViewDidFinishSelection(_ rect: NSRect)
    func overlayViewSelectionDidChange(_ rect: NSRect)
    func overlayViewDidCancel()
    func overlayViewDidConfirm()
    func overlayViewDidRequestSave()
    func overlayViewDidRequestPin()
    func overlayViewDidRequestOCR()
    func overlayViewDidRequestQuickSave()
    func overlayViewDidRequestFileSave()
    func overlayViewDidRequestUpload()
    func overlayViewDidRequestShare(anchorView: NSView?)
    @available(macOS 14.0, *)
    func overlayViewDidRequestRemoveBackground()
    func overlayViewDidRequestEnterRecordingMode()
    func overlayViewDidRequestStartRecording(rect: NSRect)
    func overlayViewDidRequestStopRecording()
    func overlayViewDidRequestDetach()
    func overlayViewDidRequestScrollCapture(rect: NSRect)
    func overlayViewDidRequestStopScrollCapture()
    func overlayViewDidRequestToggleAutoScroll()
    func overlayViewDidRequestAccessibilityPermission()
    func overlayViewDidRequestInputMonitoringPermission()
    func overlayViewDidBeginSelection()
    func overlayViewRemoteSelectionDidChange(_ rect: NSRect)
    func overlayViewDidChangeWindowSnapState()
    func overlayViewRemoteSelectionDidFinish(_ rect: NSRect)
    func overlayViewDidRequestAddCapture()
    func overlayViewDidChangeAspectRatioLock()
    func overlayViewDidChangeMouseLocation()
    func overlayViewLogicalSizeDidChange(_ size: NSSize)
    func overlayViewDidShowHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    )
    func overlayViewDidShowError(message: String)
}

extension OverlayViewDelegate {
    func overlayViewLogicalSizeDidChange(_ size: NSSize) {}
    func overlayViewDidShowHint(
        message: String,
        opacity: CGFloat,
        colorString: String?,
        attributedString: NSAttributedString?
    ) {}
    func overlayViewDidShowError(message: String) {}
}

enum UndoEntry {
    case added(Annotation)
    case deleted(Annotation, Int)
    case imageTransform(previousImage: NSImage, annotationOffsets: [(Annotation, CGFloat, CGFloat)])
    case propertyChange(annotation: Annotation, snapshot: Annotation)

    var annotation: Annotation {
        switch self {
        case .added(let annotation), .deleted(let annotation, _):
            return annotation
        case .propertyChange(let annotation, _):
            return annotation
        case .imageTransform:
            return Annotation(
                tool: .measure,
                startPoint: .zero,
                endPoint: .zero,
                color: .clear,
                strokeWidth: 0)
        }
    }
}

struct OverlayEditorState {
    var screenshotImage: NSImage?
    var selectionRect: NSRect
    var annotations: [Annotation]
    var undoStack: [UndoEntry]
    var redoStack: [UndoEntry]
    var currentTool: AnnotationTool
    var currentColor: NSColor
    var currentStrokeWidth: CGFloat
    var currentMarkerSize: CGFloat
    var currentNumberSize: CGFloat
    var numberCounter: Int
    var beautifyEnabled: Bool
    var beautifyStyleIndex: Int
    var effectsPreset: ImageEffectPreset
    var effectsBrightness: Float
    var effectsContrast: Float
    var effectsSaturation: Float
    var effectsSharpness: Float
}

extension OverlayView {
    enum State {
        case idle
        case selecting
        case selected
    }

    enum AspectRatioLock: Equatable {
        case none
        case oneToOne
        case threeToFour
        case nineToSixteen
        case customRatio(width: Int, height: Int)

        var ratio: CGFloat {
            switch self {
            case .none:
                return 0
            case .oneToOne:
                return 1.0
            case .threeToFour:
                return 3.0 / 4.0
            case .nineToSixteen:
                return 9.0 / 16.0
            case .customRatio(let width, let height):
                guard height > 0 else { return 0 }
                return CGFloat(width) / CGFloat(height)
            }
        }

        var displayName: String {
            switch self {
            case .none:
                return L("Free")
            case .oneToOne:
                return "1:1"
            case .threeToFour:
                return "3:4"
            case .nineToSixteen:
                return "9:16"
            case .customRatio(let width, let height):
                return "\(width):\(height)"
            }
        }

        var inverted: AspectRatioLock {
            switch self {
            case .none, .oneToOne:
                return self
            case .threeToFour:
                return .customRatio(width: 4, height: 3)
            case .nineToSixteen:
                return .customRatio(width: 16, height: 9)
            case .customRatio(let width, let height):
                return .customRatio(width: height, height: width)
            }
        }

        init(from ratio: CustomAspectRatio) {
            switch (ratio.width, ratio.height) {
            case (1, 1):
                self = .oneToOne
            case (3, 4):
                self = .threeToFour
            case (9, 16):
                self = .nineToSixteen
            default:
                self = .customRatio(width: ratio.width, height: ratio.height)
            }
        }

        func sharesShortcutGroup(with other: AspectRatioLock) -> Bool {
            guard let lhs = dimensions, let rhs = other.dimensions else { return false }
            return normalizedPair(for: lhs) == normalizedPair(for: rhs)
        }

        private var dimensions: (width: Int, height: Int)? {
            switch self {
            case .none:
                return nil
            case .oneToOne:
                return (1, 1)
            case .threeToFour:
                return (3, 4)
            case .nineToSixteen:
                return (9, 16)
            case .customRatio(let width, let height):
                return (width, height)
            }
        }

        private func normalizedPair(for dimensions: (width: Int, height: Int)) -> (Int, Int) {
            let divisor = greatestCommonDivisor(abs(dimensions.width), abs(dimensions.height))
            let normalizedWidth = divisor > 0 ? dimensions.width / divisor : dimensions.width
            let normalizedHeight = divisor > 0 ? dimensions.height / divisor : dimensions.height
            return (min(normalizedWidth, normalizedHeight), max(normalizedWidth, normalizedHeight))
        }

        private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
            var a = lhs
            var b = rhs
            while b != 0 {
                let remainder = a % b
                a = b
                b = remainder
            }
            return a
        }
    }

    enum ColorPickerTarget {
        case drawColor
        case textBg
        case textOutline
        case annotationOutline
    }

    enum ResizeHandle {
        case none
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case move
    }
}
