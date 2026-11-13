import Foundation
import Security

/// Das angemeldete Konto für Luna-Erweiterungen (z. B. „In Luna hochladen“ im Teilen-Menü).
///
/// Liegt im Schlüsselbund. Die App und ihre Erweiterungen teilen sich über „Keychain Sharing“
/// eine Zugriffsgruppe; sie ist in den Entitlements die erste und damit Standard für neue Einträge.
/// Ohne diese Fähigkeit (z. B. auf dem Mac) bleibt der Eintrag einfach bei der App.
public enum GeteiltesKonto {
    private static let dienst = "app.lilith.geteilt"
    private static let schluessel = "aktiv"

    private struct Inhalt: Codable {
        let account: Account
        let credential: Credential
    }

    private static func basis() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: schluessel,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Merkt sich das Konto für Erweiterungen. Fehler sind nicht schlimm: Dann fehlt nur das Teilen-Menü.
    public static func speichere(_ account: Account, credential: Credential) {
        guard let daten = try? JSONEncoder().encode(Inhalt(account: account, credential: credential)) else { return }
        if lade().map({ $0.0 == account && $0.1 == credential }) == true { return }
        loesche()
        var anfrage = basis()
        anfrage[kSecValueData as String] = daten
        // Nach dem ersten Entsperren lesbar, auch wenn die Erweiterung im Hintergrund startet.
        anfrage[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(anfrage as CFDictionary, nil)
    }

    public static func lade() -> (Account, Credential)? {
        var anfrage = basis()
        anfrage[kSecReturnData as String] = true
        anfrage[kSecMatchLimit as String] = kSecMatchLimitOne
        var ergebnis: AnyObject?
        guard SecItemCopyMatching(anfrage as CFDictionary, &ergebnis) == errSecSuccess,
              let daten = ergebnis as? Data,
              let inhalt = try? JSONDecoder().decode(Inhalt.self, from: daten) else { return nil }
        return (inhalt.account, inhalt.credential)
    }

    public static func loesche() {
        SecItemDelete(basis() as CFDictionary)
    }
}
