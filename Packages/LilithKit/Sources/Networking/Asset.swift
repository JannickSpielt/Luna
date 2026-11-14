import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Immich schickt Zeitpunkte mal mit, mal ohne Sekundenbruchteile. Beides wird gelesen.
struct ImmichDatum: DateTranscoder {
    func encode(_ date: Date) throws -> String {
        date.formatted(.iso8601.year().month().day().timeZone(separator: .omitted)
            .time(includingFractionalSeconds: true).timeSeparator(.colon).dateSeparator(.dash))
    }

    func decode(_ text: String) throws -> Date {
        let mitBruch = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let d = try? mitBruch.parse(text) { return d }
        if let d = try? Date.ISO8601FormatStyle().parse(text) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Kein gültiges Datum: \(text)"))
    }
}

/// Alle Angaben zu einem Foto oder Video für das Info-Panel.
public struct AssetInfo: Hashable, Sendable {
    public var id: String
    public var dateiname: String
    public var istVideo: Bool
    /// Aufnahmezeit in Ortszeit der Aufnahme. Mit Zeitzone UTC formatieren.
    public var aufgenommenLokal: Date
    public var istFavorit: Bool
    public var livePhotoVideoId: String?
    public var breite: Int?
    public var hoehe: Int?
    public var dateigroesse: Int?
    public var kamera: String?
    public var objektiv: String?
    public var blende: Double?
    public var iso: Int?
    public var belichtung: String?
    public var brennweite: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var ort: String?
    public var beschreibung: String?
    public var personen: [String]

    public init(id: String, dateiname: String, istVideo: Bool = false, aufgenommenLokal: Date, istFavorit: Bool = false,
                livePhotoVideoId: String? = nil, breite: Int? = nil, hoehe: Int? = nil, dateigroesse: Int? = nil,
                kamera: String? = nil, objektiv: String? = nil, blende: Double? = nil, iso: Int? = nil,
                belichtung: String? = nil, brennweite: Double? = nil, latitude: Double? = nil, longitude: Double? = nil,
                ort: String? = nil, beschreibung: String? = nil, personen: [String] = []) {
        self.id = id; self.dateiname = dateiname; self.istVideo = istVideo; self.aufgenommenLokal = aufgenommenLokal
        self.istFavorit = istFavorit; self.livePhotoVideoId = livePhotoVideoId; self.breite = breite; self.hoehe = hoehe
        self.dateigroesse = dateigroesse; self.kamera = kamera; self.objektiv = objektiv; self.blende = blende
        self.iso = iso; self.belichtung = belichtung; self.brennweite = brennweite; self.latitude = latitude
        self.longitude = longitude; self.ort = ort; self.beschreibung = beschreibung; self.personen = personen
    }
}

extension ImmichClient {
    /// Lädt alle Angaben zu einem Foto oder Video.
    public func assetInfo(id: String) async throws -> AssetInfo {
        let output: Operations.GetAssetInfo.Output
        do {
            output = try await client.getAssetInfo(path: .init(id: id))
        } catch {
            throw Self.uebersetze(error)
        }
        switch output {
        case .ok(let ok):
            return Self.assetInfo(try await rufe { try ok.body.json })
        case .undocumented(statusCode: 401, _):
            throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _):
            throw ImmichError.unerwarteteAntwort(code)
        }
    }

    static func assetInfo(_ d: Components.Schemas.AssetResponseDto) -> AssetInfo {
        let e = d.exifInfo
        func text(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            return s
        }
        let kamera = [text(e?.make), text(e?.model)].compactMap { $0 }
        // Viele Kameras wiederholen den Hersteller im Modellnamen („Apple“ + „iPhone 15“ ist gut, „Canon“ + „Canon EOS“ nicht).
        let kameraText = kamera.count == 2 && kamera[1].lowercased().hasPrefix(kamera[0].lowercased()) ? kamera[1] : kamera.joined(separator: " ")
        let ort = [text(e?.city), text(e?.state), text(e?.country)].compactMap { $0 }
        return AssetInfo(
            id: d.id,
            dateiname: d.originalFileName,
            istVideo: d._type == .video,
            aufgenommenLokal: d.localDateTime,
            istFavorit: d.isFavorite,
            livePhotoVideoId: text(d.livePhotoVideoId),
            breite: d.width ?? e?.exifImageWidth,
            hoehe: d.height ?? e?.exifImageHeight,
            dateigroesse: e?.fileSizeInByte,
            kamera: text(kameraText),
            objektiv: text(e?.lensModel),
            blende: e?.fNumber,
            iso: e?.iso,
            belichtung: text(e?.exposureTime),
            brennweite: e?.focalLength,
            latitude: e?.latitude,
            longitude: e?.longitude,
            ort: ort.isEmpty ? nil : ort.joined(separator: ", "),
            beschreibung: text(e?.description),
            personen: (d.people ?? []).filter { !$0.isHidden }.compactMap { text($0.name) }
        )
    }

    /// Setzt die Bildunterschrift (Immich „Beschreibung“). Leerer Text entfernt sie.
    public func setzeBeschreibung(id: String, _ text: String) async throws {
        let output: Operations.UpdateAsset.Output
        do {
            output = try await client.updateAsset(path: .init(id: id), body: .json(.init(description: text)))
        } catch {
            throw Self.uebersetze(error)
        }
        switch output {
        case .ok: return
        case .undocumented(statusCode: 401, _): throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _): throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Markiert ein Foto als Favorit oder entfernt die Markierung.
    public func setzeFavorit(id: String, _ favorit: Bool) async throws {
        let output: Operations.UpdateAsset.Output
        do {
            // In v3 als veraltet markiert, der Nachfolger existiert in v3.3.5 aber noch nicht.
            output = try await client.updateAsset(path: .init(id: id), body: .json(.init(isFavorite: favorit)))
        } catch {
            throw Self.uebersetze(error)
        }
        switch output {
        case .ok: return
        case .undocumented(statusCode: 401, _): throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _): throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Anfrage für die Videowiedergabe (vom Server bei Bedarf umgewandelt).
    public func videoAnfrage(assetId: String) -> URLRequest {
        anfrage(["assets", assetId, "video", "playback"])
    }

    /// Anfrage für die Originaldatei.
    public func originalAnfrage(assetId: String) -> URLRequest {
        anfrage(["assets", assetId, "original"])
    }

    /// Anfrage für das Profilbild eines Nutzers (404, wenn keins hochgeladen ist).
    public func profilbildAnfrage(nutzerId: String) -> URLRequest {
        anfrage(["users", nutzerId, "profile-image"])
    }

    /// Anmelde-Header, z. B. für den Videoplayer.
    /// Hängt den Zugang als Parameter an den Link (Immich: `sessionKey` bzw. `apiKey`).
    /// Nötig für AirPlay: Das Apple TV lädt das Video selbst und kennt Lunas Header nicht.
    public func mitZugangImLink(_ url: URL) -> URL {
        switch credential {
        case .accessToken(let token): url.appending(queryItems: [URLQueryItem(name: "sessionKey", value: token)])
        case .apiKey(let key): url.appending(queryItems: [URLQueryItem(name: "apiKey", value: key)])
        case nil: url
        }
    }

    public var anmeldeHeader: [String: String] {
        switch credential {
        case .accessToken(let token): ["Authorization": "Bearer \(token)"]
        case .apiKey(let key): ["x-api-key": key]
        case nil: [:]
        }
    }

    func anfrage(_ pfad: [String], query: [URLQueryItem] = []) -> URLRequest {
        var url = address.apiURL
        for teil in pfad { url.append(path: teil) }
        if !query.isEmpty { url.append(queryItems: query) }
        var anfrage = URLRequest(url: url)
        for (name, wert) in anmeldeHeader { anfrage.setValue(wert, forHTTPHeaderField: name) }
        return anfrage
    }

    /// Lädt die Originaldatei in einen temporären Ordner, z. B. zum Teilen.
    public func ladeOriginal(assetId: String, dateiname: String) async throws -> URL {
        let ordner = FileManager.default.temporaryDirectory.appending(path: "lilith-teilen").appending(path: assetId)
        // Nur der letzte Pfadteil, damit ein Dateiname nie aus dem Ordner herausführt.
        let name = URL(fileURLWithPath: dateiname).lastPathComponent
        let ziel = ordner.appending(path: name.isEmpty ? assetId : name)
        // Schon einmal geladen: wiederverwenden statt neu herunterzuladen.
        if FileManager.default.fileExists(atPath: ziel.path) { return ziel }
        let (temp, antwort): (URL, URLResponse)
        do {
            (temp, antwort) = try await URLSession.shared.download(for: originalAnfrage(assetId: assetId))
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw status == 401 ? ImmichError.sitzungAbgelaufen : ImmichError.unerwarteteAntwort(status)
        }
        try? FileManager.default.removeItem(at: ordner)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temp, to: ziel)
        return ziel
    }

    static func uebersetze(_ error: any Error) -> ImmichError {
        if let e = error as? ImmichError { return e }
        if let c = error as? ClientError, c.underlyingError is DecodingError { return .keinImmichServer }
        return .nichtErreichbar(kurzerGrund(error))
    }
}
