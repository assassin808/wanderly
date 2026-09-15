import Foundation
import Security
import WanderlyCore

/// AI 服务的 Key 存在钥匙串里，并通过 iCloud 钥匙串在自己的设备间同步。
enum APIKeyStore {
    private static func baseQuery(for provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.github.assassin808.wanderly.ai",
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func load(for provider: AIProvider) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var query = baseQuery(for: provider)
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    /// 编译时从 Config/Secrets.xcconfig 注入的 Gemini Key。
    static var bundledGeminiKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    /// 用户在设置里填的优先；Gemini 没填时用编译时注入的 Key。
    static func effectiveKey(for provider: AIProvider) -> String? {
        if let key = load(for: provider), !key.isEmpty { return key }
        return provider == .gemini ? bundledGeminiKey : nil
    }
}
