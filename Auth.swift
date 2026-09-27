import Foundation

/// Учётные данные, которые веб-клиент MAX держит в localStorage:
///   __oneme_auth      → {"viewerId": <int>, "token": "..."}
///   __oneme_device_id → "<uuid>"
struct Auth: Codable, Equatable {
    var viewerId: Int64
    var token: String
    var deviceId: String
}

/// Токен — учётные данные, поэтому Keychain, а не UserDefaults.
enum Keychain {
    private static let service = "org.netrender.litemax"
    private static let account = "auth"

    static func save(_ auth: Auth) {
        guard let data = try? JSONEncoder().encode(auth) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Auth? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Auth.self, from: data)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
