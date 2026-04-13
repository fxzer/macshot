import Foundation

enum UploadHistoryStore {

    private static let unifiedKey = "uploadHistory"
    private static let legacyImgbbKey = "imgbbUploads"

    static func append(link: String, deleteURL: String = "", provider: String) {
        var history = load()
        history.append([
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
}
