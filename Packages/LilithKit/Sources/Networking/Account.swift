import Foundation

/// Ein Konto: ein Nutzer auf einem Server. Das Modell kann mehrere Konten,
/// die Oberfläche zeigt vorerst nur eins.
public struct Account: Identifiable, Hashable, Codable, Sendable {
    public var server: ServerInfo
    public var user: ImmichUser
    public var usesAPIKey: Bool

    /// Eindeutig pro Server und Nutzer. Dient auch als Schlüssel im Schlüsselbund.
    public var id: String { "\(server.address.url.absoluteString)#\(user.id)" }

    public init(server: ServerInfo, user: ImmichUser, usesAPIKey: Bool) {
        self.server = server
        self.user = user
        self.usesAPIKey = usesAPIKey
    }
}

/// Speichert die Konten (ohne Geheimnisse) lokal. Token und API-Keys liegen im Schlüsselbund.
/// Wird in Schritt 4 durch die Datenbank ersetzt.
public struct AccountStore: Sendable {
    private let key = "lilith.accounts"
    // UserDefaults ist laut Apple threadsicher, aber nicht als Sendable markiert.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let keychain: KeychainStore

    public init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func accounts() -> [Account] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Account].self, from: data)) ?? []
    }

    /// Das zuletzt genutzte Konto samt Zugangsdaten, falls vorhanden.
    public func activeAccount() -> (Account, Credential)? {
        for account in accounts() {
            if let credential = keychain.load(account: account.id) { return (account, credential) }
        }
        return nil
    }

    public func save(_ account: Account, credential: Credential) throws {
        try keychain.save(credential, account: account.id)
        var list = accounts().filter { $0.id != account.id }
        list.insert(account, at: 0)
        defaults.set(try JSONEncoder().encode(list), forKey: key)
        GeteiltesKonto.speichere(account, credential: credential)
    }

    public func remove(_ account: Account) {
        keychain.delete(account: account.id)
        GeteiltesKonto.loesche()
        let list = accounts().filter { $0.id != account.id }
        defaults.set(try? JSONEncoder().encode(list), forKey: key)
    }
}
