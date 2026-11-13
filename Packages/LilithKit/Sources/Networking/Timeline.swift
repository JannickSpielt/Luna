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
    /// Aufnahmezeitpunkt (zum Einsortieren von Fotos, die nur auf dem Gerät liegen).
    public let erstellt: Date?

    public init(id: String, istBild: Bool, dauerMs: Int?, istFavorit: Bool, livePhotoVideoId: String?,
                seitenverhaeltnis: Double, thumbhash: String?, stadt: String?, erstellt: Date? = nil) {
        self.erstellt = erstellt
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
    public func timelineMonate(_ filter: TimelineFilter = .alle) async throws -> [TimelineMonat] {
        let output: Operations.GetTimeBuckets.Output
        do {
            let f = Self.abfrage(filter)
            output = try await client.getTimeBuckets(query: .init(
                albumId: f.album, isFavorite: f.favorit, isTrashed: f.papierkorb, personId: f.person, visibility: f.sichtbarkeit))
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
    public func timelineInhalt(_ monat: TimelineMonat, filter: TimelineFilter = .alle) async throws -> [TimelineAsset] {
        let output: Operations.GetTimeBucket.Output
        do {
            let f = Self.abfrage(filter)
            output = try await client.getTimeBucket(query: .init(
                albumId: f.album, isFavorite: f.favorit, isTrashed: f.papierkorb, personId: f.person,
                timeBucket: monat.schluessel, visibility: f.sichtbarkeit))
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        switch output {
        case .ok(let ok):
            let d = try await rufe { try ok.body.json }
            return Self.zusammensetzen(d, mitPapierkorb: filter == .papierkorb)
        case .undocumented(statusCode: 401, _):
            throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _):
            throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Übersetzt den Filter in die Abfrage-Parameter von Immich.
    static func abfrage(_ filter: TimelineFilter)
        -> (album: String?, favorit: Bool?, papierkorb: Bool?, sichtbarkeit: Components.Schemas.AssetVisibility?, person: String?) {
        switch filter {
        case .alle: (nil, nil, nil, .timeline, nil)
        case .favoriten: (nil, true, nil, .timeline, nil)
        case .archiv: (nil, nil, nil, .archive, nil)
        case .papierkorb: (nil, nil, true, nil, nil)
        case .album(let id): (id, nil, nil, nil, nil)
        case .person(let id): (nil, nil, nil, .timeline, id)
        case .suche, .kuerzlich, .medienart, .ort: (nil, nil, nil, .timeline, nil)
        }
    }

    /// ISO-Datum mit oder ohne Sekundenbruchteile.
    static func leseDatum(_ text: String) -> Date? {
        // Immich schreibt je nach Version „…Z“ oder „…+00:00“, mit oder ohne Sekundenbruchteile.
        let mit = ISO8601DateFormatter()
        mit.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = mit.date(from: text) { return d }
        let ohne = ISO8601DateFormatter()
        ohne.formatOptions = [.withInternetDateTime]
        if let d = ohne.date(from: text) { return d }
        // Die Timeline liefert die Ortszeit ohne Zeitzone („2026-11-12T10:01:18.975“): als Ortszeit des Geräts lesen.
        let teile = text.split(separator: ".", maxSplits: 1)
        let basis = DateFormatter()
        basis.locale = Locale(identifier: "en_US_POSIX")
        basis.timeZone = .current
        basis.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let sekunden = teile.first.flatMap({ basis.date(from: String($0)) }) else { return nil }
        let bruch = teile.count > 1 ? Double("0." + teile[1].prefix { $0.isNumber }) ?? 0 : 0
        return sekunden.addingTimeInterval(bruch)
    }

    static func zusammensetzen(_ d: Components.Schemas.TimeBucketAssetResponseDto, mitPapierkorb: Bool = false) -> [TimelineAsset] {
        let n = d.id.count
        // Spalten mit falscher Länge würden zu Abstürzen führen: lieber sicher zugreifen.
        func wert<T>(_ spalte: [T], _ i: Int) -> T? { i < spalte.count ? spalte[i] : nil }
        var ergebnis: [TimelineAsset] = []
        ergebnis.reserveCapacity(n)
        for i in 0..<n where mitPapierkorb || wert(d.isTrashed, i) != true {
            ergebnis.append(TimelineAsset(
                id: d.id[i],
                istBild: wert(d.isImage, i) ?? true,
                dauerMs: wert(d.duration, i) ?? nil,
                istFavorit: wert(d.isFavorite, i) ?? false,
                livePhotoVideoId: wert(d.livePhotoVideoId, i) ?? nil,
                seitenverhaeltnis: wert(d.ratio, i) ?? 1,
                thumbhash: wert(d.thumbhash, i) ?? nil,
                stadt: d.city.flatMap { wert($0, i) } ?? nil,
                erstellt: wert(d.fileCreatedAt, i).flatMap(Self.leseDatum)
            ))
        }
        return ergebnis
    }

    /// Anfrage für ein Vorschaubild, inklusive Anmeldung. Wird vom Bilder-Cache (Nuke) geladen.
    public func vorschauAnfrage(assetId: String, groesse: VorschauGroesse) -> URLRequest {
        anfrage(["assets", assetId, "thumbnail"], query: [URLQueryItem(name: "size", value: groesse.rawValue)])
    }
}
