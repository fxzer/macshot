import Foundation

enum KeychainStore {

    // Legacy UserDefaults key prefix for Data fallback (used for non-string data like JSON tokens)
    private static let userDefaultsDataPrefix = "_data_"
    private static let lock = NSLock()
    private static let storageFileName = "secrets.json"

    static func string(forKey key: String, legacyUserDefaultsKey: String? = nil) -> String? {
        guard let data = data(forKey: key, legacyUserDefaultsKey: legacyUserDefaultsKey),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func setString(_ value: String?, forKey key: String, legacyUserDefaultsKey: String? = nil) -> Bool {
        let didPersist: Bool
        if let value, !value.isEmpty {
            didPersist = setData(Data(value.utf8), forKey: key)
        } else {
            didPersist = deleteValue(forKey: key)
        }
        if let legacyUserDefaultsKey {
            if let value, !value.isEmpty, !didPersist {
                UserDefaults.standard.set(value, forKey: legacyUserDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            }
        }
        return didPersist
    }

    static func data(forKey key: String, legacyUserDefaultsKey: String? = nil) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        var store = loadStore()
        if let encoded = store[key], let existing = Data(base64Encoded: encoded) {
            return existing
        }

        // Try legacy string UserDefaults key
        if let legacyUserDefaultsKey,
           let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey),
           !legacy.isEmpty {
            let data = Data(legacy.utf8)
            if writeValue(data, forKey: key, in: &store) {
                UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            }
            return data
        }

        // Try fallback UserDefaults Data key (base64 encoded)
        let fallbackKey = userDefaultsDataPrefix + key
        if let fallbackBase64 = UserDefaults.standard.string(forKey: fallbackKey),
           !fallbackBase64.isEmpty,
           let fallbackData = Data(base64Encoded: fallbackBase64) {
            if writeValue(fallbackData, forKey: key, in: &store) {
                UserDefaults.standard.removeObject(forKey: fallbackKey)
            }
            return fallbackData
        }

        return nil
    }

    @discardableResult
    static func setData(_ data: Data?, forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let didPersist: Bool
        var store = loadStore()
        if let data {
            didPersist = writeValue(data, forKey: key, in: &store)
        } else {
            didPersist = deleteValue(forKey: key, in: &store)
        }

        // Fallback to UserDefaults if file write failed.
        if !didPersist, let data {
            let fallbackKey = userDefaultsDataPrefix + key
            UserDefaults.standard.set(data.base64EncodedString(), forKey: fallbackKey)
        } else if didPersist {
            // Clean up UserDefaults fallback if file storage succeeded.
            let fallbackKey = userDefaultsDataPrefix + key
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        }

        return didPersist
    }

    @discardableResult
    static func deleteValue(forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var store = loadStore()
        return deleteValue(forKey: key, in: &store)
    }

    private static func writeValue(_ data: Data, forKey key: String, in store: inout [String: String]) -> Bool {
        store[key] = data.base64EncodedString()
        return saveStore(store)
    }

    private static func deleteValue(forKey key: String, in store: inout [String: String]) -> Bool {
        store.removeValue(forKey: key)
        return saveStore(store)
    }

    private static func loadStore() -> [String: String] {
        guard let data = try? Data(contentsOf: storageURL),
              let store = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return store
    }

    private static func saveStore(_ store: [String: String]) -> Bool {
        do {
            let dir = storageURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            let data = try JSONEncoder().encode(store)
            try data.write(to: storageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
            return true
        } catch {
            return false
        }
    }

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.fxzer.macshot"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(storageFileName)
    }
}
