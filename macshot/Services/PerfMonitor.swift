import Foundation

/// Performance monitoring helper.
///
/// Two modes:
/// 1. **Phased** — `PerfMonitor(label:)` for capture-flow pipeline tracing.
///    Logs every step with cumulative + delta time, always on.
/// 2. **Threshold** — `PerfMonitor(enabled:thresholdMs:)` for annotation drawing.
///    Only logs when exceeding the threshold; zero overhead when disabled.
struct PerfMonitor {

    // MARK: - Shared state

    let start: CFAbsoluteTime
    private var lastStep: CFAbsoluteTime
    private let label: String
    private let mode: Mode

    private enum Mode {
        case phased              // always-on, logs every step
        case threshold(ms: Double, enabled: Bool)  // conditional
    }

    // MARK: - Phased init (capture pipeline)

    /// Create an always-on phased timer for tracing a multi-step pipeline.
    /// Usage: `let p = PerfMonitor(label: "capture"); p.step("prewarm"); ...; p.finish()`
    init(label: String) {
        self.label = label
        self.mode = .phased
        self.start = CFAbsoluteTimeGetCurrent()
        self.lastStep = start
    }

    /// Log a named step. Prints cumulative time from start and delta from previous step.
    mutating func step(_ name: String) {
        let now = CFAbsoluteTimeGetCurrent()
        let totalMs = (now - start) * 1000
        let deltaMs = (now - lastStep) * 1000
        lastStep = now
        CaptureDiagnostics.log(
            "[macshot-perf][\(label)] \(name) total=\(String(format: "%.1f", totalMs))ms (+\(String(format: "%.1f", deltaMs))ms)"
        )
    }

    /// Log final summary with total elapsed time.
    mutating func finish() {
        let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        CaptureDiagnostics.log("[macshot-perf][\(label)] DONE total=\(String(format: "%.1f", totalMs))ms")
    }

    // MARK: - Threshold init (annotation tools)

    /// Create a threshold-based monitor for measuring slow operations.
    /// - Parameters:
    ///   - enabled: Whether monitoring is enabled (false = zero overhead)
    ///   - thresholdMs: Minimum milliseconds to log (default: 8ms)
    init(enabled: Bool, thresholdMs: Double = 8) {
        self.label = ""
        self.mode = .threshold(ms: thresholdMs, enabled: enabled)
        self.start = enabled ? CFAbsoluteTimeGetCurrent() : 0
        self.lastStep = start
    }

    /// Finish monitoring and log if the operation exceeded the threshold.
    func finish(
        tool: String,
        context: String,
        metadata: @autoclosure () -> String = ""
    ) {
        guard case .threshold(let ms, let enabled) = mode, enabled else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard elapsedMs >= ms else { return }
        let meta = metadata()
        NSLog("[macshot-perf][\(tool)] \(context) slow elapsed=\(String(format: "%.1f", elapsedMs))ms\(meta.isEmpty ? "" : " \(meta)")")
    }
}
