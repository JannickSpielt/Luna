import Foundation

/// Eine geprüfte Immich-Serveradresse, z. B. `https://fotos.example.de`.
public struct ServerAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Basisadresse ohne `/api` und ohne Schrägstrich am Ende.
    public let url: URL

    /// Adresse der REST-API (`…/api`).
    public var apiURL: URL { url.appending(path: "api") }

    public var description: String { url.absoluteString }

    /// Wandelt eine Eingabe des Nutzers in eine Adresse um.
    /// Ergänzt `https://`, entfernt Leerzeichen, Schrägstriche und ein angehängtes `/api`.
    /// Gibt `nil` zurück, wenn die Eingabe keine gültige Adresse ist.
    public init?(eingabe: String) {
        var text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/api") { text.removeLast(4) }
        while text.hasSuffix("/") { text.removeLast() }

        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty,
              url.query == nil, url.fragment == nil
        else { return nil }
        self.url = url
    }
}
