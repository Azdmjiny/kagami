import Foundation
import Security

protocol APIKeyStoring: Sendable {
    func load() -> String?
    func save(_ key: String) throws
}

struct APIKeyStore: APIKeyStoring {
    private let service = "com.kagami.translation-api"
    private let account = "default"

    func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if key.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(key.utf8)
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw KagamiError.configuration("无法将 API 密钥保存到钥匙串。")
            }
        } else if status != errSecSuccess {
            throw KagamiError.configuration("无法将 API 密钥保存到钥匙串。")
        }
    }
}
