import Foundation

enum AppExternalAction {
    static let scheme = "macshot"

    case captureArea
    case captureFullScreen
    case quickCapture
    case captureOCR
    case recordArea
    case recordFullScreen
    case scrollCapture
    case history
    case settings
    case stopRecording
    case openImage(URL)

    enum ParseError: LocalizedError {
        case unsupportedAction(String)
        case missingOpenFile
        case invalidOpenFile(ImageFileLoader.LoadError)

        var errorDescription: String? {
            switch self {
            case .unsupportedAction(let action):
                return String(format: L("Unsupported macshot action: %@"), action)
            case .missingOpenFile:
                return L("Missing image file path in macshot://open URL.")
            case .invalidOpenFile(let error):
                return error.localizedDescription
            }
        }
    }

    static func parse(url: URL) -> Result<AppExternalAction, ParseError> {
        guard url.scheme?.lowercased() == scheme else {
            return .failure(.unsupportedAction(url.absoluteString))
        }

        let actionName = normalizedActionName(from: url)
        switch actionName {
        case "capture", "capture-area":
            return .success(.captureArea)
        case "capture-fullscreen", "capture-screen":
            return .success(.captureFullScreen)
        case "quick-capture":
            return .success(.quickCapture)
        case "ocr", "capture-ocr":
            return .success(.captureOCR)
        case "record", "record-area":
            return .success(.recordArea)
        case "record-fullscreen", "record-screen":
            return .success(.recordFullScreen)
        case "scroll-capture":
            return .success(.scrollCapture)
        case "history", "history-panel":
            return .success(.history)
        case "settings", "preferences":
            return .success(.settings)
        case "stop-recording":
            return .success(.stopRecording)
        case "open":
            return resolveOpenImage(from: url)
        default:
            return .failure(.unsupportedAction(actionName.isEmpty ? url.absoluteString : actionName))
        }
    }

    private static func normalizedActionName(from url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host == "x-callback-url" {
            return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        if !host.isEmpty {
            return host
        }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func resolveOpenImage(from url: URL) -> Result<AppExternalAction, ParseError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawFile = components.queryItems?.first(where: { $0.name == "file" })?.value,
              !rawFile.isEmpty else {
            return .failure(.missingOpenFile)
        }

        let candidateURL: URL
        if let parsedURL = URL(string: rawFile), parsedURL.isFileURL {
            candidateURL = parsedURL
        } else {
            candidateURL = URL(fileURLWithPath: rawFile)
        }

        switch ImageFileLoader.validatedImageFileURL(for: candidateURL) {
        case .success(let fileURL):
            return .success(.openImage(fileURL))
        case .failure(let error):
            return .failure(.invalidOpenFile(error))
        }
    }
}
