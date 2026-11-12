import Foundation
import Testing
@testable import Backup
@testable import Networking
@testable import Persistence

extension WarteschlangeTests {
    @Test("Beim Verlassen der App gehen Aufträge an iOS, das Ergebnis wird danach eingetragen")
    func uebergabe() async throws {
        UploadAttrappe.sperre.withLock {
            UploadAttrappe.antwort = (201, #"{"id":"neu-9","status":"created"}"#)
            UploadAttrappe.anfragen = []
        }
        let ordner = tempOrdner()
        let kopie = ordner.appending(path: "x/foto.heic")
        try FileManager.default.createDirectory(at: kopie.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("foto".utf8).write(to: kopie)
        let db = try Datenbank.imSpeicher()
        try db.gleicheAb(konto: "k", medien: [MediumKopf(id: "m1", erstellt: .now, geaendert: .now, istVideo: false)])
        var a = UploadAuftrag(konto: "k", quelle: "mediathek", datei: kopie.path, dateiname: "foto.heic",
                              erstellt: .now, geaendert: .now, lokaleId: "m1")
        a.pruefsumme = "summe"
        _ = try db.speichere([a])

        let client = ImmichClient(address: ServerAddress(eingabe: "foto.example.de")!, credential: .apiKey("k"))
        let schlange = UploadWarteschlange(client: client, db: db, konto: "k", ordner: ordner, uploader: UploadAttrappe.uploader())
        var fertig = false
        schlange.onDurchgangFertig = { fertig = true }

        schlange.uebergibAnHintergrund()
        #expect(try db.offeneAuftraege(konto: "k").first?.zustand == .laeuft)
        for _ in 0..<200 where !fertig { try await Task.sleep(for: .milliseconds(20)) }

        #expect(fertig)
        #expect(try db.offeneAuftraege(konto: "k").isEmpty)
        #expect(try db.lokaleFotos(konto: "k", zustand: .gesichert).first?.remoteId == "neu-9")
        #expect(!FileManager.default.fileExists(atPath: kopie.path))
        // Nur WLAN beim automatischen Backup.
        let anfrage = UploadAttrappe.sperre.withLock { UploadAttrappe.anfragen.first }
        #expect(anfrage?.allowsCellularAccess == false)
    }
}
