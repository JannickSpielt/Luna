import Foundation
import Security

/// Speichert Zugangsdaten sicher im Schlüsselbund, getrennt pro Server und Nutzer.
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "app.lilith.credentials") {
        self.service = service
    }

    public func save(_ credential: Credential, account: String) throws {
        let data = try JSONEncoder().encode(credential)
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Nach dem ersten Entsperren lesbar, damit später auch Uploads im Hintergrund klappen.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func load(account: String) -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    public func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public struct KeychainError: Error, Equatable, Sendable, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let grund = SecCopyErrorMessageString(status, nil) as String? ?? "unbekannt"
        return "Die Anmeldedaten konnten nicht sicher im Schlüsselbund gespeichert werden (\(status): \(grund))."
    }
}
