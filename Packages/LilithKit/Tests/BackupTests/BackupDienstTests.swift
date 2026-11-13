import CoreGraphics
import Foundation
import Testing
@testable import Backup
@testable import Networking
@testable import Persistence

/// Nachgebaute Mediathek: Prüfsummen sind „summe-<id>“, Exporte schreiben kleine Dateien.
final class TestMediathek: Mediathek, @unchecked Sendable {
    var medien: [MediumKopf]
    var live: Set<String> = []
    var nurICloud: Set<String> = []
    /// Album-ID → Foto-IDs.
    var albenInhalt: [String: Set<String>] = [:]
    private(set) var exportiert: [String] = []

    init(_ ids: [String]) {
        medien = ids.enumerated().map { i, id in
            MediumKopf(id: id, erstellt: Date(timeIntervalSince1970: Double(1000 + i)),
                       geaendert: Date(timeIntervalSince1970: Double(1000 + i)), istVideo: false)
        }
    }

    func zugriff() -> MediathekZugriff { .voll }
    func frageZugriff() async -> MediathekZugriff { .voll }
    func alleMedien() async throws -> [MediumKopf] { medien }

    func pruefsumme(_ id: String, iCloud: Bool) async throws -> String {
        if nurICloud.contains(id), !iCloud { throw MediathekFehler.nurInICloud }
        return "summe-\(id)"
    }

    func exportiere(_ id: String, nach ordner: URL, iCloud: Bool) async throws -> ExportiertesMedium {
        exportiert.append(id)
        let datei = ordner.appending(path: "\(id).heic")
        try Data("foto \(id)".utf8).write(to: datei)
        var video: URL?
        if live.contains(id) {
            video = ordner.appending(path: "\(id)_live.mov")
            try Data("video \(id)".utf8).write(to: video!)
        }
        return ExportiertesMedium(datei: datei, dateiname: "\(id).heic", liveVideo: video)
    }

    func alben() async -> [MediathekAlbum] {
        albenInhalt.keys.sorted().map { MediathekAlbum(id: $0, titel: $0, anzahl: albenInhalt[$0]!.count) }
    }
    func medienIds(inAlbum id: String) async -> Set<String> { albenInhalt[id] ?? [] }
    func vorschau(_ id: String, kante: CGFloat) async -> CGImage? { nil }
    func loesche(_ ids: [String]) async throws { medien.removeAll { ids.contains($0.id) } }
}

extension WarteschlangeTests {
    /// Server kennt nur „summe-a“, alles andere nimmt er an.
    static func backupServer() -> FunktionsTransport {
        FunktionsTransport { operation, body in
            guard operation == "checkBulkUpload" else { return (500, "{}") }
            let json = try! JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: [[String: String]]]
            let ergebnisse = json["assets"]!.map { e in
                e["checksum"] == "summe-a"
                    ? #"{"id":"\#(e["id"]!)","action":"reject","reason":"duplicate","assetId":"server-a","isTrashed":false}"#
                    : #"{"id":"\#(e["id"]!)","action":"accept"}"#
            }
            return (200, #"{"results":[\#(ergebnisse.joined(separator: ","))]}"#)
        }
    }

    func dienst(_ mediathek: TestMediathek, db: Datenbank, transport: FunktionsTransport, aktiv: Bool = true,
                umgebung: TestUmgebung? = nil, einstellungen: BackupEinstellungen? = nil) -> (BackupDienst, URL) {
        let client = ImmichClient(address: ServerAddress(eingabe: "foto.example.de")!, credential: .apiKey("k"),
                                  transport: transport, uploadSession: UploadAttrappe.session())
        let ordner = tempOrdner()
        let schlange = UploadWarteschlange(client: client, db: db, konto: "k", ordner: ordner, uploader: UploadAttrappe.uploader())
        let speicher = UserDefaults(suiteName: "lilith-test-\(UUID().uuidString)")!
        speicher.set(aktiv, forKey: "lilith.backup.aktiv.k")
        // In den Tests ohne iCloud, sofern nicht anders angegeben.
        var e = einstellungen ?? BackupEinstellungen()
        if einstellungen == nil { e.iCloud = false }
        speicher.set(try! JSONEncoder().encode(e), forKey: "lilith.backup.einstellungen.k")
        return (BackupDienst(client: client, db: db, konto: "k", mediathek: mediathek, uploads: schlange, speicher: speicher,
                             umgebung: umgebung), ordner)
    }

    @Test("Backup lädt nur Fehlendes hoch, Live Photos mit Video, iCloud-Fotos werden übersprungen")
    func backupDurchgang() async throws {
        let mediathek = TestMediathek(["a", "b", "c", "d"])
        mediathek.live = ["c"]
        mediathek.nurICloud = ["d"]
        UploadAttrappe.sperre.withLock {
            UploadAttrappe.antwort = (201, #"{"id":"neu-1","status":"created"}"#)
            UploadAttrappe.anfragen = []
        }
        let db = try Datenbank.imSpeicher()
        let (dienst, ordner) = dienst(mediathek, db: db, transport: Self.backupServer())

        await dienst.lauf()

        #expect(dienst.phase == .bereit)
        #expect(dienst.uebersicht == .init(gesamt: 4, gesichert: 3, fehler: 0, uebersprungen: 1))
        // „a“ war schon da und wird gar nicht erst exportiert.
        #expect(mediathek.exportiert.sorted() == ["b", "c"])
        // b, das Video von c und das Foto c.
        #expect(UploadAttrappe.sperre.withLock { UploadAttrappe.anfragen.count } == 3)
        #expect(try db.lokaleFotos(konto: "k", zustand: .uebersprungen).first?.grund == MediathekFehler.nurInICloud.errorDescription)
        #expect(try db.lokaleFotos(konto: "k", zustand: .gesichert).first { $0.lokaleId == "a" }?.remoteId == "server-a")
        #expect(try FileManager.default.contentsOfDirectory(atPath: ordner.path).isEmpty)

        // Zweiter Durchgang: nichts Neues, also kein Upload. Gelöschtes verschwindet aus der Zählung.
        mediathek.medien.removeAll { $0.id == "a" }
        await dienst.lauf()
        #expect(UploadAttrappe.sperre.withLock { UploadAttrappe.anfragen.count } == 3)
        #expect(dienst.uebersicht.gesamt == 3)
        #expect(dienst.statusText.hasPrefix("Alles gesichert"))
    }

    @Test("Albenauswahl: nur gewählte Alben, ausgeschlossene nie")
    func albenAuswahl() async throws {
        let mediathek = TestMediathek(["a", "b", "c", "d"])
        mediathek.albenInhalt = ["Urlaub": ["b", "c"], "Screenshots": ["c", "d"]]
        let db = try Datenbank.imSpeicher()
        // Ausgeschaltet, damit `setze` keinen echten Durchgang startet.
        let (dienst, _) = dienst(mediathek, db: db, transport: Self.backupServer(), aktiv: false)
        let alle = try await mediathek.alleMedien()

        // Voreinstellung: alles.
        #expect(await dienst.filtere(alle).count == 4)
        // Alles außer Screenshots.
        var auswahl = AlbenAuswahl()
        auswahl.ausgeschlossen = ["Screenshots"]
        dienst.setze(auswahl: auswahl)
        #expect(await dienst.filtere(alle).map(\.id) == ["a", "b"])
        // Nur Urlaub, aber ohne Screenshots: c liegt in beiden und fällt raus.
        dienst.setze(auswahl: AlbenAuswahl(gewaehlt: ["Urlaub"], ausgeschlossen: ["Screenshots"]))
        #expect(await dienst.filtere(alle).map(\.id) == ["b"])
    }

    @Test("Ohne WLAN wird verglichen, aber nicht hochgeladen")
    func ohneWLAN() async throws {
        UploadAttrappe.sperre.withLock {
            UploadAttrappe.antwort = (201, #"{"id":"neu-1","status":"created"}"#)
            UploadAttrappe.anfragen = []
        }
        let umgebung = TestUmgebung()
        umgebung.imWLAN = false
        let db = try Datenbank.imSpeicher()
        let mediathek = TestMediathek(["a", "b"])
        var e = BackupEinstellungen()
        e.iCloud = false
        let (dienst, _) = dienst(mediathek, db: db, transport: Self.backupServer(), umgebung: umgebung, einstellungen: e)
        await dienst.lauf()
        #expect(dienst.phase == .halt("Wartet auf WLAN"))
        #expect(dienst.uebersicht.gesichert == 1)   // „a“ war schon auf dem Server
        #expect(mediathek.exportiert.isEmpty)
        #expect(UploadAttrappe.sperre.withLock { UploadAttrappe.anfragen.count } == 0)

        // Mit WLAN geht es weiter.
        umgebung.imWLAN = true
        await dienst.lauf()
        #expect(dienst.phase == .bereit)
        #expect(dienst.uebersicht.gesichert == 2)
    }

    @Test("Videos ausgeschaltet, iCloud-Originale erlaubt")
    func videosUndICloud() async throws {
        let mediathek = TestMediathek(["a", "b"])
        mediathek.medien.append(MediumKopf(id: "v", erstellt: .now, geaendert: .now, istVideo: true))
        mediathek.nurICloud = ["b"]
        let db = try Datenbank.imSpeicher()
        var e = BackupEinstellungen()
        e.videos = false
        e.iCloud = true
        let (dienst, _) = dienst(mediathek, db: db, transport: Self.backupServer(), aktiv: false, einstellungen: e)
        #expect(await dienst.filtere(mediathek.medien).map(\.id) == ["a", "b"])
        // Mit iCloud klappt die Prüfsumme auch für „b“.
        #expect(try await mediathek.pruefsumme("b", iCloud: dienst.einstellungen.iCloud) == "summe-b")
    }

    @Test("Antippen wechselt neutral → gewählt → ausgeschlossen → neutral")
    func antippen() {
        var a = AlbenAuswahl(gewaehlt: [])
        a.weiter("x"); #expect(a.zustand("x") == .gewaehlt)
        a.weiter("x"); #expect(a.zustand("x") == .ausgeschlossen)
        a.weiter("x"); #expect(a.zustand("x") == .neutral)
    }

    @Test("Bearbeitete Fotos werden neu geprüft")
    func bearbeitet() throws {
        let db = try Datenbank.imSpeicher()
        let kopf = MediumKopf(id: "x", erstellt: .init(timeIntervalSince1970: 0), geaendert: .init(timeIntervalSince1970: 0), istVideo: false)
        try db.gleicheAb(konto: "k", medien: [kopf])
        var f = try db.lokaleFotos(konto: "k", zustand: .neu)[0]
        f.pruefsumme = "alt"
        f.zustand = .gesichert
        try db.aktualisiere([f])

        var neu = kopf
        neu.geaendert = .init(timeIntervalSince1970: 100)
        try db.gleicheAb(konto: "k", medien: [neu])
        let wieder = try db.lokaleFotos(konto: "k", zustand: .neu)
        #expect(wieder.count == 1)
        #expect(wieder.first?.pruefsumme == nil)
    }

    @Test("Hängengebliebene Einträge werden nach einem Absturz wieder bereit")
    func aufraeumen() throws {
        let db = try Datenbank.imSpeicher()
        try db.gleicheAb(konto: "k", medien: [MediumKopf(id: "y", erstellt: .now, geaendert: .now, istVideo: false)])
        try db.setzeLokal(konto: "k", lokaleId: "y", zustand: .eingereiht)
        try db.raeumeLokalAuf(konto: "k")
        #expect(try db.lokaleFotos(konto: "k", zustand: .bereit).count == 1)
    }
}

@MainActor
final class TestUmgebung: Umgebung {
    var imWLAN = true
    var amStrom = true
    var freierSpeicher: Int64 = 100_000_000_000
}

extension WarteschlangeTests {
    @Test("Zählertext: alles gesichert, sonst nur die neuen Fotos")
    func zaehler() async throws {
        let mediathek = TestMediathek(["a", "b", "c", "d"])
        UploadAttrappe.sperre.withLock {
            UploadAttrappe.antwort = (201, #"{"id":"neu-1","status":"created"}"#)
            UploadAttrappe.anfragen = []
        }
        let db = try Datenbank.imSpeicher()
        let (dienst, _) = dienst(mediathek, db: db, transport: Self.backupServer())
        await dienst.lauf()
        #expect(dienst.zaehlerText == "Alles gesichert")
    }
}
