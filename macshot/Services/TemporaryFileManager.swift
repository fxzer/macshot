import Foundation

enum TemporaryFileManager {

    private static let clipboardCurrentFileName = "macshot-clipboard-current.png"
    private static let legacyClipboardPrefix = "macshot-clipboard-"
    private static let genericMacshotPrefix = "macshot_"
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
            guard name.hasPrefix(genericMacshotPrefix) else { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let timestamp = values?.contentModificationDate ?? values?.creationDate ?? .distantFuture
            guard now.timeIntervalSince(timestamp) > staleMacshotFileLifetime else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func clipboardCurrentFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(clipboardCurrentFileName)
    }

    private static func temporaryFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
