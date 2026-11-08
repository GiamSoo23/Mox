import Foundation
import MoxCore
import Security

/// Keeps the Supabase settings in the login Keychain. They include the Mox
/// user's password, so they don't belong in UserDefaults or plain files
/// (PROTOCOL.md §1).
enum SettingsStore {
    private static let service = "com.mox.app.settings"
    private static let account = "default"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> MoxSettings? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(MoxSettings.self, from: data)
    }

    /// Replaces whatever was stored. Returns false if the Keychain refused.
    @discardableResult
    static func save(_ settings: MoxSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(settings) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        // Readable only while the Mac is unlocked, and never synced to other devices.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// The settings to use at launch. A complete `.env` wins (a developer
    /// override) and is copied into the Keychain, so builds without a
    /// `.env` keep working afterwards.
    static func resolve(fromEnv envSettings: MoxSettings?) -> MoxSettings? {
        if let envSettings {
            if load() != envSettings { save(envSettings) }
            return envSettings
        }
        return load()
    }
}
