import Foundation
import Security
import LocalAuthentication

protocol APIKeyStoring: Sendable {
    func load() throws -> String?
    func containsKey() throws -> Bool
    func save(_ key: String) throws
}

/// Injectable Security boundary; tests never need access to a user's Keychain.
protocol KeychainAccess: Sendable {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

struct SystemKeychainAccess: KeychainAccess {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { SecItemUpdate(query, attributes) }
    func add(_ attributes: CFDictionary) -> OSStatus { SecItemAdd(attributes, nil) }
    func delete(_ query: CFDictionary) -> OSStatus { SecItemDelete(query) }
}

struct APIKeyStore: APIKeyStoring {
    var access: any KeychainAccess = SystemKeychainAccess()

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.kagami.translation-api",
         kSecAttrAccount as String: "default"]
    }

    func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = access.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        try check(status, operation: "读取")
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KagamiError.configuration("钥匙串中的 API 密钥格式无效，请在设置中重新保存。")
        }
        return key
    }

    func containsKey() throws -> Bool {
        var query = query
        // Metadata only. A status refresh must never request the secret or open a prompt.
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        let status = access.copyMatching(query as CFDictionary, result: nil)
        if status == errSecItemNotFound { return false }
        try check(status, operation: "查询")
        return true
    }

    func save(_ key: String) throws {
        if key.isEmpty {
            let status = access.delete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status, operation: "删除") }
            return
        }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = access.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(key.utf8)
            try check(access.add(insert as CFDictionary), operation: "保存")
        } else {
            try check(status, operation: "保存")
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status != errSecSuccess else { return }
        let reason: String
        switch status {
        case errSecUserCanceled: reason = "已取消钥匙串授权。请重试，并在系统提示中允许 Kagami 访问。"
        case errSecAuthFailed: reason = "钥匙串授权失败。请检查登录密码及此条目的访问权限。"
        case errSecInteractionNotAllowed: reason = "当前无法显示授权窗口，请解锁登录钥匙串后重试。"
        default: reason = (SecCopyErrorMessageString(status, nil) as String?) ?? "未知钥匙串错误。"
        }
        throw KagamiError.configuration("无法\(operation) API 密钥（钥匙串错误 \(status)）：\(reason)")
    }
}
