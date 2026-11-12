import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import Backup
@testable import Networking
@testable import Persistence

// MARK: - Hilfen

/// Antwortet auf generierte API-Aufrufe per Funktion (Operation, Body → Status, JSON).
final class FunktionsTransport: ClientTransport, @unchecked Sendable {
    let antwort: @Sendable (String, String) -> (Int, String)
    private let sperre = NSLock()
    private(set) var aufrufe: [String] = []
    init(_ antwort: @escaping @Sendable (String, String) -> (Int, String)) { self.antwort = antwort }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        var text = ""
        if let body { text = try await String(collecting: body, upTo: 1_000_000) }
        sperre.withLock { aufrufe.append(operationID) }
        let (status, json) = antwort(operationID, text)
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(json))
    }
}

/// Fängt Uploads über `URLSession` ab.
final class UploadAttrappe: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var antwort: (Int, String) = (201, #"{"id":"neu-1","status":"created"}"#)
    nonisolated(unsafe) static var anfragen: [URLRequest] = []
    static let sperre = NSLock()

    static func session() -> URLSession {
        URLSession(configuration: konfiguration())
    }

    static func konfiguration() -> URLSessionConfiguration {
        let k = URLSessionConfiguration.ephemeral
        k.protocolClasses = [UploadAttrappe.self]
        return k
    }

    /// Uploader wie in der App, aber über die Attrappe statt einer echten Hintergrund-Session.
    static func uploader() -> HintergrundUpload {
        HintergrundUpload(konfiguration: konfiguration(), koerperOrdner: tempOrdner())
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.sperre.withLock { Self.anfragen.append(request) }
        let (status, json) = Self.sperre.withLock { Self.antwort }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func tempOrdner() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "lilith-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Tests

@Suite("Prüfsumme und Multipart")
struct PruefsummeTests {
    @Test("SHA1 als Base64 wie Immich")
    func sha1() throws {
        let datei = tempOrdner().appending(path: "abc.txt")
        try Data("abc".utf8).write(to: datei)
        #expect(try Pruefsumme.sha1Base64(datei: datei) == "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=")
    }

    @Test("Multipart-Body enthält Pflichtfelder und Datei")
    func multipart() throws {
        let ordner = tempOrdner()
        let datei = ordner.appending(path: "IMG_1.HEIC")
        try Data("BILDDATEN".utf8).write(to: datei)
        let body = ordner.appending(path: "body")
        let d = UploadDatei(datei: datei, dateiname: "IMG_1.HEIC", erstellt: Date(timeIntervalSince1970: 0),
                            geaendert: Date(timeIntervalSince1970: 60), dauerMs: 1500, livePhotoVideoId: "v1", versteckt: true)
        let grenze = try Multipart.schreibe(d, nach: body)
        let text = try String(contentsOf: body, encoding: .utf8)
        #expect(text.contains("name=\"fileCreatedAt\"\r\n\r\n1970-01-01T00:00:00.000Z"))
        #expect(text.contains("name=\"fileModifiedAt\"\r\n\r\n1970-01-01T00:01:00.000Z"))
        #expect(text.contains("name=\"duration\"\r\n\r\n1500"))
        #expect(text.contains("name=\"livePhotoVideoId\"\r\n\r\nv1"))
        #expect(text.contains("name=\"visibility\"\r\n\r\nhidden"))
        #expect(text.contains("name=\"assetData\"; filename=\"IMG_1.HEIC\"\r\nContent-Type: application/octet-stream\r\n\r\nBILDDATEN\r\n"))
        #expect(text.hasSuffix("--\(grenze)--\r\n"))
    }

    @Test("EXIF-Datum mit und ohne Zeitzone")
    func exif() {
        let mit = ImportVorbereitung.exifDatum("2026:10:18 19:42:10", versatz: "+01:00")
        #expect(mit == Date(timeIntervalSince1970: 1_792_348_930))
        #expect(ImportVorbereitung.exifDatum("kein Datum", versatz: nil) == nil)
    }

    @Test("Nur Fotos und Videos werden aufgenommen, Ordner werden durchsucht")
    func sammeln() throws {
        let ordner = tempOrdner()
        let unter = ordner.appending(path: "Urlaub")
        try FileManager.default.createDirectory(at: unter, withIntermediateDirectories: true)
        for name in ["a.jpg", "b.txt", "Urlaub/c.mov", "Urlaub/d.heic", "Urlaub/e.pdf"] {
            try Data().write(to: ordner.appending(path: name))
        }
        let namen = ImportVorbereitung.sammleMedien([ordner]).map(\.lastPathComponent).sorted()
        #expect(namen == ["a.jpg", "c.mov", "d.heic"])
    }
}

@MainActor
@Suite("Upload-Warteschlange", .serialized)
struct WarteschlangeTests {
    @Test("Lädt Neues hoch, erkennt Vorhandenes, fügt dem Album hinzu und räumt auf")
    func durchgang() async throws {
        let quelle = tempOrdner()
        let neu = quelle.appending(path: "neu.jpg")
        let alt = quelle.appending(path: "alt.jpg")
        try Data("neues Foto".utf8).write(to: neu)
        try Data("altes Foto".utf8).write(to: alt)
        let altSumme = try Pruefsumme.sha1Base64(datei: alt)

        let transport = FunktionsTransport { operation, body in
            switch operation {
            case "checkBulkUpload":
                // Kennung und Prüfsumme aus der Anfrage lesen und passend antworten.
                let json = try! JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: [[String: String]]]
                let e = json["assets"]![0]
                if e["checksum"] == altSumme {
                    return (200, #"{"results":[{"id":"\#(e["id"]!)","action":"reject","reason":"duplicate","assetId":"vorhanden-1","isTrashed":false}]}"#)
                }
                return (200, #"{"results":[{"id":"\#(e["id"]!)","action":"accept"}]}"#)
            case "addAssetsToAlbum":
                return (200, "[]")
            default:
                return (500, "{}")
            }
        }
        UploadAttrappe.sperre.withLock {
            UploadAttrappe.antwort = (201, #"{"id":"neu-1","status":"created"}"#)
            UploadAttrappe.anfragen = []
        }
        let client = ImmichClient(address: ServerAddress(eingabe: "foto.example.de")!, credential: .apiKey("k"),
                                  transport: transport, uploadSession: UploadAttrappe.session())
        let db = try Datenbank.imSpeicher()
        let arbeitsordner = tempOrdner()
        let schlange = UploadWarteschlange(client: client, db: db, konto: "test", ordner: arbeitsordner, uploader: UploadAttrappe.uploader())
        var fertig = false
        schlange.onDurchgangFertig = { fertig = true }

        let anzahl = try await schlange.fuegeHinzu([neu, alt], quelle: "test", albumId: "album-1")
        #expect(anzahl == 2)
        for _ in 0..<200 where !fertig { try await Task.sleep(for: .milliseconds(20)) }

        #expect(fertig)
        #expect(schlange.stand.hochgeladen == 1)
        #expect(schlange.stand.duplikate == 1)
        #expect(schlange.stand.fehler == 0)
        #expect(UploadAttrappe.sperre.withLock { UploadAttrappe.anfragen.count } == 1)
        // Beide landen im Album (auch das schon vorhandene).
        #expect(transport.aufrufe.filter { $0 == "addAssetsToAlbum" }.count == 2)
        // Datenbank und Kopien sind aufgeräumt.
        #expect(try db.offeneAuftraege(konto: "test").isEmpty)
        let rest = try FileManager.default.contentsOfDirectory(atPath: arbeitsordner.path)
        #expect(rest.isEmpty)
        // Die Originale bleiben unangetastet.
        #expect(FileManager.default.fileExists(atPath: neu.path))
    }

    @Test("Zu große Datei landet in der Fehlerliste, der Rest läuft weiter")
    func zuGross() async throws {
        let quelle = tempOrdner()
        let video = quelle.appending(path: "riesig.mov")
        try Data("video".utf8).write(to: video)
        let transport = FunktionsTransport { operation, body in
            let json = try! JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: [[String: String]]]
            return (200, #"{"results":[{"id":"\#(json["assets"]![0]["id"]!)","action":"accept"}]}"#)
        }
        UploadAttrappe.sperre.withLock { UploadAttrappe.antwort = (413, "{}") }
        let client = ImmichClient(address: ServerAddress(eingabe: "foto.example.de")!, transport: transport,
                                  uploadSession: UploadAttrappe.session())
        let db = try Datenbank.imSpeicher()
        let schlange = UploadWarteschlange(client: client, db: db, konto: "test", ordner: tempOrdner(), uploader: UploadAttrappe.uploader())
        var fertig = false
        schlange.onDurchgangFertig = { fertig = true }
        try await schlange.fuegeHinzu([video], quelle: "test")
        for _ in 0..<200 where !fertig { try await Task.sleep(for: .milliseconds(20)) }

        #expect(schlange.stand.fehler == 1)
        #expect(schlange.fehlerListe().first?.fehler == ImmichError.dateiZuGross.errorDescription)
        schlange.verwirfFehler()
        #expect(schlange.fehlerListe().isEmpty)
    }

    @Test("Nach einem Absturz geht es weiter")
    func wiederaufnahme() throws {
        let db = try Datenbank.imSpeicher()
        var a = UploadAuftrag(konto: "k", quelle: "test", datei: "/tmp/x.jpg", dateiname: "x.jpg", erstellt: .now, geaendert: .now)
        a = try db.speichere([a])[0]
        a.zustand = .laeuft
        try db.aktualisiere(a)
        try db.setzeLaufendeZurueck(konto: "k")
        #expect(try db.offeneAuftraege(konto: "k").first?.zustand == .wartet)
        #expect(try db.offeneAuftraege(konto: "anderes").isEmpty)
    }
}
