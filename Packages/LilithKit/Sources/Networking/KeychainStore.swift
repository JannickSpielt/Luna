import Foundation
import Security

/// Speichert Zugangsdaten sicher im Schlüsselbund, getrennt pro Server und Nutzer.
///
/// Bevorzugt wird der moderne Schlüsselbund („Data Protection Keychain“). Er braucht auf dem Mac
/// eine Signatur mit Apple-Entwicklerkonto. Fehlt die (Fehler -34018), nimmt Lilith auf dem Mac
/// den klassischen Schlüsselbund, der ebenfalls verschlüsselt ist.
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "app.lilith.credentials") {
        self.service = service
    }

    private func basis(_ account: String, modern: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if modern { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    /// Reihenfolge der Versuche: auf iOS nur modern, auf dem Mac modern und dann klassisch.
    private var varianten: [Bool] {
        #if os(macOS)
        [true, false]
        #else
        [true]
        #endif
    }

    public func save(_ credential: Credential, account: String) throws {
        let data = try JSONEncoder().encode(credential)
        delete(account: account)
        var letzterStatus = errSecSuccess
        for modern in varianten {
            var query = basis(account, modern: modern)
            query[kSecValueData as String] = data
            // Nach dem ersten Entsperren lesbar, damit später auch Uploads im Hintergrund klappen.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            letzterStatus = SecItemAdd(query as CFDictionary, nil)
            if letzterStatus == errSecSuccess { return }
            if letzterStatus != errSecMissingEntitlement { break }
        }
        throw KeychainError(status: letzterStatus)
    }

    public func load(account: String) -> Credential? {
        for modern in varianten {
            var query = basis(account, modern: modern)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                return try? JSONDecoder().decode(Credential.self, from: data)
            }
        }
        return nil
    }

    public func delete(account: String) {
        for modern in varianten {
            SecItemDelete(basis(account, modern: modern) as CFDictionary)
        }
    }
}

public struct KeychainError: Error, Equatable, Sendable, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let grund = SecCopyErrorMessageString(status, nil) as String? ?? "unbekannt"
        return "Die Anmeldedaten konnten nicht sicher im Schlüsselbund gespeichert werden (\(status): \(grund))."
    }
}
