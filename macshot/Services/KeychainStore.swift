import Foundation
import Security

enum KeychainStore {

    private static let service = Bundle.main.bundleIdentifier ?? "com.fxzer.macshot.macshot"

    static func string(forKey key: String, legacyUserDefaultsKey: String? = nil) -> String? {
        guard let data = data(forKey: key, legacyUserDefaultsKey: legacyUserDefaultsKey),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func setString(_ value: String?, forKey key: String, legacyUserDefaultsKey: String? = nil) {
        if let value, !value.isEmpty {
            setData(Data(value.utf8), forKey: key)
        } else {
            deleteValue(forKey: key)
        }
        if let legacyUserDefaultsKey {
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
        }
    }

    static func data(forKey key: String, legacyUserDefaultsKey: String? = nil) -> Data? {
        if let existing = readValue(forKey: key) {
            return existing
        }

        guard let legacyUserDefaultsKey,
              let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey),
              !legacy.isEmpty else { return nil }

        let data = Data(legacy.utf8)
        setData(data, forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
        return data
    }

    static func setData(_ data: Data?, forKey key: String) {
        if let data {
            writeValue(data, forKey: key)
        } else {
            deleteValue(forKey: key)
        }
    }

    static func deleteValue(forKey key: String) {
        let query = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)
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

    private static func writeValue(_ data: Data, forKey key: String) {
        let query = baseQuery(forKey: key)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            for (k, v) in attrs {
                addQuery[k] = v
            }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
