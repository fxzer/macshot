import AppKit

enum BeautifyBackgroundStore {
    private static let fileManager = FileManager.default
    private static let legacyDataKey = "beautifyCustomBgImageData"
    private static let appSupportFolder = "com.fxzer.macshot"
    private static let relativeDirectory = "beautify"
    private static let fileName = "custom-background.png"

    static func hasCustomBackground() -> Bool {
        if loadImageFromFile(at: backgroundFileURL) != nil {
            return true
        }
        guard
            let legacyData = UserDefaults.standard.data(forKey: legacyDataKey),
            let image = NSImage(data: legacyData)
        else {
            return false
        }
        return image.isValid && image.size.width > 0 && image.size.height > 0
    }

    static func loadImage() -> NSImage? {
        if let image = loadImageFromFile(at: backgroundFileURL) {
            return image
        }

        guard
            let legacyData = UserDefaults.standard.data(forKey: legacyDataKey),
            let image = NSImage(data: legacyData)
        else {
            return nil
        }

        migrateLegacyDataToFile(using: legacyData)
        return image
    }

    @discardableResult
    static func saveImage(_ image: NSImage) -> Bool {
        guard let data = pngData(for: image) else { return false }
        return savePNGData(data)
    }

    static func removeImage() {
        try? fileManager.removeItem(at: backgroundFileURL)
        UserDefaults.standard.removeObject(forKey: legacyDataKey)
    }

    private static var backgroundFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent(appSupportFolder, isDirectory: true)
            .appendingPathComponent(relativeDirectory, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func ensureDirectoryExists() -> Bool {
        let directoryURL = backgroundFileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            return true
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
            return true
        } catch {
            return false
        }
    }

    private static func loadImageFromFile(at url: URL) -> NSImage? {
        guard
            fileManager.fileExists(atPath: url.path),
            let image = NSImage(contentsOf: url),
            image.isValid,
            image.size.width > 0,
            image.size.height > 0
        else {
            return nil
        }
        return image
    }

    private static func migrateLegacyDataToFile(using legacyData: Data) {
        _ = savePNGData(legacyData)
    }

    @discardableResult
    private static func savePNGData(_ data: Data) -> Bool {
        guard ensureDirectoryExists() else {
            UserDefaults.standard.set(data, forKey: legacyDataKey)
            return false
        }

        do {
            try data.write(to: backgroundFileURL, options: .atomic)
            UserDefaults.standard.removeObject(forKey: legacyDataKey)
            return true
        } catch {
            UserDefaults.standard.set(data, forKey: legacyDataKey)
            return false
        }
    }

    private static func pngData(for image: NSImage) -> Data? {
        // Use the shared ImageEncoder path — avoids the NSImage→TIFF→
        // NSBitmapImageRep round-trip and keeps a single encode codepath.
        ImageEncoder.encodePNG(image)
    }
}
