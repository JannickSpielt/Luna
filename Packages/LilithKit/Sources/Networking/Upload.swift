import CryptoKit
import Foundation
import ImmichAPI
import OpenAPIRuntime

/// SHA1-Prüfsumme einer Datei als Base64, genau wie die offizielle Immich-App sie berechnet.
/// Die Datei wird stückweise gelesen, auch große Videos landen nie ganz im Speicher.
public enum Pruefsumme {
    public static func sha1Base64(datei: URL) throws -> String {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: datei) } catch { throw ImmichError.dateiNichtLesbar(error.localizedDescription) }
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while true {
            let stueck = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if stueck.isEmpty { break }
            hasher.update(data: stueck)
        }
        return Data(hasher.finalize()).base64EncodedString()
    }
}

/// Eine Datei, die hochgeladen werden soll.
public struct UploadDatei: Sendable, Hashable {
    public var datei: URL
    public var dateiname: String
    public var erstellt: Date
    public var geaendert: Date
    /// Videodauer in Millisekunden.
    public var dauerMs: Int?
    /// Bei Live Photos: ID des schon hochgeladenen Videos.
    public var livePhotoVideoId: String?
    /// Versteckt hochladen (das Video eines Live Photos).
    public var versteckt: Bool
    public var pruefsumme: String?
    /// Nur über WLAN senden (automatisches Backup mit dieser Einstellung).
    public var nurWLAN: Bool

    public init(datei: URL, dateiname: String, erstellt: Date, geaendert: Date, dauerMs: Int? = nil,
                livePhotoVideoId: String? = nil, versteckt: Bool = false, pruefsumme: String? = nil, nurWLAN: Bool = false) {
        self.nurWLAN = nurWLAN
        self.datei = datei; self.dateiname = dateiname; self.erstellt = erstellt; self.geaendert = geaendert
        self.dauerMs = dauerMs; self.livePhotoVideoId = livePhotoVideoId; self.versteckt = versteckt; self.pruefsumme = pruefsumme
    }
}

/// Ergebnis eines Uploads: ID auf dem Server und ob das Foto schon da war.
public struct UploadErgebnis: Sendable, Equatable {
    public let id: String
    public let duplikat: Bool
}

/// Was der Server vorab zu einer Prüfsumme sagt.
public enum VorabPruefung: Sendable, Equatable {
    case hochladen
    case vorhanden(id: String, imPapierkorb: Bool)
    case abgelehnt
}

/// Baut den Multipart-Body als Datei. So können auch Uploads im Hintergrund ihn später senden.
enum Multipart {
    static func datum(_ d: Date) -> String {
        d.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// Schreibt den Body nach `ziel` und gibt die Trennzeichenfolge zurück.
    static func schreibe(_ d: UploadDatei, nach ziel: URL) throws -> String {
        let grenze = "LilithGrenze-\(UUID().uuidString)"
        FileManager.default.createFile(atPath: ziel.path, contents: nil)
        let aus = try FileHandle(forWritingTo: ziel)
        defer { try? aus.close() }

        func feld(_ name: String, _ wert: String) throws {
            try aus.write(contentsOf: Data("--\(grenze)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(wert)\r\n".utf8))
        }
        try feld("fileCreatedAt", datum(d.erstellt))
        try feld("fileModifiedAt", datum(d.geaendert))
        try feld("filename", d.dateiname)
        if let dauer = d.dauerMs { try feld("duration", String(dauer)) }
        if let live = d.livePhotoVideoId { try feld("livePhotoVideoId", live) }
        if d.versteckt { try feld("visibility", "hidden") }

        // Dateiname im Header ohne Anführungszeichen und Zeilenumbrüche.
        let sicher = d.dateiname.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        try aus.write(contentsOf: Data("--\(grenze)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"\(sicher)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        let ein: FileHandle
        do { ein = try FileHandle(forReadingFrom: d.datei) } catch { throw ImmichError.dateiNichtLesbar(error.localizedDescription) }
        defer { try? ein.close() }
        while true {
            let stueck = try ein.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if stueck.isEmpty { break }
            try aus.write(contentsOf: stueck)
        }
        try aus.write(contentsOf: Data("\r\n--\(grenze)--\r\n".utf8))
        return grenze
    }
}

/// Meldet den Fortschritt eines Uploads.
final class UploadFortschritt: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let melden: @Sendable (Double) -> Void
    init(_ melden: @escaping @Sendable (Double) -> Void) { self.melden = melden }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        melden(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

extension ImmichClient {
    /// Fragt den Server, welche Prüfsummen er schon kennt. Schlüssel ist die eigene Kennung.
    /// Höchstens 500 auf einmal, mehr wird automatisch aufgeteilt.
    public func pruefeVorab(_ eintraege: [(kennung: String, pruefsumme: String)]) async throws -> [String: VorabPruefung] {
        var ergebnis: [String: VorabPruefung] = [:]
        for start in stride(from: 0, to: eintraege.count, by: 500) {
            let teil = eintraege[start..<min(start + 500, eintraege.count)]
            let output: Operations.CheckBulkUpload.Output
            do {
                output = try await client.checkBulkUpload(body: .json(.init(
                    assets: teil.map { .init(checksum: $0.pruefsumme, id: $0.kennung) })))
            } catch { throw Self.uebersetze(error) }
            switch output {
            case .ok(let ok):
                for r in try await rufe({ try ok.body.json }).results {
                    switch r.action {
                    case .accept: ergebnis[r.id] = .hochladen
                    case .reject:
                        if r.reason == .duplicate, let id = r.assetId {
                            ergebnis[r.id] = .vorhanden(id: id, imPapierkorb: r.isTrashed ?? false)
                        } else {
                            ergebnis[r.id] = .abgelehnt
                        }
                    }
                }
            case .undocumented(let code, _): throw Self.fehler(code)
            }
        }
        return ergebnis
    }

    /// Lädt eine Datei hoch. Der Multipart-Body wird vorher als Datei gebaut und danach gelöscht.
    public func ladeHoch(_ d: UploadDatei, arbeitsordner: URL,
                         fortschritt: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> UploadErgebnis {
        try FileManager.default.createDirectory(at: arbeitsordner, withIntermediateDirectories: true)
        let body = arbeitsordner.appending(path: "upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: body) }
        let grenze = try Multipart.schreibe(d, nach: body)
        let anfrage = uploadAnfrage(grenze: grenze, datei: d)

        let (daten, antwort): (Data, URLResponse)
        do {
            (daten, antwort) = try await uploadSession.upload(for: anfrage, fromFile: body, delegate: UploadFortschritt(fortschritt))
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        return try Self.werteUploadAus(status: (antwort as? HTTPURLResponse)?.statusCode ?? 0, daten: daten)
    }

    /// Die Anfrage für `POST /assets` (ohne Body).
    func uploadAnfrage(grenze: String, datei d: UploadDatei) -> URLRequest {
        var anfrage = anfrage(["assets"])
        anfrage.httpMethod = "POST"
        anfrage.timeoutInterval = 600
        anfrage.setValue("multipart/form-data; boundary=\(grenze)", forHTTPHeaderField: "Content-Type")
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
        if let summe = d.pruefsumme { anfrage.setValue(summe, forHTTPHeaderField: "x-immich-checksum") }
        if d.nurWLAN {
            // Auch wenn iOS den Upload im Hintergrund weiterführt: nie über Mobilfunk oder im Datensparmodus.
            anfrage.allowsCellularAccess = false
            anfrage.allowsExpensiveNetworkAccess = false
            anfrage.allowsConstrainedNetworkAccess = false
        }
        return anfrage
    }

    /// Wertet die Antwort des Servers auf einen Upload aus.
    static func werteUploadAus(status: Int, daten: Data) throws -> UploadErgebnis {
        switch status {
        case 200, 201:
            struct Antwort: Decodable { let id: String; let status: String }
            guard let a = try? JSONDecoder().decode(Antwort.self, from: daten) else { throw ImmichError.keinImmichServer }
            return UploadErgebnis(id: a.id, duplikat: a.status == "duplicate" || status == 200)
        case 401: throw ImmichError.sitzungAbgelaufen
        case 413: throw ImmichError.dateiZuGross
        default:
            let text = String(decoding: daten, as: UTF8.self).lowercased()
            if text.contains("quota") { throw ImmichError.kontingentVoll }
            if text.contains("unsupported") { throw ImmichError.formatNichtUnterstuetzt }
            throw ImmichError.unerwarteteAntwort(status)
        }
    }

    /// Fügt Fotos nach dem Upload einem Album hinzu (auch Duplikate).
    public func nachUpload(albumId: String, assetIds: [String]) async throws {
        _ = try await fuegeZuAlbum(albumId: albumId, assetIds: assetIds)
    }
}
