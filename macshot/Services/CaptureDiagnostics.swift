import Foundation
import OSLog

enum CaptureDiagnostics {
    static let enabledDefaultsKey = "capturePerfLoggingEnabled"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.fxzer.macshot.macshot",
        category: "capture-perf"
    )

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["MACSHOT_CAPTURE_PERF_LOGS"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let resolved = message()
        logger.notice("\(resolved, privacy: .public)")
    }
}
