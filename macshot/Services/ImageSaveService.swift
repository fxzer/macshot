//
//  ImageSaveService.swift
//  macshot
//
//  统一的图片保存服务，消除重复代码
//

import AppKit

enum ImageSaveService {

    // MARK: - Error Types

    enum SaveError: LocalizedError {
        case encodingFailed
        case directoryCreationFailed(Error)
        case writeFailed(Error)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode image"
            case .directoryCreationFailed(let error):
                return "Failed to create save directory: \(error.localizedDescription)"
            case .writeFailed(let error):
                return "Failed to write image: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sync Save

    /// 同步保存图片到默认目录
    /// - Parameters:
    ///   - image: 要保存的图片
    ///   - kind: 文件名类型（截图、录制等）
    /// - Returns: 保存结果，成功时返回文件 URL
    static func saveToDefaultDirectory(
        _ image: NSImage,
        kind: FilenameOutputKind = .screenshot
    ) -> Result<URL, Error> {
        let dirURL = SaveDirectoryAccess.resolve()
        defer { SaveDirectoryAccess.stopAccessing(url: dirURL) }
        return save(image, in: dirURL, kind: kind)
    }

    /// 保存图片到指定目录，文件名使用统一模板生成
    static func save(
        _ image: NSImage,
        in directoryURL: URL,
        kind: FilenameOutputKind = .screenshot
    ) -> Result<URL, Error> {
        let baseName = FilenameTemplateEngine.makeBaseName(kind: kind)
        let fileURL = FilenameTemplateEngine.uniqueDestinationURL(
            in: directoryURL,
            baseName: baseName,
            fileExtension: ImageEncoder.fileExtension
        )
        return save(image, to: fileURL)
    }

    /// 保存图片到指定文件路径，必要时递归创建父目录
    static func save(_ image: NSImage, to fileURL: URL) -> Result<URL, Error> {
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(SaveError.directoryCreationFailed(error))
        }

        guard let imageData = ImageEncoder.encode(image) else {
            return .failure(SaveError.encodingFailed)
        }

        do {
            try imageData.write(to: fileURL, options: .atomic)
            return .success(fileURL)
        } catch {
            return .failure(SaveError.writeFailed(error))
        }
    }

    // MARK: - Async Save

    /// 异步保存图片到默认目录
    /// - Parameters:
    ///   - image: 要保存的图片
    ///   - kind: 文件名类型（截图、录制等）
    ///   - completion: 完成回调，在主线程执行
    static func saveToDefaultDirectoryAsync(
        _ image: NSImage,
        kind: FilenameOutputKind = .screenshot,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = saveToDefaultDirectory(image, kind: kind)
            Task { @MainActor in
                completion(result)
            }
        }
    }
}
