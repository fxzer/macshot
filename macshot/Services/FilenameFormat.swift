import Cocoa

/// Filename format configuration for customizable timestamp patterns
struct FilenameFormat: Codable, Equatable {
    /// Include year (4 digits: 2026)
    var includeYear: Bool = true
    /// Include month (2 digits: 04)
    var includeMonth: Bool = true
    /// Include day (2 digits: 13)
    var includeDay: Bool = true
    /// Include hour (2 digits: 18, 24-hour format)
    var includeHour: Bool = true
    /// Include minute (2 digits: 39)
    var includeMinute: Bool = true
    /// Include second (2 digits: 50)
    var includeSecond: Bool = true

    /// Default format with all components enabled
    static let `default` = FilenameFormat()

    /// Generate filename timestamp using the configured format
    /// - Parameter date: The date to format (defaults to now)
    /// - Returns: Formatted timestamp string (e.g., "2026-04-13-18-39-50" or "04-13-18-39")
    func formatTimestamp(_ date: Date = Date()) -> String {
        var components: [String] = []
        let calendar = Calendar.current
        let components_set = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        if includeYear {
            components.append(String(format: "%04d", components_set.year ?? 0))
        }
        if includeMonth {
            components.append(String(format: "%02d", components_set.month ?? 0))
        }
        if includeDay {
            components.append(String(format: "%02d", components_set.day ?? 0))
        }
        if includeHour {
            components.append(String(format: "%02d", components_set.hour ?? 0))
        }
        if includeMinute {
            components.append(String(format: "%02d", components_set.minute ?? 0))
        }
        if includeSecond {
            components.append(String(format: "%02d", components_set.second ?? 0))
        }

        return components.joined(separator: "-")
    }

    /// Get a preview string showing what the filename would look like
    var preview: String {
        "macshot-\(formatTimestamp()).png"
    }
}

// MARK: - UserDefaults Keys

extension FilenameFormat {
    private static let screenshotKey = "screenshotFilenameFormat"
    private static let recordingKey = "recordingFilenameFormat"

    /// Get the screenshot filename format from UserDefaults
    static var screenshotFormat: FilenameFormat {
        get {
            guard let data = UserDefaults.standard.data(forKey: screenshotKey),
                  let format = try? JSONDecoder().decode(FilenameFormat.self, from: data) else {
                return .default
            }
            return format
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: screenshotKey)
            }
        }
    }

    /// Get the recording filename format from UserDefaults
    static var recordingFormat: FilenameFormat {
        get {
            guard let data = UserDefaults.standard.data(forKey: recordingKey),
                  let format = try? JSONDecoder().decode(FilenameFormat.self, from: data) else {
                return .default
            }
            return format
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: recordingKey)
            }
        }
    }
}
