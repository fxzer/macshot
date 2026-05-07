import Foundation

enum TemporaryFileManager {

    private static let clipboardCurrentFileName = "macshot-clipboard-current.png"
    private static let legacyClipboardPrefix = "macshot-clipboard-"
    private static let genericMacshotPrefix = "macshot_"
    private static let shareFilePrefix = "macshot-share-"
    private static let recordingFilePrefix = "macshot-recording-"
    private static let staleMacshotFileLifetime: TimeInterval = 24 * 60 * 60

    static func cleanupOnLaunch(now: Date = Date()) {
        cleanupLegacyClipboardFiles()
        cleanupStaleMacshotFiles(now: now)
    }

    static func writeClipboardImageData(_ data: Data) -> URL? {
        cleanupLegacyClipboardFiles()

        let url = clipboardCurrentFileURL()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func writeDragImageData(_ data: Data, fileExtension: String) -> URL? {
        cleanupStaleMacshotFiles(now: Date())

        return writeManagedImageData(data, prefix: genericMacshotPrefix, fileExtension: fileExtension)
    }

    static func writeShareImageData(_ data: Data, fileExtension: String) -> URL? {
        cleanupStaleMacshotFiles(now: Date())
        guard let url = writeManagedImageData(data, prefix: shareFilePrefix, fileExtension: fileExtension) else {
            return nil
        }
        scheduleCleanup(at: url, after: 10 * 60)
        return url
    }

    static func makeRecordingOutputURL(fileExtension: String, baseName: String) -> URL {
        cleanupStaleMacshotFiles(now: Date())
        let sanitizedExtension = sanitizeFileExtension(fileExtension)
        let sanitizedBaseName = sanitizeBaseName(baseName)
        let filename = sanitizedBaseName.isEmpty
            ? "\(recordingFilePrefix)\(UUID().uuidString)\(sanitizedExtension)"
            : "\(recordingFilePrefix)\(sanitizedBaseName)\(sanitizedExtension)"
        return uniqueTemporaryURL(for: filename)
    }

    static func removeTemporaryFile(at url: URL) {
        guard isManagedTemporaryFile(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func isManagedTemporaryFile(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let tempDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent() == tempDirectory else {
            return false
        }
        return isManagedTemporaryFileName(standardizedURL.lastPathComponent)
    }

    private static func cleanupLegacyClipboardFiles() {
        for url in temporaryFiles() {
            let name = url.lastPathComponent
            guard name.hasPrefix(legacyClipboardPrefix),
                  name != clipboardCurrentFileName else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func cleanupStaleMacshotFiles(now: Date) {
        for url in temporaryFiles() {
            let name = url.lastPathComponent
            guard isManagedTemporaryFileName(name) else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let timestamp = values?.contentModificationDate ?? values?.creationDate ?? .distantFuture
            guard now.timeIntervalSince(timestamp) > staleMacshotFileLifetime else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func clipboardCurrentFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(clipboardCurrentFileName)
    }

    private static func writeManagedImageData(_ data: Data, prefix: String, fileExtension: String) -> URL? {
        let sanitizedExtension = sanitizeFileExtension(fileExtension)
        let url = uniqueTemporaryURL(for: "\(prefix)\(UUID().uuidString)\(sanitizedExtension)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func sanitizeFileExtension(_ fileExtension: String) -> String {
        let sanitizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizedExtension.isEmpty ? "" : ".\(sanitizedExtension)"
    }

    private static func sanitizeBaseName(_ baseName: String) -> String {
        let invalidCharacterSet = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let scalarView = baseName.unicodeScalars.map { scalar -> Character in
            if invalidCharacterSet.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return "-"
            }
            return Character(scalar)
        }
        let raw = String(scalarView)
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }

    private static func uniqueTemporaryURL(for filename: String) -> URL {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let directory = baseURL.deletingLastPathComponent()
        let ext = baseURL.pathExtension
        let stem = ext.isEmpty ? baseURL.lastPathComponent : baseURL.deletingPathExtension().lastPathComponent
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var attempt = 2
        var candidate = directory.appendingPathComponent("\(stem)-\(attempt)\(suffix)")
        while FileManager.default.fileExists(atPath: candidate.path) {
            attempt += 1
            candidate = directory.appendingPathComponent("\(stem)-\(attempt)\(suffix)")
        }
        return candidate
    }

    private static func scheduleCleanup(at url: URL, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            removeTemporaryFile(at: url)
        }
    }

    private static func isManagedTemporaryFileName(_ name: String) -> Bool {
        name.hasPrefix(genericMacshotPrefix)
            || name.hasPrefix(shareFilePrefix)
            || name.hasPrefix(recordingFilePrefix)
    }

    private static func temporaryFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
