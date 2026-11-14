import Foundation
import Observation
import Networking
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Hält die Anmeldung: wer angemeldet ist und bei welchem Server.
@MainActor
@Observable
public final class SessionStore {
    public enum Phase: Equatable {
        case startet
        case abgemeldet
        case angemeldet(Account)
    }

    public private(set) var phase: Phase = .startet
    /// Hinweis auf dem Anmelde-Bildschirm, z. B. wenn die Sitzung abgelaufen ist.
    public var hinweis: String?
    /// Zuletzt genutzte Serveradresse, damit sie beim erneuten Anmelden schon drinsteht.
    public private(set) var letzteAdresse: String?
    /// Client des angemeldeten Kontos.
    public private(set) var client: ImmichClient?

    private let store: AccountStore

    public init(store: AccountStore = AccountStore()) {
        self.store = store
    }

    /// Beim App-Start: gespeichertes Konto laden und im Hintergrund prüfen.
    public func start() async {
        guard phase == .startet else { return }
        #if DEBUG
        // Zum Testen: „-LilithKeychainTest YES“ prüft, ob der Schlüsselbund nutzbar ist.
        if UserDefaults.standard.bool(forKey: "LilithKeychainTest") {
            let kc = KeychainStore(service: "app.lilith.test")
            do {
                try kc.save(.apiKey("test-wert"), account: "test")
                let ok = kc.load(account: "test") == .apiKey("test-wert")
                kc.delete(account: "test")
                print("LILITH-KEYCHAIN \(ok ? "OK" : "LESEN FEHLGESCHLAGEN")")
            } catch {
                print("LILITH-KEYCHAIN FEHLER \(error.localizedDescription)")
            }
            fflush(stdout)
        }
        // Zum Testen ohne Server: Start mit „-LilithDemo YES“ überspringt die Anmeldung.
        if UserDefaults.standard.bool(forKey: "LilithDemo") {
            let adresse = ServerAddress(eingabe: "demo.lilith.invalid")!
            phase = .angemeldet(Account(
                server: ServerInfo(address: adresse, version: ServerVersion(major: 3, minor: 3, patch: 5),
                                   capabilities: ServerCapabilities(smartSearch: true, trash: true)),
                user: ImmichUser(id: "demo", email: "demo@lilith.invalid", name: "Demo", isAdmin: false),
                usesAPIKey: true))
            return
        }
        #endif
        guard let (account, credential) = store.activeAccount() else {
            letzteAdresse = store.accounts().first?.server.address.description
            phase = .abgemeldet
            return
        }
        let client = ImmichClient(address: account.server.address, credential: credential)
        self.client = client
        // Bestehende Anmeldung auch dem Teilen-Menü bekannt machen (ohne neu anmelden).
        GeteiltesKonto.speichere(account, credential: credential)
        // Sofort anzeigen, auch offline. Die Prüfung läuft danach.
        phase = .angemeldet(account)

        do {
            let user = try await client.currentUser()
            var aktualisiert = account
            aktualisiert.user = user
            if let info = try? await client.serverInfo() { aktualisiert.server = info }
            try? store.save(aktualisiert, credential: credential)
            if case .angemeldet = phase { phase = .angemeldet(aktualisiert) }
        } catch ImmichError.sitzungAbgelaufen {
            beende(account, hinweis: ImmichError.sitzungAbgelaufen.errorDescription)
        } catch {
            // Offline oder Server kurz weg: angemeldet bleiben, später erneut versuchen.
        }
    }

    /// Prüft eine eingegebene Serveradresse.
    public func pruefe(adresse eingabe: String) async throws -> ServerInfo {
        guard let adresse = ServerAddress(eingabe: eingabe) else { throw ImmichError.ungueltigeAdresse }
        return try await ImmichClient(address: adresse).serverInfo()
    }

    /// Anmeldung mit E-Mail und Passwort.
    public func anmelden(bei server: ServerInfo, email: String, passwort: String) async throws {
        guard server.capabilities.passwordLogin else { throw ImmichError.passwortLoginAus }
        let (credential, user) = try await ImmichClient(address: server.address)
            .login(email: email.trimmingCharacters(in: .whitespaces), password: passwort)
        try speichere(Account(server: server, user: user, usesAPIKey: false), credential: credential)
    }

    /// Anmeldung mit API-Key.
    public func anmelden(bei server: ServerInfo, apiKey: String) async throws {
        let credential = Credential.apiKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
        let user: ImmichUser
        do {
            user = try await ImmichClient(address: server.address, credential: credential).currentUser()
        } catch ImmichError.sitzungAbgelaufen {
            throw ImmichError.falscheZugangsdaten
        }
        try speichere(Account(server: server, user: user, usesAPIKey: true), credential: credential)
    }

    /// Der Server hat die Anmeldung abgelehnt: zurück zur Anmeldung, mit Hinweis.
    public func sitzungAbgelaufen() {
        guard case .angemeldet(let account) = phase else { return }
        beende(account, hinweis: ImmichError.sitzungAbgelaufen.errorDescription)
    }

    public func abmelden() async {
        guard case .angemeldet(let account) = phase else { return }
        if !account.usesAPIKey { await client?.logout() }
        beende(account, hinweis: nil)
    }

    private func speichere(_ account: Account, credential: Credential) throws {
        try store.save(account, credential: credential)
        client = ImmichClient(address: account.server.address, credential: credential)
        hinweis = nil
        phase = .angemeldet(account)
        Self.widgetsNeuLaden()
    }

    /// Nach An- oder Abmelden: das Foto-Widget soll gleich das richtige Konto zeigen.
    private static func widgetsNeuLaden() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func beende(_ account: Account, hinweis: String?) {
        store.remove(account)
        TimelineCache.loescheAlles()
        client = nil
        letzteAdresse = account.server.address.description
        self.hinweis = hinweis
        phase = .abgemeldet
        Self.widgetsNeuLaden()
    }
}
