import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein Foto für das Widget: nur das Nötigste, damit es klein bleibt.
public struct WidgetFoto: Hashable, Sendable, Codable {
    public let id: String
    /// Aufnahmezeitpunkt (für Datum unten im Widget und zum Öffnen in Luna).
    public let aufgenommen: Date
    public let stadt: String?

    public init(id: String, aufgenommen: Date, stadt: String?) {
        self.id = id; self.aufgenommen = aufgenommen; self.stadt = stadt
    }
}

/// Woher das Widget seine Fotos nimmt.
public enum ZufallsQuelle: Hashable, Sendable {
    case alle
    case favoriten
    case album(String)
    /// Fotos vom heutigen Tag in früheren Jahren (gibt es keine, zufällig aus allen).
    case heuteFrueher
}

extension ImmichClient {
    /// Zufällige Fotos (keine Videos) aus der gewählten Quelle.
    ///
    /// Bewusst über die normale Fotosuche und nicht über Immichs „zufällige Fotos“: Die beantwortet
    /// Server 3.x mit Fehler 502. Für „alle“ wird eine zufällige Seite der Bibliothek geholt und gemischt.
    public func zufaelligeFotos(_ quelle: ZufallsQuelle, anzahl: Int, heute: Date = .now) async throws -> [WidgetFoto] {
        let liste: [WidgetFoto]
        switch quelle {
        case .heuteFrueher:
            let frueher = try await fotosHeuteFrueher(heute: heute)
            if frueher.isEmpty { return try await zufaelligeFotos(.alle, anzahl: anzahl) }
            liste = frueher
        case .favoriten:
            liste = try await suche(Self.suchAnfrage(favorit: true, groesse: 250))
        case .album(let id):
            liste = try await suche(Self.suchAnfrage(alben: [id], groesse: 250))
        case .alle:
            let gesamt = try await timelineMonate(.alle).reduce(0) { $0 + $1.anzahl }
            let proSeite = 100
            let seite = Int.random(in: 1...max(1, gesamt / proSeite))
            liste = try await suche(Self.suchAnfrage(seite: seite, groesse: proSeite))
        }
        return Array(liste.shuffled().prefix(anzahl))
    }

    private func suche(_ anfrage: Components.Schemas.MetadataSearchDto) async throws -> [WidgetFoto] {
        let output: Operations.SearchAssets.Output
        do { output = try await client.searchAssets(body: .json(anfrage)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.assets.items
                .filter { !$0.isTrashed && $0._type == .image }
                .map { WidgetFoto(id: $0.id, aufgenommen: $0.fileCreatedAt, stadt: $0.exifInfo?.city) }
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Server 3.x versteht die Felder oben in der Anfrage (nicht das neuere „filter“).
    @available(*, deprecated, message: "albumIds/page/type sind veraltet, werden von Immich 3.x aber gebraucht")
    private static func suchAnfrage(favorit: Bool? = nil, alben: [String]? = nil, seite: Int? = nil,
                                    groesse: Int) -> Components.Schemas.MetadataSearchDto {
        Components.Schemas.MetadataSearchDto(albumIds: alben, isFavorite: favorit, page: seite, size: groesse,
                                             _type: .image, visibility: .timeline, withExif: true)
    }

    /// Fotos vom selben Kalendertag in den letzten zehn Jahren.
    private func fotosHeuteFrueher(heute: Date) async throws -> [WidgetFoto] {
        let kalender = Calendar.current
        let start = kalender.startOfDay(for: heute)
        return try await withThrowingTaskGroup(of: [WidgetFoto].self) { gruppe in
            for n in 1...10 {
                guard let tag = kalender.date(byAdding: .year, value: -n, to: start) else { continue }
                gruppe.addTask {
                    try await self.fotos(amTag: tag, hoechstens: 40)
                        .filter(\.istBild)
                        .map { WidgetFoto(id: $0.id, aufgenommen: $0.erstellt ?? tag, stadt: $0.stadt) }
                }
            }
            var alle: [WidgetFoto] = []
            for try await teil in gruppe { alle += teil }
            return alle
        }
    }
}

/// Link, mit dem das Widget ein Foto in Luna öffnet: `luna://foto/<id>?zeit=<Sekunden seit 1970>`.
public enum FotoLink {
    public static let schema = "luna"

    public static func url(_ foto: WidgetFoto) -> URL {
        var teile = URLComponents()
        teile.scheme = schema
        teile.host = "foto"
        teile.path = "/" + foto.id
        teile.queryItems = [URLQueryItem(name: "zeit", value: String(Int(foto.aufgenommen.timeIntervalSince1970)))]
        return teile.url!
    }

    /// Foto-ID und Aufnahmezeit aus einem Luna-Link, sonst `nil`.
    public static func lies(_ url: URL) -> (id: String, aufgenommen: Date)? {
        guard url.scheme == schema, url.host() == "foto",
              let teile = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = String(url.path().dropFirst())
        guard !id.isEmpty, !id.contains("/"),
              let zeit = teile.queryItems?.first(where: { $0.name == "zeit" })?.value.flatMap(Double.init) else { return nil }
        return (id, Date(timeIntervalSince1970: zeit))
    }
}
