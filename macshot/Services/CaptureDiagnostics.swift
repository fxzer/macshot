import Foundation
import OSLog

enum CaptureDiagnostics {
    /// When absent, perf logging defaults to **on** (Release / DMG 也能在 Console 里看到分段耗时).
    /// `defaults write … capturePerfLoggingEnabled -bool false` 可关闭。
    static let enabledDefaultsKey = "capturePerfLoggingEnabled"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.fxzer.macshot.macshot",
        category: "capture-perf"
    )

    /// 环境变量优先于 UserDefaults：`MACSHOT_CAPTURE_PERF_LOGS=1` 强制开，`=0` 强制关。
    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment["MACSHOT_CAPTURE_PERF_LOGS"]
        if env == "0" { return false }
        if env == "1" { return true }
        if UserDefaults.standard.object(forKey: enabledDefaultsKey) != nil {
            return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
        }
        return true
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let resolved = message()
        logger.notice("\(resolved, privacy: .public)")
    }
}
