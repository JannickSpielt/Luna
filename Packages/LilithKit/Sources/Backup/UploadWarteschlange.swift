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

    public init(client: ImmichClient, db: Datenbank, konto: String, ordner: URL? = nil) {
        self.client = client
        self.db = db
        self.konto = konto
        self.ordner = ordner ?? Self.standardOrdner(konto: konto)
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
        try? db.setzeLaufendeZurueck(konto: konto)
        let offen = (try? db.offeneAuftraege(konto: konto)) ?? []
        if !offen.isEmpty, arbeit == nil {
            halt = nil
            stand = Stand(gesamt: offen.count)
            arbeite()
        }
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
        halt = nil
        arbeite()
        return auftraege.count
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
            entferneKopie(a)
            try? db.entferne(a)
        }
        stand.fehler = 0
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
            while let naechster = (try? db.offeneAuftraege(konto: konto))?.first {
                let weiter = await bearbeite(naechster)
                if !weiter { break }
            }
            try? db.entferneErledigte(konto: konto)
            stand.laeuft = false
            stand.anteil = 0
            arbeit = nil
            onDurchgangFertig?()
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
                let upload = UploadDatei(datei: datei, dateiname: a.dateiname, erstellt: a.erstellt, geaendert: a.geaendert,
                                         dauerMs: a.dauerMs, pruefsumme: a.pruefsumme)
                let ergebnis = try await client.ladeHoch(upload, arbeitsordner: ordner) { anteil in
                    Task { @MainActor [weak self] in self?.stand.anteil = anteil }
                }
                a.remoteId = ergebnis.id
                a.zustand = ergebnis.duplikat ? .duplikat : .fertig
                if ergebnis.duplikat { stand.duplikate += 1 } else { stand.hochgeladen += 1 }
            }
            if let album = a.albumId, let id = a.remoteId {
                // Scheitert nur das Album, ist das Foto trotzdem sicher auf dem Server.
                try? await client.nachUpload(albumId: album, assetIds: [id])
            }
            a.fehler = nil
            try? db.aktualisiere(a)
            entferneKopie(a)
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
        return true
    }

    private func entferneKopie(_ a: UploadAuftrag) {
        let datei = URL(fileURLWithPath: a.datei)
        try? FileManager.default.removeItem(at: datei.deletingLastPathComponent())
    }
}
