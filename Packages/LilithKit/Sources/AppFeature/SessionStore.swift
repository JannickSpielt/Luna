import Foundation
import Observation
import Networking

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
        guard let (account, credential) = store.activeAccount() else {
            letzteAdresse = store.accounts().first?.server.address.description
            phase = .abgemeldet
            return
        }
        let client = ImmichClient(address: account.server.address, credential: credential)
        self.client = client
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
    }

    private func beende(_ account: Account, hinweis: String?) {
        store.remove(account)
        client = nil
        letzteAdresse = account.server.address.description
        self.hinweis = hinweis
        phase = .abgemeldet
    }
}
