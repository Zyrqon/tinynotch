import Foundation
import Security

/// Небольшая обёртка над Связкой ключей для секретов приложения.
enum Keychain {
    private static let prefix = "dev.notchly.app."

    static func data(service: String, account: String) -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Есть ли запись — без чтения самого секрета, поэтому macOS не показывает запрос доступа.
    /// (Запрос блокирует вызывающий поток; на главном потоке остров бы замер, пока на него не ответят.)
    static func contains(service: String, account: String) -> Bool {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    @discardableResult
    static func set(_ data: Data, service: String, account: String) -> Bool {
        let query = baseQuery(service: service, account: account)
        let update: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess { return true }
        var add = query
        add[kSecValueData as String] = data
        // Только пока Mac разблокирован и только на этом Mac: секреты не уходят в iCloud и в бэкапы на другие устройства.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: prefix + service,
         kSecAttrAccount as String: account]
    }
}
