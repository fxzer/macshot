import Foundation
import AppKit

enum UploadHistoryStore {

    private static let unifiedKey = "uploadHistory"
    private static let legacyImgbbKey = "imgbbUploads"

    // 保存上传历史，包含缩略图
    static func append(link: String, deleteURL: String = "", provider: String, thumbnail: NSImage? = nil) {
        var history = load()

        // 生成唯一 ID
        let id = UUID().uuidString

        // 保存缩略图到文件
        if let thumbnail = thumbnail {
            saveThumbnail(id: id, image: thumbnail)
        }

        history.append([
            "id": id,
            "provider": provider,
            "link": link,
            "deleteURL": deleteURL,
        ])
        UserDefaults.standard.set(history, forKey: unifiedKey)
    }

    static func load() -> [[String: String]] {
        let defaults = UserDefaults.standard

        if let unifiedHistory = defaults.array(forKey: unifiedKey) as? [[String: String]] {
            return unifiedHistory
        }

        guard let legacyHistory = defaults.array(forKey: legacyImgbbKey) as? [[String: String]] else {
            return []
        }

        let migratedHistory = legacyHistory.map { item in
            var migratedItem = item
            if migratedItem["provider"]?.isEmpty ?? true {
                migratedItem["provider"] = "imgbb"
            }
            return migratedItem
        }

        defaults.set(migratedHistory, forKey: unifiedKey)
        return migratedHistory
    }

    // 保存缩略图到文件
    private static func saveThumbnail(id: String, image: NSImage) {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let historyDir = appSupportURL.appendingPathComponent("com.fxzer.macshot/history")
        let thumbnailDir = historyDir.appendingPathComponent("thumbnails")

        // 确保目录存在
        try? fileManager.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)

        // 保存缩略图（调整为合适的大小）
        let thumbnail = resizeImage(image: image, maxSize: NSSize(width: 100, height: 100))
        let thumbnailURL = thumbnailDir.appendingPathComponent("\(id).jpg")

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }

        try? jpeg.write(to: thumbnailURL)
    }

    // 调整图片大小
    private static func resizeImage(image: NSImage, maxSize: NSSize) -> NSImage {
        let originalSize = image.size
        let ratio = min(maxSize.width / originalSize.width, maxSize.height / originalSize.height)
        let newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()

        return resizedImage
    }

    // 根据 ID 获取缩略图 URL
    static func getThumbnailURL(id: String) -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let historyDir = appSupportURL.appendingPathComponent("com.fxzer.macshot/history")
        let thumbnailDir = historyDir.appendingPathComponent("thumbnails")
        let thumbnailURL = thumbnailDir.appendingPathComponent("\(id).jpg")

        guard fileManager.fileExists(atPath: thumbnailURL.path) else {
            return nil
        }

        return thumbnailURL
    }
}
