import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein Monat der Timeline mit der Anzahl seiner Fotos und Videos (Immich-„Time Bucket“).
public struct TimelineMonat: Hashable, Sendable {
    /// Schlüssel, wie ihn der Server liefert, z. B. „2026-10-01“. Wird unverändert zum Nachladen genutzt.
    public let schluessel: String
    public let anzahl: Int

    public init(schluessel: String, anzahl: Int) {
        self.schluessel = schluessel
        self.anzahl = anzahl
    }

    /// Jahr und Monat aus dem Schlüssel, z. B. (2026, 10).
    public var jahrMonat: (jahr: Int, monat: Int)? {
        let teile = schluessel.prefix(10).split(separator: "-")
        guard teile.count >= 2, let j = Int(teile[0]), let m = Int(teile[1]), (1...12).contains(m) else { return nil }
        return (j, m)
    }
}

/// Ein Foto oder Video in der Timeline, so knapp wie möglich.
public struct TimelineAsset: Hashable, Sendable {
    public let id: String
    public let istBild: Bool
    /// Dauer in Millisekunden bei Videos, sonst `nil`.
    public let dauerMs: Int?
    public let istFavorit: Bool
    public let livePhotoVideoId: String?
    /// Seitenverhältnis Breite / Höhe.
    public let seitenverhaeltnis: Double
    /// Thumbhash (Base64) für einen sofortigen Platzhalter.
    public let thumbhash: String?
    public let stadt: String?

    public init(id: String, istBild: Bool, dauerMs: Int?, istFavorit: Bool, livePhotoVideoId: String?,
                seitenverhaeltnis: Double, thumbhash: String?, stadt: String?) {
        self.id = id
        self.istBild = istBild
        self.dauerMs = dauerMs
        self.istFavorit = istFavorit
        self.livePhotoVideoId = livePhotoVideoId
        self.seitenverhaeltnis = seitenverhaeltnis
        self.thumbhash = thumbhash
        self.stadt = stadt
    }
}

/// Größen der Vorschaubilder, die Immich erzeugt.
public enum VorschauGroesse: String, Sendable {
    /// ca. 250 px, fürs Grid
    case thumbnail
    /// ca. 1440 px, für große Kacheln und die Detailansicht
    case preview
}

extension ImmichClient {
    /// Alle Monate der Timeline (neueste zuerst) mit Anzahl. Archiv, Papierkorb und gesperrte Fotos sind nicht dabei.
    public func timelineMonate() async throws -> [TimelineMonat] {
        let output: Operations.GetTimeBuckets.Output
        do {
            output = try await client.getTimeBuckets(query: .init(visibility: .timeline, withPartners: nil))
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        switch output {
        case .ok(let ok):
            let liste = try await rufe { try ok.body.json }
            return liste.map { TimelineMonat(schluessel: $0.timeBucket, anzahl: $0.count) }
        case .undocumented(statusCode: 401, _):
            throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _):
            throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Inhalt eines Monats. Immich liefert die Daten spaltenweise; hier werden sie zu Einträgen zusammengesetzt.
    public func timelineInhalt(_ monat: TimelineMonat) async throws -> [TimelineAsset] {
        let output: Operations.GetTimeBucket.Output
        do {
            output = try await client.getTimeBucket(query: .init(timeBucket: monat.schluessel, visibility: .timeline))
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        switch output {
        case .ok(let ok):
            let d = try await rufe { try ok.body.json }
            return Self.zusammensetzen(d)
        case .undocumented(statusCode: 401, _):
            throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _):
            throw ImmichError.unerwarteteAntwort(code)
        }
    }

    static func zusammensetzen(_ d: Components.Schemas.TimeBucketAssetResponseDto) -> [TimelineAsset] {
        let n = d.id.count
        // Spalten mit falscher Länge würden zu Abstürzen führen: lieber sicher zugreifen.
        func wert<T>(_ spalte: [T], _ i: Int) -> T? { i < spalte.count ? spalte[i] : nil }
        var ergebnis: [TimelineAsset] = []
        ergebnis.reserveCapacity(n)
        for i in 0..<n where wert(d.isTrashed, i) != true {
            ergebnis.append(TimelineAsset(
                id: d.id[i],
                istBild: wert(d.isImage, i) ?? true,
                dauerMs: wert(d.duration, i) ?? nil,
                istFavorit: wert(d.isFavorite, i) ?? false,
                livePhotoVideoId: wert(d.livePhotoVideoId, i) ?? nil,
                seitenverhaeltnis: wert(d.ratio, i) ?? 1,
                thumbhash: wert(d.thumbhash, i) ?? nil,
                stadt: d.city.flatMap { wert($0, i) } ?? nil
            ))
        }
        return ergebnis
    }

    /// Anfrage für ein Vorschaubild, inklusive Anmeldung. Wird vom Bilder-Cache (Nuke) geladen.
    public func vorschauAnfrage(assetId: String, groesse: VorschauGroesse) -> URLRequest {
        anfrage(["assets", assetId, "thumbnail"], query: [URLQueryItem(name: "size", value: groesse.rawValue)])
    }
}
