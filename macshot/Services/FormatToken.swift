import Foundation

/// 文件名规则里的一个片段：要么是普通文本，要么是变量 token。
enum FormatToken: Codable, Hashable, Equatable {
    case text(String)
    case prefix
    case kind
    case date
    case time
    case timestamp
    case shortCode

    /// 控件里显示给用户看的名称。
    var label: String {
        switch self {
        case .text:
            return ""
        case .prefix:
            return L("Prefix")
        case .kind:
            return L("Type")
        case .date:
            return L("Date")
        case .time:
            return L("Time")
        case .timestamp:
            return L("Timestamp")
        case .shortCode:
            return L("Short code")
        }
    }

    /// 变量编码，用于序列化和在输入框中插入。
    var variableCode: String? {
        switch self {
        case .text:
            return nil
        case .prefix:
            return "%p"
        case .kind:
            return "%k"
        case .date:
            return "%d"
        case .time:
            return "%H"
        case .timestamp:
            return "%s"
        case .shortCode:
            return "%r"
        }
    }

    /// 变量池中的示例值。
    var sampleValue: String {
        switch self {
        case .text:
            return ""
        case .prefix:
            return "MacShot"
        case .kind:
            return "Screenshot"
        case .date:
            return "2026-04-13"
        case .time:
            return "15-30-00"
        case .timestamp:
            return "1712999400"
        case .shortCode:
            return "a8b3"
        }
    }

    /// 只有变量 token 才会出现在变量池里。
    static let allVariables: [FormatToken] = [.prefix, .kind, .date, .time, .timestamp, .shortCode]

    static func fromVariableCode(_ code: String) -> FormatToken? {
        switch code {
        case "%p":
            return .prefix
        case "%k":
            return .kind
        case "%d":
            return .date
        case "%H":
            return .time
        case "%s":
            return .timestamp
        case "%r":
            return .shortCode
        default:
            return nil
        }
    }
}

/// 共用的文件名模板。截图、录屏、GIF 都只用这一套规则。
struct TokenFilenameFormat: Codable, Equatable {
    var tokens: [FormatToken]

    static let `default` = TokenFilenameFormat(tokens: [
        .prefix,
        .text("_"),
        .kind,
        .text("_"),
        .date,
        .text("_"),
        .time
    ])

    static let sharedKey = "sharedTokenFormat"
    private static let migrationVersionKey = "sharedTokenFormatMigrationVersion"
    private static let currentMigrationVersion = 1
    private static let screenshotKey = "screenshotTokenFormat"
    private static let recordingKey = "recordingTokenFormat"
    private static let legacyScreenshotKey = "screenshotFilenameFormat"
    private static let legacyRecordingKey = "recordingFilenameFormat"

    /// 兼容旧调用方，实际已经收口到 sharedFormat。
    static var screenshotFormat: TokenFilenameFormat {
        get { sharedFormat }
        set { sharedFormat = newValue }
    }

    /// 兼容旧调用方，实际已经收口到 sharedFormat。
    static var recordingFormat: TokenFilenameFormat {
        get { sharedFormat }
        set { sharedFormat = newValue }
    }

    static var sharedFormat: TokenFilenameFormat {
        get {
            migrateIfNeeded()
            if let string = UserDefaults.standard.string(forKey: sharedKey) {
                return fromSerializedString(string)
            }
            return .default
        }
        set {
            UserDefaults.standard.set(newValue.serializedString, forKey: sharedKey)
            UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
        }
    }

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: migrationVersionKey) >= currentMigrationVersion,
           defaults.string(forKey: sharedKey) != nil {
            return
        }

        let migrated: TokenFilenameFormat
        if let screenshotString = defaults.string(forKey: screenshotKey), !screenshotString.isEmpty {
            migrated = fromLegacySerializedString(screenshotString)
        } else if let recordingString = defaults.string(forKey: recordingKey), !recordingString.isEmpty {
            migrated = fromLegacySerializedString(recordingString)
        } else if let legacy = legacyBooleanFormat(forKey: legacyScreenshotKey) ?? legacyBooleanFormat(forKey: legacyRecordingKey) {
            migrated = legacy
        } else {
            migrated = .default
        }

        defaults.set(migrated.serializedString, forKey: sharedKey)
        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    /// 序列化为 `%p_%k_%d_%H` 这样的字符串。
    var serializedString: String {
        tokens.map { token in
            switch token {
            case .text(let string):
                return string
            case .prefix:
                return "%p"
            case .kind:
                return "%k"
            case .date:
                return "%d"
            case .time:
                return "%H"
            case .timestamp:
                return "%s"
            case .shortCode:
                return "%r"
            }
        }.joined()
    }

    /// 从序列化字符串恢复规则。
    static func fromSerializedString(_ string: String) -> TokenFilenameFormat {
        let tokens = parseTokens(from: string)
        return TokenFilenameFormat(tokens: normalized(tokens))
    }

    /// 把旧规则中的不支持变量清理掉，再恢复成新模板。
    static func fromLegacySerializedString(_ string: String) -> TokenFilenameFormat {
        var migrated = string
        migrated = migrated.replacingOccurrences(
            of: "%y[\\-_ ]?%m[\\-_ ]?%d",
            with: "%d",
            options: .regularExpression
        )
        migrated = migrated.replacingOccurrences(
            of: "%H[\\-_ ]?%M[\\-_ ]?%S",
            with: "%H",
            options: .regularExpression
        )
        migrated = migrated.replacingOccurrences(of: "%a", with: "")
        migrated = migrated.replacingOccurrences(of: "%t", with: "")
        migrated = migrated.replacingOccurrences(of: "%y", with: "")
        migrated = migrated.replacingOccurrences(of: "%m", with: "")
        migrated = migrated.replacingOccurrences(of: "%M", with: "")
        migrated = migrated.replacingOccurrences(of: "%S", with: "")
        return fromSerializedString(migrated)
    }

    func preview(kind: FilenameOutputKind, fileExtension: String) -> String {
        FilenameTemplateEngine.makeFilename(
            format: self,
            kind: kind,
            fileExtension: fileExtension
        )
    }

    private static func parseTokens(from string: String) -> [FormatToken] {
        var tokens: [FormatToken] = []
        var currentText = ""
        var index = string.startIndex

        while index < string.endIndex {
            let character = string[index]
            let nextIndex = string.index(after: index)
            if character == "%", nextIndex < string.endIndex {
                let code = "%" + String(string[nextIndex])
                if let variable = FormatToken.fromVariableCode(code) {
                    if !currentText.isEmpty {
                        tokens.append(.text(currentText))
                        currentText = ""
                    }
                    tokens.append(variable)
                    index = string.index(after: nextIndex)
                    continue
                }
            }

            currentText.append(character)
            index = nextIndex
        }

        if !currentText.isEmpty {
            tokens.append(.text(currentText))
        }

        return tokens
    }

    private static func normalized(_ tokens: [FormatToken]) -> [FormatToken] {
        var normalizedTokens: [FormatToken] = []
        var pendingText = ""

        func flushText() {
            guard !pendingText.isEmpty else { return }
            normalizedTokens.append(.text(pendingText))
            pendingText = ""
        }

        for token in tokens {
            switch token {
            case .text(let string):
                pendingText += string
            default:
                flushText()
                normalizedTokens.append(token)
            }
        }

        flushText()
        return normalizedTokens.isEmpty ? TokenFilenameFormat.default.tokens : normalizedTokens
    }

    private static func legacyBooleanFormat(forKey key: String) -> TokenFilenameFormat? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let format = try? JSONDecoder().decode(FilenameFormat.self, from: data) else {
            return nil
        }

        var tokens: [FormatToken] = [.prefix]
        let hasDate = format.includeYear || format.includeMonth || format.includeDay
        let hasTime = format.includeHour || format.includeMinute || format.includeSecond

        if hasDate {
            tokens.append(.text("_"))
            tokens.append(.date)
        }
        if hasTime {
            tokens.append(.text("_"))
            tokens.append(.time)
        }

        return TokenFilenameFormat(tokens: normalized(tokens))
    }
}
