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
            // 自动迁移旧格式数据到新格式
            migrateIfNeeded(data: existing, forKey: key)
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

        // 创建访问控制：允许应用在解锁后访问，无需用户交互确认
        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleAfterFirstUnlock,
            [],  // 空标志 = 不需要用户在场确认
            nil
        )

        var attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if let accessControl {
            attrs[kSecAttrAccessControl as String] = accessControl
        }

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            for (k, v) in attrs {
                addQuery[k] = v
            }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    /// 迁移旧格式数据到新格式（添加访问控制）
    private static func migrateIfNeeded(data: Data, forKey key: String) {
        // 删除旧项
        let query = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)

        // 用新格式重新写入
        writeValue(data, forKey: key)
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
