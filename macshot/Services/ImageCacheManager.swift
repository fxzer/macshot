import Foundation
import AppKit

/// 图片缓存管理器，用于优化内存使用和提升性能
@MainActor
class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let previewCache = NSCache<NSString, NSImage>()
    private let screenshotCache = NSCache<NSString, NSImage>()

    private init() {
        // 设置内存限制
        thumbnailCache.totalCostLimit = 10 * 1024 * 1024  // 10MB
        previewCache.totalCostLimit = 50 * 1024 * 1024   // 50MB
        screenshotCache.totalCostLimit = 30 * 1024 * 1024  // 30MB

        // 设置数量限制
        thumbnailCache.countLimit = 50
        previewCache.countLimit = 20
        screenshotCache.countLimit = 5

        // 监听内存警告
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

    // MARK: - 内存警告处理

    @objc private func handleMemoryWarning() {
        NSLog("[ImageCacheManager] Memory warning received, clearing caches")
        thumbnailCache.removeAllObjects()
        previewCache.removeAllObjects()
        // 保留screenshot缓存，因为可能正在使用
    }

    // MARK: - 缩略图缓存

    func storeThumbnail(_ image: NSImage, forKey key: String) {
        let cost = estimateImageCost(image)
        thumbnailCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func retrieveThumbnail(forKey key: String) -> NSImage? {
        return thumbnailCache.object(forKey: key as NSString)
    }

    // MARK: - 预览图缓存

    func storePreview(_ image: NSImage, forKey key: String) {
        let cost = estimateImageCost(image)
        previewCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func retrievePreview(forKey key: String) -> NSImage? {
        return previewCache.object(forKey: key as NSString)
    }

    // MARK: - 截图缓存

    func storeScreenshot(_ image: NSImage, forKey key: String) {
        let cost = estimateImageCost(image)
        screenshotCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func retrieveScreenshot(forKey key: String) -> NSImage? {
        return screenshotCache.object(forKey: key as NSString)
    }

    // MARK: - 通用方法

    func clearAllCaches() {
        thumbnailCache.removeAllObjects()
        previewCache.removeAllObjects()
        screenshotCache.removeAllObjects()
    }

    func clearThumbnailCache() {
        thumbnailCache.removeAllObjects()
    }

    func clearPreviewCache() {
        previewCache.removeAllObjects()
    }

    func clearScreenshotCache() {
        screenshotCache.removeAllObjects()
    }

    // MARK: - 辅助方法

    private func estimateImageCost(_ image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 1024 }
        let pixels = Int(rep.pixelsWide * rep.pixelsHigh)
        return pixels * 4  // RGBA = 4 bytes per pixel
    }

    // MARK: - 缓存统计

    func getCacheStats() -> (thumbnailCount: Int, previewCount: Int, screenshotCount: Int) {
        return (
            thumbnailCount: thumbnailCache.countLimit,
            previewCount: previewCache.countLimit,
            screenshotCount: screenshotCache.countLimit
        )
    }
}
