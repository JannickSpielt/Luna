import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein Monat der Timeline mit der Anzahl seiner Fotos und Videos (Immich-„Time Bucket“).
public struct TimelineMonat: Hashable, Sendable, Codable {
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
public struct TimelineAsset: Hashable, Sendable, Codable {
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
        case .gesperrt: (nil, nil, nil, .locked, nil)
        case .suche, .kuerzlich, .medienart, .ort, .ordner, .tag, .ohneAlbum, .weihnachten: (nil, nil, nil, .timeline, nil)
        }
    }

    /// ISO-Datum mit oder ohne Sekundenbruchteile.
    // Einmal angelegt statt pro Foto (Formatierer sind teuer). Laut Apple sind sie threadsicher.
    nonisolated(unsafe) private static let isoMit: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let isoOhne: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func leseDatum(_ text: String) -> Date? {
        // Häufigster Fall (Timeline): Ortszeit ohne Zeitzone, „2026-11-12T10:01:18.975“. Von Hand lesen, das ist
        // viel schneller als ein Formatierer; als Ortszeit des Geräts.
        if let d = leseOrtszeit(text) { return d }
        // Immich schreibt je nach Version „…Z“ oder „…+00:00“, mit oder ohne Sekundenbruchteile.
        return isoMit.date(from: text) ?? isoOhne.date(from: text)
    }

    /// „yyyy-MM-ddTHH:mm:ss“ mit optionalen Sekundenbruchteilen und ohne Zeitzone, sonst `nil`.
    static func leseOrtszeit(_ text: String) -> Date? {
        let z = Array(text.utf8)
        guard z.count >= 19, z[4] == 45, z[7] == 45, z[10] == 84, z[13] == 58, z[16] == 58 else { return nil }
        func zahl(_ von: Int, _ bis: Int) -> Int? {
            var w = 0
            for i in von..<bis { let c = z[i]; guard c >= 48, c <= 57 else { return nil }; w = w * 10 + Int(c - 48) }
            return w
        }
        var bruch = 0.0
        if z.count > 19 {
            guard z[19] == 46 else { return nil }   // Zeitzone dahinter: nicht dieser Fall
            var faktor = 0.1
            for c in z[20...] {
                guard c >= 48, c <= 57 else { return nil }
                bruch += Double(c - 48) * faktor; faktor /= 10
            }
        }
        guard let jahr = zahl(0, 4), let monat = zahl(5, 7), let tag = zahl(8, 10),
              let stunde = zahl(11, 13), let minute = zahl(14, 16), let sekunde = zahl(17, 19) else { return nil }
        var k = DateComponents()
        k.year = jahr; k.month = monat; k.day = tag; k.hour = stunde; k.minute = minute; k.second = sekunde
        return Calendar.current.date(from: k)?.addingTimeInterval(bruch)
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
