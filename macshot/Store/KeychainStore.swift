import Foundation
import Security

enum KeychainStore {

    private static let service = Bundle.main.bundleIdentifier ?? "com.fxzer.macshot.macshot"

    // Legacy UserDefaults key prefix for Data fallback (used for non-string data like JSON tokens)
    private static let userDefaultsDataPrefix = "_data_"

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
        if let existing = readValue(forKey: key) {
            return existing
        }

        // Try legacy string UserDefaults key
        if let legacyUserDefaultsKey,
           let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey),
           !legacy.isEmpty {
            let data = Data(legacy.utf8)
            if setData(data, forKey: key) {
                UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            }
            return data
        }

        // Try fallback UserDefaults Data key (base64 encoded)
        let fallbackKey = userDefaultsDataPrefix + key
        if let fallbackBase64 = UserDefaults.standard.string(forKey: fallbackKey),
           !fallbackBase64.isEmpty,
           let fallbackData = Data(base64Encoded: fallbackBase64) {
            // Try to migrate back to Keychain
            if setData(fallbackData, forKey: key) {
                UserDefaults.standard.removeObject(forKey: fallbackKey)
            }
            return fallbackData
        }

        return nil
    }

    @discardableResult
    static func setData(_ data: Data?, forKey key: String) -> Bool {
        let didPersist: Bool
        if let data {
            didPersist = writeValue(data, forKey: key)
        } else {
            didPersist = deleteValue(forKey: key)
        }

        // Fallback to UserDefaults if Keychain write failed
        if !didPersist, let data {
            let fallbackKey = userDefaultsDataPrefix + key
            UserDefaults.standard.set(data.base64EncodedString(), forKey: fallbackKey)
        } else if didPersist {
            // Clean up UserDefaults fallback if Keychain succeeded
            let fallbackKey = userDefaultsDataPrefix + key
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        }

        return didPersist
    }

    @discardableResult
    static func deleteValue(forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func readValue(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeValue(_ data: Data, forKey key: String) -> Bool {
        let query = baseQuery(forKey: key)

        // 创建访问控制：允许应用在解锁后访问，无需用户交互确认
        // 注意：使用 kSecAttrAccessControl 时，不能再设置 kSecAttrAccessible
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlock,
            [],  // 空标志 = 不需要用户在场确认
            nil
        )

        let attrs: [String: Any]
        if let accessControl {
            attrs = [
                kSecValueData as String: data,
                kSecAttrAccessControl as String: accessControl,
            ]
        } else {
            // Fallback 如果无法创建 accessControl
            attrs = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
        }

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            let deleteStatus = SecItemDelete(query as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                return false
            }
        }

        var addQuery = query
        for (k, v) in attrs {
            addQuery[k] = v
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
