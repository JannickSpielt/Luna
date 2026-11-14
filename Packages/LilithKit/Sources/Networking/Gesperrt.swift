import Foundation
import LocalAuthentication
import ImmichAPI
import OpenAPIRuntime
import Security

/// Stand des gesperrten Bereichs (Immich „Locked Folder“).
public struct SperrStatus: Sendable, Equatable {
    /// Auf dem Server ist eine PIN eingerichtet.
    public let hatPin: Bool
    /// Die Sitzung ist gerade entsperrt (gesperrte Fotos sind sichtbar).
    public let entsperrt: Bool
}

extension ImmichClient {
    public func sperrStatus() async throws -> SperrStatus {
        let output: Operations.GetAuthStatus.Output
        do { output = try await client.getAuthStatus() } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            let s = try await rufe { try ok.body.json }
            return SperrStatus(hatPin: s.pinCode, entsperrt: s.isElevated)
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Richtet die PIN für den gesperrten Bereich ein (nur wenn noch keine existiert).
    public func richtePinEin(_ pin: String) async throws {
        let output: Operations.SetupPinCode.Output
        do { output = try await client.setupPinCode(body: .json(.init(pinCode: pin))) } catch { throw Self.uebersetze(error) }
        switch output {
        case .noContent: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Entsperrt die Sitzung mit der PIN. Falsche PIN: `ImmichError.unerwarteteAntwort(400 oder 401)`.
    public func entsperre(pin: String) async throws {
        let output: Operations.UnlockAuthSession.Output
        do { output = try await client.unlockAuthSession(body: .json(.init(pinCode: pin))) } catch { throw Self.uebersetze(error) }
        switch output {
        case .noContent: return
        case .undocumented(let code, _): throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Sperrt die Sitzung wieder (gesperrte Fotos sind dann nicht mehr abrufbar).
    public func sperreSitzung() async {
        _ = try? await client.lockAuthSession()
    }

    /// Fotos in den gesperrten Bereich verschieben (`true`) oder zurück in die Timeline (`false`).
    public func verschiebe(assetIds: [String], gesperrt: Bool) async throws {
        guard !assetIds.isEmpty else { return }
        let output: Operations.UpdateAssets.Output
        do {
            output = try await client.updateAssets(body: .json(.init(ids: assetIds, visibility: gesperrt ? .locked : .timeline)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .noContent: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }
}

/// Die PIN des gesperrten Bereichs im Schlüsselbund, nur mit Face ID / Touch ID (oder Gerätecode) lesbar.
public enum PinSafe {
    private static let dienst = "app.lilith.gesperrt"

    /// Speichert die PIN geschützt. Eine alte wird ersetzt.
    public static func speichere(_ pin: String, konto: String) throws {
        loesche(konto: konto)
        var fehler: Unmanaged<CFError>?
        guard let zugriff = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                             .userPresence, &fehler) else {
            throw fehler!.takeRetainedValue() as Error
        }
        let anfrage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: konto,
            kSecAttrAccessControl as String: zugriff,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: Data(pin.utf8),
        ]
        let status = SecItemAdd(anfrage as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    /// Liest die PIN – aber erst nach sichtbarer Bestätigung mit Face ID / Touch ID / Gerätecode.
    /// Hat das Gerät nichts davon eingerichtet, gibt es die PIN nicht heraus (dann muss man sie eintippen).
    /// `nil`: keine gespeichert, abgebrochen oder keine Gerätesperre.
    public static func lies(konto: String, grund: String = "Gesperrten Bereich öffnen") async -> String? {
        await Task.detached {
            let kontext = LAContext()
            var fehler: NSError?
            // Ausdrücklich prüfen statt sich nur auf den Schlüsselbund zu verlassen (der Simulator setzt dessen Schutz nicht immer durch).
            guard kontext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fehler) else { return nil }
            guard (try? await kontext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: grund)) == true else { return nil }
            let anfrage: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: dienst,
                kSecAttrAccount as String: konto,
                kSecUseDataProtectionKeychain as String: true,
                kSecReturnData as String: true,
                // Schon bestätigt: kein zweites Nachfragen.
                kSecUseAuthenticationContext as String: kontext,
            ]
            var ergebnis: CFTypeRef?
            guard SecItemCopyMatching(anfrage as CFDictionary, &ergebnis) == errSecSuccess,
                  let daten = ergebnis as? Data else { return nil }
            return String(data: daten, encoding: .utf8)
        }.value
    }

    public static func hatGespeichert(konto: String) -> Bool {
        let kontext = LAContext()
        kontext.interactionNotAllowed = true
        let anfrage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: konto,
            kSecUseDataProtectionKeychain as String: true,
            kSecUseAuthenticationContext as String: kontext,
        ]
        let status = SecItemCopyMatching(anfrage as CFDictionary, nil)
        // „Nicht ohne Face ID lesbar“ heißt: Es gibt einen Eintrag.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    public static func loesche(konto: String) {
        let anfrage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: konto,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(anfrage as CFDictionary)
    }
}
