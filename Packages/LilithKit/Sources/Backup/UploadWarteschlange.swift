import Foundation
import Observation
import Networking
import Persistence

/// Nimmt Dateien entgegen und lädt sie nacheinander hoch: Prüfsumme berechnen, beim Server
/// nachfragen, nur Fehlendes hochladen, danach ins Ziel-Album. Jeder Schritt steht in der Datenbank.
@MainActor
@Observable
public final class UploadWarteschlange {
    /// Was die Oberfläche anzeigt.
    public struct Stand: Equatable, Sendable {
        public var gesamt = 0
        public var hochgeladen = 0
        public var duplikate = 0
        public var fehler = 0
        /// Fortschritt der gerade laufenden Datei (0…1).
        public var anteil = 0.0
        public var laeuft = false
        /// Davon per Hand hinzugefügt (für die Live Activity bei großen Uploads).
        public var manuell = 0
        public var erledigt: Int { hochgeladen + duplikate + fehler }
        /// Gesamtfortschritt über alle Dateien dieses Durchgangs.
        public var gesamtAnteil: Double { gesamt == 0 ? 0 : min(1, (Double(erledigt) + anteil) / Double(gesamt)) }
    }

    public private(set) var stand = Stand()
    /// Grund, warum gerade nichts weitergeht (z. B. Kontingent voll). Die Oberfläche zeigt ihn an.
    public private(set) var halt: String?

    @ObservationIgnored public var onDurchgangFertig: (() -> Void)?
    @ObservationIgnored public var onSitzungAbgelaufen: (() -> Void)?

    @ObservationIgnored private let client: ImmichClient
    @ObservationIgnored private let db: Datenbank
    @ObservationIgnored private let konto: String
    @ObservationIgnored private let ordner: URL
    @ObservationIgnored private var arbeit: Task<Void, Never>?
    @ObservationIgnored private let maxVersuche = 5
    @ObservationIgnored private var warter: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let uploader: HintergrundUpload
    /// Aufträge, die iOS gerade im Hintergrund hochlädt. Die Schleife fasst sie nicht an.
    @ObservationIgnored private var imHintergrund: Set<Int64> = []
    /// Automatisches Backup nur über WLAN (gilt nicht für Uploads per Hand).
    @ObservationIgnored public var nurWLANFuerMediathek = true

    /// Ordner für Upload-Dateien. Das Backup legt seine Exporte auch hier ab.
    public var arbeitsordner: URL { ordner }

    public init(client: ImmichClient, db: Datenbank, konto: String, ordner: URL? = nil,
                uploader: HintergrundUpload = .geteilt) {
        self.client = client
        self.db = db
        self.konto = konto
        self.ordner = ordner ?? Self.standardOrdner(konto: konto)
        self.uploader = uploader
        // Ergebnisse von Uploads, die im Hintergrund fertig wurden (auch nach einem Neustart).
        uploader.setzeAbschluss { [weak self] kennung, ergebnis in
            Task { @MainActor in self?.abschliessen(kennung, ergebnis) }
        }
    }

    /// Kopien der Dateien liegen hier, bis sie hochgeladen sind (übersteht einen Neustart).
    static func standardOrdner(konto: String) -> URL {
        let basis = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let sicher = konto.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return basis.appending(path: "Lilith/Uploads/\(sicher)", directoryHint: .isDirectory)
    }

    /// Beim App-Start: unterbrochene Aufträge fortsetzen.
    public func start() {
        Task {
            // Was iOS noch im Hintergrund hochlädt, bleibt „läuft“. Der Rest geht zurück in die Warteschlange.
            let laufend = await uploader.laufendeKennungen()
            imHintergrund = Set(laufend.compactMap { Int64($0) })
            try? db.setzeLaufendeZurueck(konto: konto, ausser: imHintergrund)
            let offen = ((try? db.offeneAuftraege(konto: konto)) ?? []).filter { !imHintergrund.contains($0.id ?? -1) }
            if !offen.isEmpty, arbeit == nil {
                halt = nil
                stand = Stand(gesamt: offen.count)
                arbeite()
            }
        }
    }

    /// Beim Verlassen der App: die nächsten Aufträge an iOS übergeben, damit sie ohne Lilith weiterlaufen.
    /// Nur Aufträge mit Prüfsumme und ohne Live-Video (die brauchen zwei Schritte nacheinander).
    public func uebergibAnHintergrund(hoechstens: Int = 30) {
        guard halt == nil else { return }
        let kandidaten = ((try? db.offeneAuftraege(konto: konto)) ?? []).filter {
            $0.zustand == .wartet && $0.pruefsumme != nil && $0.liveVideoDatei == nil && !imHintergrund.contains($0.id ?? -1)
        }.prefix(hoechstens)
        for var a in kandidaten {
            guard let id = a.id else { continue }
            do {
                try uploader.starte(uploadDatei(a), client: client, kennung: String(id))
                a.zustand = .laeuft
                try? db.aktualisiere(a)
                imHintergrund.insert(id)
            } catch {
                continue
            }
        }
    }

    /// Ein Hintergrund-Upload ist fertig.
    func abschliessen(_ kennung: String, _ ergebnis: Result<UploadErgebnis, ImmichError>) {
        guard let id = Int64(kennung), var a = try? db.auftrag(id: id) else { return }
        imHintergrund.remove(id)
        switch ergebnis {
        case .success(let e):
            a.remoteId = e.id
            a.zustand = e.duplikat ? .duplikat : .fertig
            if e.duplikat { stand.duplikate += 1 } else { stand.hochgeladen += 1 }
            erfolg(a)
        case .failure(let fehler):
            _ = behandle(fehler, &a)
        }
        if arbeit == nil, imHintergrund.isEmpty {
            try? db.entferneErledigte(konto: konto)
            onDurchgangFertig?()
        }
    }

    private func uploadDatei(_ a: UploadAuftrag, livePhotoVideoId: String? = nil) -> UploadDatei {
        UploadDatei(datei: URL(fileURLWithPath: a.datei), dateiname: a.dateiname, erstellt: a.erstellt, geaendert: a.geaendert,
                    dauerMs: a.dauerMs, livePhotoVideoId: livePhotoVideoId, pruefsumme: a.pruefsumme,
                    nurWLAN: a.quelle == "mediathek" && nurWLANFuerMediathek)
    }

    /// Nach erfolgreichem Upload (oder Duplikat): Album, Stand der Mediathek, Kopie löschen.
    private func erfolg(_ auftrag: UploadAuftrag) {
        var a = auftrag
        a.fehler = nil
        try? db.aktualisiere(a)
        if let lokal = a.lokaleId {
            try? db.setzeLokal(konto: konto, lokaleId: lokal, zustand: .gesichert, remoteId: a.remoteId)
        }
        if let album = a.albumId, let id = a.remoteId {
            // Scheitert nur das Album, ist das Foto trotzdem sicher auf dem Server.
            let client = self.client
            Task { try? await client.nachUpload(albumId: album, assetIds: [id]) }
        }
        entferneKopie(a)
    }

    /// Nimmt Dateien auf. Sie werden kopiert, damit der Upload auch nach einem Neustart weitergehen kann.
    /// - Parameter albumId: Ziel-Album, falls aus einem Album heraus hochgeladen wird.
    @discardableResult
    public func fuegeHinzu(_ urls: [URL], quelle: String, albumId: String? = nil) async throws -> Int {
        let ordner = self.ordner
        let konto = self.konto
        let auftraege = try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            var neu: [UploadAuftrag] = []
            for url in ImportVorbereitung.sammleMedien(urls) {
                let ziel = ordner.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
                let kopie = ziel.appending(path: url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: kopie)
                let angaben = await ImportVorbereitung.angaben(fuer: kopie)
                neu.append(UploadAuftrag(konto: konto, quelle: quelle, datei: kopie.path, dateiname: url.lastPathComponent,
                                         erstellt: angaben.erstellt, geaendert: angaben.geaendert,
                                         dauerMs: angaben.dauerMs, istVideo: angaben.istVideo, albumId: albumId))
            }
            return neu
        }.value
        guard !auftraege.isEmpty else { return 0 }
        _ = try db.speichere(auftraege)
        if !stand.laeuft { stand = Stand() }
        stand.gesamt += auftraege.count
        stand.manuell += auftraege.count
        halt = nil
        arbeite()
        return auftraege.count
    }

    /// Fertig vorbereitete Aufträge aufnehmen (die Dateien liegen schon im Arbeitsordner).
    public func reiheEin(_ auftraege: [UploadAuftrag]) throws {
        guard !auftraege.isEmpty else { return }
        let gespeichert = try db.speichere(auftraege)
        for a in gespeichert {
            if let lokal = a.lokaleId { try? db.setzeLokal(konto: konto, lokaleId: lokal, zustand: .eingereiht) }
        }
        if !stand.laeuft { stand = Stand() }
        stand.gesamt += gespeichert.count
        halt = nil
        arbeite()
    }

    /// Wartet, bis die Warteschlange nichts mehr zu tun hat (oder angehalten hat).
    public func warteBisFertig() async {
        guard arbeit != nil else { return }
        await withCheckedContinuation { warter.append($0) }
    }

    /// Gescheiterte Aufträge noch einmal versuchen.
    public func wiederhole() {
        let gescheitert = (try? db.auftraege(konto: konto, zustand: .fehler)) ?? []
        guard !gescheitert.isEmpty else { return }
        for var a in gescheitert {
            a.zustand = .wartet
            a.versuche = 0
            a.fehler = nil
            try? db.aktualisiere(a)
        }
        stand = Stand(gesamt: gescheitert.count)
        halt = nil
        arbeite()
    }

    /// Gescheiterte Aufträge verwerfen (Kopien werden gelöscht).
    public func verwirfFehler() {
        for a in (try? db.auftraege(konto: konto, zustand: .fehler)) ?? [] {
            if let lokal = a.lokaleId {
                // Nicht beim nächsten Durchgang wieder versuchen.
                try? db.setzeLokal(konto: konto, lokaleId: lokal, zustand: .uebersprungen, grund: "Verworfen")
            }
            entferneKopie(a)
            try? db.entferne(a)
        }
        stand.fehler = 0
    }

    /// Ein gescheiterter Auftrag für die Fehlerliste.
    public struct FehlerEintrag: Identifiable, Sendable, Hashable {
        public let id: Int64
        public let dateiname: String
        public let fehler: String
        /// Kennung in der Mediathek (automatisches Backup), sonst `nil`.
        public let lokaleId: String?
        /// Pfad der Kopie (für die Vorschau).
        public let datei: String
    }

    public func fehlerEintraege() -> [FehlerEintrag] {
        ((try? db.auftraege(konto: konto, zustand: .fehler)) ?? []).compactMap { a in
            a.id.map { FehlerEintrag(id: $0, dateiname: a.dateiname, fehler: a.fehler ?? "Unbekannter Fehler",
                                     lokaleId: a.lokaleId, datei: a.datei) }
        }
    }

    /// Einen einzelnen gescheiterten Auftrag erneut versuchen.
    public func wiederhole(_ id: Int64) {
        guard var a = try? db.auftrag(id: id), a.zustand == .fehler else { return }
        a.zustand = .wartet
        a.versuche = 0
        a.fehler = nil
        try? db.aktualisiere(a)
        if let lokal = a.lokaleId { try? db.setzeLokal(konto: konto, lokaleId: lokal, zustand: .eingereiht) }
        if !stand.laeuft { stand = Stand() }
        stand.gesamt += 1
        if stand.fehler > 0 { stand.fehler -= 1 }
        halt = nil
        arbeite()
    }

    /// Einen einzelnen gescheiterten Auftrag verwerfen (die Kopie wird gelöscht).
    public func verwirf(_ id: Int64) {
        guard let a = try? db.auftrag(id: id), a.zustand == .fehler else { return }
        if let lokal = a.lokaleId {
            try? db.setzeLokal(konto: konto, lokaleId: lokal, zustand: .uebersprungen, grund: "Verworfen")
        }
        entferneKopie(a)
        try? db.entferne(a)
        if stand.fehler > 0 { stand.fehler -= 1 }
    }

    /// Fehlertexte der gescheiterten Aufträge, für die Anzeige.
    public func fehlerListe() -> [(dateiname: String, fehler: String)] {
        ((try? db.auftraege(konto: konto, zustand: .fehler)) ?? []).map { ($0.dateiname, $0.fehler ?? "Unbekannter Fehler") }
    }

    // MARK: - Arbeit

    private func arbeite() {
        guard arbeit == nil else { return }
        stand.laeuft = true
        arbeit = Task {
            while let naechster = (try? db.offeneAuftraege(konto: konto))?.first(where: { !imHintergrund.contains($0.id ?? -1) }) {
                let weiter = await bearbeite(naechster)
                if !weiter { break }
            }
            try? db.entferneErledigte(konto: konto)
            stand.laeuft = false
            stand.anteil = 0
            arbeit = nil
            onDurchgangFertig?()
            let wartende = warter
            warter = []
            for w in wartende { w.resume() }
        }
    }

    /// Ein Auftrag. Gibt `false` zurück, wenn die ganze Warteschlange anhalten soll.
    private func bearbeite(_ auftrag: UploadAuftrag) async -> Bool {
        var a = auftrag
        a.zustand = .laeuft
        try? db.aktualisiere(a)
        stand.anteil = 0
        let datei = URL(fileURLWithPath: a.datei)

        do {
            if a.pruefsumme == nil {
                a.pruefsumme = try await Task.detached(priority: .utility) { try Pruefsumme.sha1Base64(datei: datei) }.value
                try? db.aktualisiere(a)
            }
            let kennung = String(a.id ?? 0)
            let vorab = try await client.pruefeVorab([(kennung, a.pruefsumme!)])[kennung] ?? .hochladen

            switch vorab {
            case .vorhanden(let id, _):
                a.zustand = .duplikat
                a.remoteId = id
                stand.duplikate += 1
            case .abgelehnt:
                throw ImmichError.formatNichtUnterstuetzt
            case .hochladen:
                // Live Photo: zuerst das Video (versteckt), dann das Foto mit Verweis darauf.
                var videoId: String?
                if let live = a.liveVideoDatei {
                    videoId = try await ladeLiveVideoHoch(URL(fileURLWithPath: live), fuer: a)
                }
                let ergebnis = try await uploader.ladeHoch(uploadDatei(a, livePhotoVideoId: videoId), client: client,
                                                           kennung: String(a.id ?? 0)) { anteil in
                    Task { @MainActor [weak self] in self?.stand.anteil = anteil }
                }
                a.remoteId = ergebnis.id
                a.zustand = ergebnis.duplikat ? .duplikat : .fertig
                if ergebnis.duplikat { stand.duplikate += 1 } else { stand.hochgeladen += 1 }
            }
            if let album = a.albumId, let id = a.remoteId {
                // Scheitert nur das Album, ist das Foto trotzdem sicher auf dem Server.
                try? await client.nachUpload(albumId: album, assetIds: [id])
                a.albumId = nil
            }
            erfolg(a)
            return true
        } catch {
            return behandle(error, &a)
        }
    }

    private func behandle(_ error: any Error, _ a: inout UploadAuftrag) -> Bool {
        let fehler = error as? ImmichError
        a.versuche += 1
        a.fehler = error.localizedDescription
        switch fehler {
        case .sitzungAbgelaufen:
            a.zustand = .wartet
            try? db.aktualisiere(a)
            halt = ImmichError.sitzungAbgelaufen.errorDescription
            onSitzungAbgelaufen?()
            return false
        case .kontingentVoll:
            a.zustand = .wartet
            try? db.aktualisiere(a)
            halt = fehler?.errorDescription
            return false
        case .nichtErreichbar:
            if a.versuche < maxVersuche {
                a.zustand = .wartet
                try? db.aktualisiere(a)
                halt = "Server nicht erreichbar. Lilith versucht es erneut, wenn du wieder hochlädst oder die App öffnest."
                return false
            }
            a.zustand = .fehler
        default:
            // Dateifehler, zu groß, Format: ein neuer Versuch ändert nichts.
            a.zustand = .fehler
        }
        stand.fehler += 1
        try? db.aktualisiere(a)
        if let lokal = a.lokaleId {
            try? db.setzeLokal(konto: konto, lokaleId: lokal, zustand: .fehler, grund: a.fehler)
        }
        return true
    }

    /// Lädt das Video eines Live Photos versteckt hoch (oder findet es auf dem Server) und gibt seine ID zurück.
    private func ladeLiveVideoHoch(_ video: URL, fuer a: UploadAuftrag) async throws -> String {
        let summe = try await Task.detached(priority: .utility) { try Pruefsumme.sha1Base64(datei: video) }.value
        let vorab = try await client.pruefeVorab([("live", summe)])["live"] ?? .hochladen
        if case .vorhanden(let id, _) = vorab { return id }
        let upload = UploadDatei(datei: video, dateiname: video.lastPathComponent, erstellt: a.erstellt, geaendert: a.geaendert,
                                 versteckt: true, pruefsumme: summe, nurWLAN: a.quelle == "mediathek" && nurWLANFuerMediathek)
        return try await uploader.ladeHoch(upload, client: client, kennung: "\(a.id ?? 0)-live").id
    }

    private func entferneKopie(_ a: UploadAuftrag) {
        let datei = URL(fileURLWithPath: a.datei)
        try? FileManager.default.removeItem(at: datei.deletingLastPathComponent())
    }
}
