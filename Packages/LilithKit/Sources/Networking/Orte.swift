import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein Ort mit Fotos: Stadt, Land, Anzahl, Mittelpunkt und ein Foto als Titelbild.
public struct Ort: Identifiable, Hashable, Sendable {
    public let stadt: String
    public let land: String?
    public let anzahl: Int
    public let breite: Double
    public let laenge: Double
    public let titelBildId: String
    public var id: String { "\(stadt)|\(land ?? "")" }

    public init(stadt: String, land: String?, anzahl: Int, breite: Double, laenge: Double, titelBildId: String) {
        self.stadt = stadt; self.land = land; self.anzahl = anzahl
        self.breite = breite; self.laenge = laenge; self.titelBildId = titelBildId
    }
}

extension ImmichClient {
    /// Alle Orte mit Fotos, nach Anzahl sortiert (die meisten zuerst). Fotos ohne Stadt zählen nicht.
    public func orte() async throws -> [Ort] {
        let output: Operations.GetMapMarkers.Output
        do { output = try await client.getMapMarkers(query: .init(isArchived: false)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            let punkte = try await rufe { try ok.body.json }
            return Self.gruppiereOrte(punkte.compactMap { p in
                guard let stadt = p.city, !stadt.isEmpty else { return nil }
                return (id: p.id, stadt: stadt, land: p.country, breite: p.lat, laenge: p.lon)
            })
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Fasst Kartenpunkte nach Stadt und Land zusammen; der Mittelpunkt ist der Durchschnitt.
    static func gruppiereOrte(_ punkte: [(id: String, stadt: String, land: String?, breite: Double, laenge: Double)]) -> [Ort] {
        var gruppen: [String: (stadt: String, land: String?, anzahl: Int, breite: Double, laenge: Double, bild: String)] = [:]
        for p in punkte {
            let schluessel = "\(p.stadt)|\(p.land ?? "")"
            if var g = gruppen[schluessel] {
                g.anzahl += 1; g.breite += p.breite; g.laenge += p.laenge
                gruppen[schluessel] = g
            } else {
                gruppen[schluessel] = (p.stadt, p.land, 1, p.breite, p.laenge, p.id)
            }
        }
        return gruppen.values
            .map { Ort(stadt: $0.stadt, land: $0.land, anzahl: $0.anzahl, breite: $0.breite / Double($0.anzahl),
                       laenge: $0.laenge / Double($0.anzahl), titelBildId: $0.bild) }
            .sorted { $0.anzahl != $1.anzahl ? $0.anzahl > $1.anzahl : $0.stadt < $1.stadt }
    }

    /// Alle Fotos aus einer Stadt, neueste zuerst.
    public func fotos(inStadt stadt: String, land: String?, hoechstens: Int = 5000) async throws -> [TimelineAsset] {
        typealias S = Components.Schemas
        var treffer: [S.AssetResponseDto] = []
        var seite = 1
        while treffer.count < hoechstens {
            var anfrage = S.MetadataSearchDto()
            anfrage.city = stadt
            anfrage.country = land
            anfrage.visibility = .timeline
            anfrage.page = seite
            anfrage.size = 1000
            let output: Operations.SearchAssets.Output
            do { output = try await client.searchAssets(body: .json(anfrage)) } catch { throw Self.uebersetze(error) }
            switch output {
            case .ok(let ok):
                let antwort = try await rufe { try ok.body.json }.assets
                treffer += antwort.items.filter { !$0.isTrashed }
                guard antwort.nextPage != nil, !antwort.items.isEmpty else { return Self.sortiert(treffer) }
                seite += 1
            case .undocumented(let code, _): throw Self.fehler(code)
            }
        }
        return Self.sortiert(treffer)
    }

    private static func sortiert(_ d: [Components.Schemas.AssetResponseDto]) -> [TimelineAsset] {
        d.sorted { $0.fileCreatedAt > $1.fileCreatedAt }.map(timelineAsset)
    }
}
