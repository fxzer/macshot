import Cocoa

enum FinderRevealService {
    @discardableResult
    static func reveal(_ url: URL) -> Bool {
        let targetURL = url.standardizedFileURL

        if targetURL.hasDirectoryPath {
            return NSWorkspace.shared.open(targetURL)
        }

        let filePath = targetURL.path
        let rootPath = targetURL.deletingLastPathComponent().path
        if NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: rootPath) {
            return true
        }

        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        return true
    }
}
