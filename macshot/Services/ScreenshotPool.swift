import Foundation
import AppKit

/// 截图池管理器，用于复用截图对象和优化内存使用
@MainActor
class ScreenshotPool {
    static let shared = ScreenshotPool()

    private var pool: [String: NSImage] = [:]
    private var accessTimes: [String: CFAbsoluteTime] = [:]
    private let maxPoolSize: Int = 3
    private let maxMemoryUsage: Int = 50 * 1024 * 1024  // 50MB
    private let maxAge: TimeInterval = 300  // 5分钟

    private init() {
        // 监听内存警告通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: NSNotification.Name("NSApplicationMemoryWarningNotification"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 公开方法

    func add(_ image: NSImage, key: String) {
        let cost = estimateImageCost(image)

        // 检查内存限制
        if currentMemoryUsage + cost > maxMemoryUsage {
            cleanupOldest()
        }

        // 检查池大小限制
        if pool.count >= maxPoolSize {
            cleanupOldest()
        }

        pool[key] = image
        accessTimes[key] = CFAbsoluteTimeGetCurrent()

        NSLog("[ScreenshotPool] Added screenshot with key: \(key), pool size: \(pool.count)")
    }

    func retrieve(forKey key: String) -> NSImage? {
        if let image = pool[key] {
            accessTimes[key] = CFAbsoluteTimeGetCurrent()
            return image
        }
        return nil
    }

    func remove(forKey key: String) {
        pool.removeValue(forKey: key)
        accessTimes.removeValue(forKey: key)
    }

    func clearAll() {
        pool.removeAll()
        accessTimes.removeAll()
    }

    // MARK: - 内存管理

    @objc private func handleMemoryWarning() {
        NSLog("[ScreenshotPool] Memory warning, clearing pool")
        clearAll()
    }

    private func cleanupOldest() {
        guard !accessTimes.isEmpty else { return }

        // 找到最旧的条目
        let oldestKey = accessTimes.min(by: { $0.value < $1.value })?.key
        if let key = oldestKey {
            remove(forKey: key)
            NSLog("[ScreenshotPool] Removed oldest screenshot: \(key)")
        }
    }

    private func cleanupExpired() {
        let now = CFAbsoluteTimeGetCurrent()
        let expiredKeys = accessTimes.filter { now - $1 > maxAge }.map { $0.key }

        for key in expiredKeys {
            remove(forKey: key)
        }

        if !expiredKeys.isEmpty {
            NSLog("[ScreenshotPool] Removed \(expiredKeys.count) expired screenshots")
        }
    }

    // MARK: - 辅助方法

    private var currentMemoryUsage: Int {
        pool.values.reduce(0) { $0 + estimateImageCost($1) }
    }

    private func estimateImageCost(_ image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 1024 }
        let pixels = Int(rep.pixelsWide * rep.pixelsHigh)
        return pixels * 4  // RGBA = 4 bytes per pixel
    }

    // MARK: - 统计信息

    func getStats() -> (count: Int, memoryUsage: Int) {
        return (count: pool.count, memoryUsage: currentMemoryUsage)
    }
}
