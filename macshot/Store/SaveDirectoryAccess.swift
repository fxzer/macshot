import Foundation

extension Notification.Name {
    static let saveDirectoryDidChange = Notification.Name("saveDirectoryDidChange")
}

/// Manages security-scoped bookmark access for the user-chosen save directory.
/// In sandbox mode, a raw file path is not enough — we need a bookmark that the
/// system can resolve to regrant access across app launches.
enum SaveDirectoryAccess {

    private static let bookmarkKey = "saveDirectoryBookmark"
    private static let pathKey = "saveDirectory"

    enum ResolveError: LocalizedError {
        case folderMovedOrRenamed
        case folderMissing
        case pathIsNotDirectory
        case bookmarkInvalid

        var errorDescription: String? {
            switch self {
            case .folderMovedOrRenamed:
                return L("Save folder missing. Please reselect it in Preferences.")
            case .folderMissing:
                return L("Save folder missing. Please reselect it in Preferences.")
            case .pathIsNotDirectory:
                return L("Save folder missing. Please reselect it in Preferences.")
            case .bookmarkInvalid:
                return L("Save folder missing. Please reselect it in Preferences.")
            }
        }
    }

    /// Save both the path (for display) and the security-scoped bookmark (for sandbox access).
    static func save(url: URL) {
        UserDefaults.standard.set(url.path, forKey: pathKey)
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                  includingResourceValuesForKeys: nil,
                                                  relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
        NotificationCenter.default.post(name: .saveDirectoryDidChange, object: nil)
    }

    /// Resolve the save directory URL and start sandbox-scoped access.
    /// Caller **must** call `stopAccessing(url:)` when done writing.
    static func resolve() -> URL {
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData,
                                   options: .withSecurityScope,
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &isStale) {
                if isStale {
                    if let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil,
                                                          relativeTo: nil) {
                        UserDefaults.standard.set(fresh, forKey: bookmarkKey)
                    }
                }
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        if let path = UserDefaults.standard.string(forKey: pathKey) {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Resolve the preferred screenshot directory for writing.
    /// - Important: On success, caller must call `stopAccessing(url:)`.
    static func resolveForWriting() -> Result<URL, Error> {
        let fileManager = FileManager.default
        let storedPath = UserDefaults.standard.string(forKey: pathKey)

        func ensureDirectoryExists(at url: URL) -> Result<URL, Error> {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? .success(url) : .failure(ResolveError.pathIsNotDirectory)
            }
            return .failure(ResolveError.folderMissing)
        }

        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return .failure(ResolveError.bookmarkInvalid)
            }

            if isStale,
               let fresh = try? url.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }

            let started = url.startAccessingSecurityScopedResource()
            if let storedPath, !storedPath.isEmpty, url.path != storedPath {
                if started { url.stopAccessingSecurityScopedResource() }
                return .failure(ResolveError.folderMovedOrRenamed)
            }

            switch ensureDirectoryExists(at: url) {
            case .success:
                return .success(url)
            case .failure(let error):
                if started { url.stopAccessingSecurityScopedResource() }
                return .failure(error)
            }
        }

        if let storedPath, !storedPath.isEmpty {
            return ensureDirectoryExists(at: URL(fileURLWithPath: storedPath))
        }

        let fallback = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return ensureDirectoryExists(at: fallback)
    }

    /// Resolve the directory URL **without** starting scoped access.
    /// Use this for NSSavePanel/NSOpenPanel `directoryURL` hints — they handle
    /// their own sandbox access via powerbox.
    static func directoryHint() -> URL? {
        if let path = UserDefaults.standard.string(forKey: pathKey) {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
    }

    /// Stop accessing the security-scoped resource after writing is complete.
    static func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// The display path for the settings UI.
    static var displayPath: String {
        UserDefaults.standard.string(forKey: pathKey) ?? "~/Pictures"
    }
}
