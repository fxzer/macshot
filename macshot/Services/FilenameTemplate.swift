import Foundation

enum FilenameOutputKind: String, CaseIterable, Identifiable {
    case screenshot
    case recording
    case gif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .screenshot:
            return "Screenshot"
        case .recording:
            return "Recording"
        case .gif:
            return "GIF"
        }
    }

    var localizedLabel: String {
        switch self {
        case .screenshot:
            return L("Screenshot")
        case .recording:
            return L("Recording")
        case .gif:
            return L("GIF")
        }
    }
}

struct FilenameTemplateContext {
    let kind: FilenameOutputKind
    let date: Date
    let prefix: String
    let shortCode: String

    init(kind: FilenameOutputKind, date: Date = Date(), prefix: String = "MacShot", shortCode: String? = nil) {
        self.kind = kind
        self.date = date
        self.prefix = prefix
        self.shortCode = shortCode ?? FilenameTemplateEngine.makeShortCode()
    }
}

enum FilenameTemplateEngine {
    static func makeFilename(
        format: TokenFilenameFormat = .sharedFormat,
        kind: FilenameOutputKind,
        fileExtension: String,
        date: Date = Date(),
        prefix: String = "MacShot"
    ) -> String {
        let context = FilenameTemplateContext(kind: kind, date: date, prefix: prefix)
        let baseName = makeBaseName(format: format, context: context)
        return "\(baseName).\(fileExtension)"
    }

    static func makeBaseName(
        format: TokenFilenameFormat = .sharedFormat,
        kind: FilenameOutputKind,
        date: Date = Date(),
        prefix: String = "MacShot"
    ) -> String {
        let context = FilenameTemplateContext(kind: kind, date: date, prefix: prefix)
        return makeBaseName(format: format, context: context)
    }

    static func uniqueDestinationURL(in directoryURL: URL, baseName: String, fileExtension: String) -> URL {
        let sanitizedExtension = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        var candidate = directoryURL.appendingPathComponent(baseName + sanitizedExtension)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(baseName) \(suffix)\(sanitizedExtension)")
            suffix += 1
        }

        return candidate
    }

    static func makeShortCode(length: Int = 4) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    private static func makeBaseName(format: TokenFilenameFormat, context: FilenameTemplateContext) -> String {
        let joined = format.tokens.map { token -> String in
            switch token {
            case .text(let string):
                return string
            case .prefix:
                return context.prefix
            case .kind:
                return context.kind.displayName
            case .date:
                return dateString(from: context.date)
            case .time:
                return timeString(from: context.date)
            case .timestamp:
                return timestampString(from: context.date)
            case .shortCode:
                return context.shortCode
            }
        }.joined()

        let cleaned = cleanup(joined)
        if cleaned.isEmpty {
            return fallbackBaseName(for: context)
        }
        return cleaned
    }

    private static func cleanup(_ string: String) -> String {
        var output = ""
        let invalidCharacterSet = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)

        for scalar in string.unicodeScalars {
            if invalidCharacterSet.contains(scalar) {
                output.append("_")
                continue
            }

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                output.append("_")
                continue
            }

            let character = Character(scalar)
            if character == "_" || character == "-" {
                output.append(character)
                continue
            }

            output.unicodeScalars.append(scalar)
        }

        return output
    }

    private static func fallbackBaseName(for context: FilenameTemplateContext) -> String {
        let date = dateString(from: context.date)
        let time = timeString(from: context.date)
        return "\(context.prefix)_\(context.kind.displayName)_\(date)_\(time)"
    }

    private static func makeDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private static func dateString(from date: Date) -> String {
        makeDateFormatter(format: "yyyy-MM-dd").string(from: date)
    }

    private static func timeString(from date: Date) -> String {
        makeDateFormatter(format: "HH-mm-ss").string(from: date)
    }

    private static func timestampString(from date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }
}
