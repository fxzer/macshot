//
//  PerfMonitor.swift
//  macshot
//
//  Performance monitoring utility for measuring annotation drawing time.
//

import Foundation

/// Performance monitoring helper for measuring and logging slow operations.
struct PerfMonitor {
    private let start: CFAbsoluteTime
    private let isEnabled: Bool
    private let thresholdMs: Double

    /// Create a performance monitor.
    /// - Parameters:
    ///   - enabled: Whether monitoring is enabled (false = zero overhead)
    ///   - thresholdMs: Minimum milliseconds to log (default: 8ms)
    init(enabled: Bool, thresholdMs: Double = 8) {
        self.isEnabled = enabled
        self.thresholdMs = thresholdMs
        self.start = enabled ? CFAbsoluteTimeGetCurrent() : 0
    }

    /// Finish monitoring and log if the operation exceeded the threshold.
    /// - Parameters:
    ///   - tool: Tool name (e.g., "Marker")
    ///   - context: Operation context (e.g., "live draw", "append cache")
    ///   - metadata: Additional info to log (lazily evaluated)
    func finish(
        tool: String,
        context: String,
        metadata: @autoclosure () -> String = ""
    ) {
        guard isEnabled else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard elapsedMs >= thresholdMs else { return }
        let meta = metadata()
        NSLog("[PERF][\(tool)] \(context) slow elapsed=\(String(format: "%.1f", elapsedMs))ms\(meta.isEmpty ? "" : " \(meta)")")
    }
}
