import AppKit
import WebP

enum ImageFileLoader {
    enum LoadError: LocalizedError {
        case missingFile
        case notRegularFile
        case unsupportedType(String)
        case fileTooLarge(Int)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return L("The selected image file no longer exists.")
            case .notRegularFile:
                return L("The selected path is not a regular image file.")
            case .unsupportedType(let name):
                return String(format: L("Unsupported image type: %@"), name)
            case .fileTooLarge(let maxMB):
                return String(format: L("Image is too large to open safely (%d MB max)."), maxMB)
            case .unreadable(let name):
                return String(format: L("Failed to open image: %@"), name)
            }
        }
    }

    static let maxOpenFileSizeBytes = 512 * 1024 * 1024
    private static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic", "heif", "webp", "icns"
    ]

    static func isSupportedImageURL(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func validatedImageFileURL(for url: URL) -> Result<URL, LoadError> {
        let fileURL = url.standardizedFileURL
        guard fileURL.isFileURL else { return .failure(.missingFile) }
        guard isSupportedImageURL(fileURL) else {
            return .failure(.unsupportedType(fileURL.pathExtension.isEmpty ? fileURL.lastPathComponent : fileURL.pathExtension))
        }

        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return .failure(.notRegularFile) }
            if let fileSize = values.fileSize, fileSize > maxOpenFileSizeBytes {
                return .failure(.fileTooLarge(maxOpenFileSizeBytes / 1024 / 1024))
            }
            return .success(fileURL)
        } catch {
            return .failure(.missingFile)
        }
    }

    static func loadImage(from url: URL) -> Result<NSImage, LoadError> {
        switch validatedImageFileURL(for: url) {
        case .failure(let error):
            return .failure(error)
        case .success(let fileURL):
            if fileURL.pathExtension.lowercased() == "webp" {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let image = try WebPDecoder().decode(toNSImage: data, options: WebPDecoderOptions())
                    guard image.isValid, image.size.width > 0, image.size.height > 0 else {
                        return .failure(.unreadable(fileURL.lastPathComponent))
                    }
                    return .success(image)
                } catch {
                    return .failure(.unreadable(fileURL.lastPathComponent))
                }
            }

            guard let image = NSImage(contentsOf: fileURL),
                  image.isValid,
                  image.size.width > 0,
                  image.size.height > 0 else {
                return .failure(.unreadable(fileURL.lastPathComponent))
            }
            return .success(image)
        }
    }
}
