enum CaptureIntent {
    case area
    case fullScreen
    case ocr
    case quickCapture
    case scrollCapture
    case areaRecording
    case fullScreenRecording(autoStartAfterDelay: Bool)

    var startsInRecordingMode: Bool {
        switch self {
        case .areaRecording, .fullScreenRecording:
            return true
        default:
            return false
        }
    }

    var startsInOCRMode: Bool {
        switch self {
        case .ocr:
            return true
        default:
            return false
        }
    }

    var startsInQuickSaveMode: Bool {
        switch self {
        case .quickCapture:
            return true
        default:
            return false
        }
    }

    var startsInScrollCaptureMode: Bool {
        switch self {
        case .scrollCapture:
            return true
        default:
            return false
        }
    }

    var appliesFullScreenSelection: Bool {
        switch self {
        case .fullScreen, .fullScreenRecording:
            return true
        default:
            return false
        }
    }

    var autoStartsFullScreenRecording: Bool {
        switch self {
        case .fullScreenRecording(let autoStartAfterDelay):
            return autoStartAfterDelay
        default:
            return false
        }
    }

    var shouldRestoreLastSelection: Bool {
        !appliesFullScreenSelection
    }

    var prefersImmediateOverlayPresentation: Bool {
        switch self {
        case .area:
            // Safe now that the live capture path explicitly excludes the placeholder
            // overlay window and refreshes SCShareableContent when needed.
            return true
        case .fullScreen:
            return false
        default:
            return false
        }
    }

    var debugName: String {
        switch self {
        case .area:
            return "area"
        case .fullScreen:
            return "fullScreen"
        case .ocr:
            return "ocr"
        case .quickCapture:
            return "quickCapture"
        case .scrollCapture:
            return "scrollCapture"
        case .areaRecording:
            return "areaRecording"
        case .fullScreenRecording:
            return "fullScreenRecording"
        }
    }
}
