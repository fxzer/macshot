import Foundation
import AppKit

/// 性能监控工具，用于测量和记录性能指标
class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    private var measurements: [String: CFAbsoluteTime] = [:]
    private var operationCounts: [String: Int] = [:]

    private init() {}

    // MARK: - 性能测量

    /// 开始测量操作耗时
    func startMeasuring(_ operation: String) {
        measurements[operation] = CFAbsoluteTimeGetCurrent()
    }

    /// 结束测量并记录耗时
    func endMeasuring(_ operation: String) -> TimeInterval? {
        guard let startTime = measurements[operation] else { return nil }
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        measurements.removeValue(forKey: operation)

        logPerformanceMetrics(operation, duration: duration)
        return duration
    }

    /// 测量操作的执行时间
    func measure<T>(_ operation: String, block: () -> T) -> T {
        startMeasuring(operation)
        let result = block()
        endMeasuring(operation)
        return result
    }

    /// 异步测量操作的执行时间
    func measureAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
        startMeasuring(operation)
        let result = try await block()
        endMeasuring(operation)
        return result
    }

    // MARK: - 操作计数

    /// 增加操作计数
    func incrementOperationCount(_ operation: String) {
        operationCounts[operation, default: 0] += 1
    }

    /// 获取操作计数
    func getOperationCount(_ operation: String) -> Int {
        return operationCounts[operation, default: 0]
    }

    /// 重置操作计数
    func resetOperationCount(_ operation: String) {
        operationCounts.removeValue(forKey: operation)
    }

    // MARK: - 内存使用

    /// 获取当前内存使用量（字节）
    func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    /// 获取格式化的内存使用量
    func getFormattedMemoryUsage() -> String {
        let bytes = getCurrentMemoryUsage()
        return formatBytes(bytes)
    }

    /// 格式化字节数为可读字符串
    func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.2f KB", kb)
        } else {
            return "\(bytes) bytes"
        }
    }

    // MARK: - 日志记录

    private func logPerformanceMetrics(_ operation: String, duration: TimeInterval) {
        let ms = duration * 1000
        NSLog("[Performance] \(operation) took \(String(format: "%.2f", ms))ms")

        // 如果操作耗时过长，发出警告
        if duration > 0.1 {  // 100ms
            NSLog("[Performance] WARNING: \(operation) took longer than 100ms")
        }
    }

    // MARK: - 性能报告

    /// 生成性能报告摘要
    func generatePerformanceReport() -> String {
        var report = "=== Performance Report ===\n"
        report += "Current Memory Usage: \(getFormattedMemoryUsage())\n"
        report += "Operation Counts:\n"

        for (operation, count) in operationCounts.sorted(by: { $0.key < $1.key }) {
            report += "  \(operation): \(count)\n"
        }

        return report
    }
}

/// 性能测量作用域，用于自动测量代码块的执行时间
class PerformanceMeasurement {
    private let operation: String
    private let startTime: CFAbsoluteTime

    init(operation: String) {
        self.operation = operation
        self.startTime = CFAbsoluteTimeGetCurrent()
    }

    deinit {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let ms = duration * 1000
        NSLog("[Performance] \(operation) took \(String(format: "%.2f", ms))ms")
    }
}

/// 便利函数：使用闭包进行性能测量
func measurePerformance<T>(_ operation: String, block: () -> T) -> T {
    return PerformanceMonitor.shared.measure(operation, block: block)
}

/// 便利函数：异步性能测量
func measurePerformanceAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
    return try await PerformanceMonitor.shared.measureAsync(operation, block: block)
}
