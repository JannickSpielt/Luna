import CoreGraphics
import Foundation
import Observation
import Networking
import Persistence

/// Automatisches Backup der Mediathek, solange die App offen ist (Etappe 2).
/// Ablauf: Mediathek lesen → Prüfsummen berechnen → beim Server nachfragen (bis 100 auf einmal)
/// → nur Fehlendes exportieren und über die Upload-Warteschlange hochladen.
@MainActor
@Observable
public final class BackupDienst {
    public enum Phase: Equatable, Sendable {
        case aus
        /// Eingeschaltet, gerade nichts zu tun.
        case bereit
        case liest
        case prueft(erledigt: Int, gesamt: Int)
        case sichert
        /// Grund, warum es nicht weitergeht.
        case halt(String)
    }

    public struct Uebersicht: Equatable, Sendable {
        public var gesamt = 0
        public var gesichert = 0
        public var fehler = 0
        public var uebersprungen = 0
        public var offen: Int { max(0, gesamt - gesichert - fehler - uebersprungen) }
        /// 0 (Neumond) bis 1 (Vollmond).
        public var anteil: Double { gesamt == 0 ? 0 : Double(gesichert) / Double(gesamt) }

        public init(gesamt: Int = 0, gesichert: Int = 0, fehler: Int = 0, uebersprungen: Int = 0) {
            self.gesamt = gesamt; self.gesichert = gesichert; self.fehler = fehler; self.uebersprungen = uebersprungen
        }
    }

    public private(set) var aktiv: Bool
    public private(set) var zugriff: MediathekZugriff
    public private(set) var phase: Phase
    public private(set) var uebersicht = Uebersicht()
    public private(set) var letzterAbschluss: Date?
    /// Welche Alben gesichert werden.
    public private(set) var auswahl: AlbenAuswahl
    /// Gewählte iPhone-Alben auch auf dem Server anlegen und füllen.
    public private(set) var serverAlben: Bool
    /// WLAN, Laden, Videos, iCloud.
    public private(set) var einstellungen: BackupEinstellungen

    @ObservationIgnored public var onSitzungAbgelaufen: (() -> Void)?
    /// Der Stand einzelner Fotos hat sich geändert (z. B. für die Anzeige in der Bibliothek).
    @ObservationIgnored public var onAenderung: (() -> Void)?

    @ObservationIgnored private let client: ImmichClient?
    @ObservationIgnored private let db: Datenbank?
    @ObservationIgnored private let konto: String
    @ObservationIgnored private let mediathek: any Mediathek
    @ObservationIgnored private let uploads: UploadWarteschlange?
    @ObservationIgnored private let speicher: UserDefaults
    @ObservationIgnored private let umgebung: (any Umgebung)?
    /// Unter diesem freien Speicher wird nichts mehr exportiert.
    @ObservationIgnored var mindestSpeicher: Int64 = 1_000_000_000
    @ObservationIgnored private var laufAufgabe: Task<Void, Never>?
    /// Wie viele Fotos auf einmal exportiert werden (begrenzt den Platz für Upload-Dateien).
    @ObservationIgnored var exportBlock = 20
    @ObservationIgnored var pruefBlock = 100
    @ObservationIgnored private var starteNachLauf = false

    private var schluesselAktiv: String { "lilith.backup.aktiv.\(konto)" }
    private var schluesselAbschluss: String { "lilith.backup.abschluss.\(konto)" }
    private var schluesselAuswahl: String { "lilith.backup.alben.\(konto)" }
    private var schluesselServerAlben: String { "lilith.backup.serveralben.\(konto)" }
    private var schluesselEinstellungen: String { "lilith.backup.einstellungen.\(konto)" }

    public init(client: ImmichClient?, db: Datenbank?, konto: String, mediathek: any Mediathek,
                uploads: UploadWarteschlange?, speicher: UserDefaults = .standard, umgebung: (any Umgebung)? = nil) {
        self.umgebung = umgebung
        self.client = client
        self.db = db
        self.konto = konto
        self.mediathek = mediathek
        self.uploads = uploads
        self.speicher = speicher
        let an = speicher.bool(forKey: "lilith.backup.aktiv.\(konto)")
        self.aktiv = an
        self.phase = an ? .bereit : .aus
        self.zugriff = mediathek.zugriff()
        self.letzterAbschluss = speicher.object(forKey: "lilith.backup.abschluss.\(konto)") as? Date
        self.auswahl = speicher.data(forKey: "lilith.backup.alben.\(konto)")
            .flatMap { try? JSONDecoder().decode(AlbenAuswahl.self, from: $0) } ?? AlbenAuswahl()
        self.serverAlben = speicher.bool(forKey: "lilith.backup.serveralben.\(konto)")
        self.einstellungen = speicher.data(forKey: "lilith.backup.einstellungen.\(konto)")
            .flatMap { try? JSONDecoder().decode(BackupEinstellungen.self, from: $0) } ?? BackupEinstellungen()
        uploads?.nurWLANFuerMediathek = einstellungen.nurWLAN
        zaehle()
    }

    /// Feste Werte für Vorschau und Bildschirmfotos (ohne Mediathek und Server).
    public static func vorschau(mediathek: any Mediathek) -> BackupDienst {
        let d = BackupDienst(client: nil, db: nil, konto: "vorschau", mediathek: mediathek, uploads: nil,
                             speicher: UserDefaults(suiteName: "lilith.vorschau") ?? .standard)
        d.aktiv = true
        d.zugriff = .voll
        d.phase = .sichert
        d.uebersicht = Uebersicht(gesamt: 9030, gesichert: 8412, fehler: 3)
        return d
    }

    // MARK: - Steuerung

    /// Schaltet das Backup ein. Fragt dafür nach Zugriff auf die Mediathek.
    @discardableResult
    public func einschalten() async -> Bool {
        zugriff = await mediathek.frageZugriff()
        guard zugriff == .voll || zugriff == .eingeschraenkt else {
            phase = .halt("Lilith hat keinen Zugriff auf deine Fotos. Erlaube ihn in den Einstellungen.")
            return false
        }
        aktiv = true
        speicher.set(true, forKey: schluesselAktiv)
        phase = .bereit
        starte()
        return true
    }

    public func ausschalten() {
        laufAufgabe?.cancel()
        laufAufgabe = nil
        aktiv = false
        speicher.set(false, forKey: schluesselAktiv)
        phase = .aus
    }

    /// Startet einen Durchgang, falls eingeschaltet und nicht schon einer läuft.
    public func starte() {
        guard aktiv, laufAufgabe == nil, client != nil else { return }
        laufAufgabe = Task {
            await lauf()
            laufAufgabe = nil
            // Wurde währenddessen die Auswahl geändert: gleich noch einmal.
            if starteNachLauf {
                starteNachLauf = false
                starte()
            }
        }
    }

    /// Hält an (z. B. wenn die App in den Hintergrund geht). Uploads in der Warteschlange laufen weiter.
    public func halteAn() {
        laufAufgabe?.cancel()
    }

    /// Nach Rückkehr aus den Einstellungen oder der Auswahl: Zugriff neu lesen.
    public func aktualisiereZugriff() {
        zugriff = mediathek.zugriff()
    }

    /// Neue Albenauswahl speichern. Wirkt beim nächsten Durchgang, der gleich startet.
    public func setze(auswahl neu: AlbenAuswahl) {
        auswahl = neu
        speicher.set(try? JSONEncoder().encode(neu), forKey: schluesselAuswahl)
        if laufAufgabe != nil { halteAn() }
        starteNachLauf = true
        starte()
    }

    public func setze(einstellungen neu: BackupEinstellungen) {
        einstellungen = neu
        speicher.set(try? JSONEncoder().encode(neu), forKey: schluesselEinstellungen)
        uploads?.nurWLANFuerMediathek = neu.nurWLAN
        if laufAufgabe != nil { halteAn() }
        starteNachLauf = true
        starte()
    }

    /// Ein ganzer Durchgang, auf den gewartet wird (für Läufe im Hintergrund).
    public func durchgang() async {
        if laufAufgabe == nil { starte() }
        await laufAufgabe?.value
    }

    /// Warum gerade nicht hochgeladen werden darf (`nil`: alles in Ordnung).
    func hindernis() -> String? {
        guard let umgebung else { return nil }
        if einstellungen.nurWLAN && !umgebung.imWLAN { return "Wartet auf WLAN" }
        if einstellungen.nurBeimLaden && !umgebung.amStrom { return "Wartet auf Strom" }
        if umgebung.freierSpeicher < mindestSpeicher { return "Zu wenig Speicher frei auf diesem Gerät" }
        return nil
    }

    public func setze(serverAlben an: Bool) {
        serverAlben = an
        speicher.set(an, forKey: schluesselServerAlben)
        if an { starte() }
    }

    /// Die Alben der Mediathek für die Auswahl.
    public func mediathekAlben() async -> [MediathekAlbum] {
        await mediathek.alben()
    }

    /// Vorschaubild vom Gerät (für Albenliste und nicht gesicherte Fotos).
    public func vorschau(_ id: String, kante: CGFloat) async -> CGImage? {
        await mediathek.vorschau(id, kante: kante)
    }

    /// Fotos vom Gerät, die (noch) nicht auf dem Server sind. Ungeprüfte („neu“) zählen nicht dazu,
    /// weil viele davon schon auf dem Server liegen und sonst kurz doppelt erscheinen würden.
    public func nichtGesicherte() -> [LokalesFoto] {
        guard aktiv, let db else { return [] }
        return [LokalesFoto.Zustand.bereit, .eingereiht, .fehler, .uebersprungen]
            .flatMap { (try? db.lokaleFotos(konto: konto, zustand: $0)) ?? [] }
    }

    /// „Jetzt sichern“ für ein einzelnes Foto: wieder einreihen und einen Durchgang starten.
    public func sichereJetzt(_ lokaleId: String) {
        guard let db else { return }
        if let f = nichtGesicherte().first(where: { $0.lokaleId == lokaleId }), f.zustand != .eingereiht {
            try? db.setzeLokal(konto: konto, lokaleId: lokaleId, zustand: .bereit)
        }
        zaehle()
        onAenderung?()
        if laufAufgabe == nil { starte() } else { starteNachLauf = true }
    }

    /// Fotos vom Gerät, die nicht gesichert werden konnten (z. B. Export gescheitert).
    public func fehlerFotos() -> [LokalesFoto] {
        guard let db else { return [] }
        return (try? db.lokaleFotos(konto: konto, zustand: .fehler)) ?? []
    }

    /// Fotos, die bewusst übersprungen wurden (nur in iCloud, ignoriert, Format).
    public func uebersprungeneFotos() -> [LokalesFoto] {
        guard let db else { return [] }
        return (try? db.lokaleFotos(konto: konto, zustand: .uebersprungen)) ?? []
    }

    /// Ein einzelnes Foto beim nächsten Durchgang neu versuchen.
    public func wiederhole(lokaleId: String) {
        guard let db else { return }
        try? db.pruefeNeu(konto: konto, lokaleId: lokaleId)
        zaehle()
        onAenderung?()
        if laufAufgabe == nil { starte() } else { starteNachLauf = true }
    }

    /// Ein Foto nicht mehr sichern (bis „erneut versuchen“).
    public func ignoriere(lokaleId: String) {
        guard let db else { return }
        try? db.setzeLokal(konto: konto, lokaleId: lokaleId, zustand: .uebersprungen, grund: "Ignoriert")
        zaehle()
        onAenderung?()
    }

    /// Eine einzelne Prüfung auf Fehler zurücksetzen, damit sie beim nächsten Durchgang neu versucht werden.
    public func wiederholeFehler() {
        guard let db else { return }
        let fehler = (try? db.lokaleFotos(konto: konto, zustand: .fehler)) ?? []
        try? db.aktualisiere(fehler.map { var f = $0; f.zustand = .neu; f.grund = nil; return f })
        zaehle()
        starte()
    }

    // MARK: - Durchgang

    func lauf() async {
        guard aktiv, let client, let db, let uploads else { return }
        zugriff = mediathek.zugriff()
        guard zugriff == .voll || zugriff == .eingeschraenkt else {
            phase = .halt("Lilith hat keinen Zugriff mehr auf deine Fotos. Erlaube ihn in den Einstellungen.")
            return
        }
        do {
            phase = .liest
            starteNachLauf = false
            let medien = await filtere(try await mediathek.alleMedien())
            let konto = self.konto
            let iCloud = einstellungen.iCloud
            try await Task.detached(priority: .utility) {
                try db.gleicheAb(konto: konto, medien: medien)
                try db.raeumeLokalAuf(konto: konto)
                // iCloud-Originale sind (wieder) erlaubt: Übersprungene neu versuchen.
                if iCloud, let grund = MediathekFehler.nurInICloud.errorDescription {
                    try db.pruefeErneut(konto: konto, grund: grund)
                }
            }.value
            zaehle()

            try await pruefeNeue(client: client, db: db)
            onAenderung?()
            if let grund = hindernis() {
                // Vergleichen geht immer (wenig Daten), hochladen erst, wenn WLAN/Strom/Platz passen.
                phase = .halt(grund)
                zaehle()
                return
            }
            try await sichereFehlende(db: db, uploads: uploads)
            if serverAlben { await gleicheServerAlbenAb(client: client, db: db) }
            onAenderung?()

            if let grund = uploads.halt ?? hindernis() {
                phase = .halt(grund)
            } else {
                phase = .bereit
                letzterAbschluss = .now
                speicher.set(letzterAbschluss, forKey: schluesselAbschluss)
            }
        } catch is CancellationError {
            phase = .bereit
        } catch ImmichError.sitzungAbgelaufen {
            phase = .halt(ImmichError.sitzungAbgelaufen.errorDescription ?? "")
            onSitzungAbgelaufen?()
        } catch {
            phase = .halt(error.localizedDescription)
        }
        zaehle()
    }

    /// Prüfsummen berechnen und beim Server nachfragen, was er schon hat.
    private func pruefeNeue(client: ImmichClient, db: Datenbank) async throws {
        let gesamt = (try? db.zaehleLokal(konto: konto)[.neu]) ?? 0
        var erledigt = 0
        while true {
            try Task.checkCancellation()
            var block = try db.lokaleFotos(konto: konto, zustand: .neu, hoechstens: pruefBlock)
            if block.isEmpty { break }
            phase = .prueft(erledigt: erledigt, gesamt: max(gesamt, erledigt + block.count))

            for i in block.indices where block[i].pruefsumme == nil {
                try Task.checkCancellation()
                do {
                    block[i].pruefsumme = try await mediathek.pruefsumme(block[i].lokaleId, iCloud: einstellungen.iCloud)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    markiere(&block[i], wegen: error)
                }
            }
            let fragen = block.filter { $0.zustand == .neu }.compactMap { f in f.pruefsumme.map { (f.lokaleId, $0) } }
            let antworten = fragen.isEmpty ? [:] : try await client.pruefeVorab(fragen)
            for i in block.indices where block[i].zustand == .neu {
                switch antworten[block[i].lokaleId] ?? .hochladen {
                case .vorhanden(let id, _):
                    block[i].zustand = .gesichert
                    block[i].remoteId = id
                case .hochladen:
                    block[i].zustand = .bereit
                case .abgelehnt:
                    block[i].zustand = .uebersprungen
                    block[i].grund = ImmichError.formatNichtUnterstuetzt.errorDescription
                }
            }
            try db.aktualisiere(block)
            erledigt += block.count
            zaehle()
        }
    }

    /// Fehlendes blockweise exportieren und hochladen. Pro Block wird gewartet, damit nicht
    /// die ganze Mediathek auf einmal als Kopie auf dem Gerät liegt.
    private func sichereFehlende(db: Datenbank, uploads: UploadWarteschlange) async throws {
        while uploads.halt == nil, hindernis() == nil {
            try Task.checkCancellation()
            var block = try db.lokaleFotos(konto: konto, zustand: .bereit, hoechstens: exportBlock)
            if block.isEmpty { break }
            phase = .sichert

            var auftraege: [UploadAuftrag] = []
            for i in block.indices {
                try Task.checkCancellation()
                let f = block[i]
                let ordner = uploads.arbeitsordner.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                do {
                    try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
                    let e = try await mediathek.exportiere(f.lokaleId, nach: ordner, iCloud: einstellungen.iCloud)
                    var a = UploadAuftrag(konto: konto, quelle: "mediathek", datei: e.datei.path, dateiname: e.dateiname,
                                          erstellt: f.erstellt, geaendert: f.geaendert, dauerMs: e.dauerMs,
                                          istVideo: f.istVideo, lokaleId: f.lokaleId, liveVideoDatei: e.liveVideo?.path)
                    a.pruefsumme = f.pruefsumme
                    auftraege.append(a)
                } catch {
                    try? FileManager.default.removeItem(at: ordner)
                    if error is CancellationError {
                        // Schon Exportiertes trotzdem einreihen, damit nichts doppelt exportiert wird.
                        try? uploads.reiheEin(auftraege)
                        throw error
                    }
                    markiere(&block[i], wegen: error)
                }
            }
            try db.aktualisiere(block.filter { $0.zustand != .bereit })
            // Was nicht exportiert werden konnte, ist schon markiert. Der Rest geht in die Warteschlange.
            try uploads.reiheEin(auftraege)
            await uploads.warteBisFertig()
            zaehle()
        }
    }

    /// Nur Fotos, die laut Albenauswahl gesichert werden sollen.
    func filtere(_ alle: [MediumKopf]) async -> [MediumKopf] {
        let medien = einstellungen.videos ? alle : alle.filter { !$0.istVideo }
        guard !auswahl.gewaehlt.contains(AlbenAuswahl.alle) || !auswahl.ausgeschlossen.isEmpty else { return medien }
        var erlaubt: Set<String>?
        if !auswahl.gewaehlt.contains(AlbenAuswahl.alle) {
            var ids = Set<String>()
            for album in auswahl.gewaehlt { ids.formUnion(await mediathek.medienIds(inAlbum: album)) }
            erlaubt = ids
        }
        var verboten = Set<String>()
        for album in auswahl.ausgeschlossen { verboten.formUnion(await mediathek.medienIds(inAlbum: album)) }
        return medien.filter { (erlaubt?.contains($0.id) ?? true) && !verboten.contains($0.id) }
    }

    /// Gewählte eigene Alben auf dem Server anlegen (gleicher Name) und die gesicherten Fotos hinzufügen.
    /// Fehler hier halten das Backup nicht auf: Die Fotos selbst sind ja gesichert.
    private func gleicheServerAlbenAb(client: ImmichClient, db: Datenbank) async {
        let eigene = await mediathek.alben().filter { !$0.vonIOS && auswahl.gewaehlt.contains($0.id) }
        guard !eigene.isEmpty, var vorhanden = try? await client.alben() else { return }
        for album in eigene {
            let ids = await mediathek.medienIds(inAlbum: album.id)
            guard let remote = try? db.remoteIds(konto: konto, lokaleIds: ids), !remote.isEmpty else { continue }
            if let ziel = vorhanden.first(where: { $0.name == album.titel && !$0.geteilt }) {
                _ = try? await client.fuegeZuAlbum(albumId: ziel.id, assetIds: remote)
            } else if let neu = try? await client.erstelleAlbum(name: album.titel, assetIds: remote) {
                vorhanden.append(neu)
            }
        }
    }

    private func markiere(_ f: inout LokalesFoto, wegen error: any Error) {
        switch error as? MediathekFehler {
        case .nurInICloud, .nichtUnterstuetzt, .nichtGefunden:
            f.zustand = .uebersprungen
        case nil:
            f.zustand = .fehler
        }
        f.grund = error.localizedDescription
    }

    private func zaehle() {
        guard let db, let z = try? db.zaehleLokal(konto: konto) else { return }
        uebersicht = Uebersicht(gesamt: z.values.reduce(0, +), gesichert: z[.gesichert] ?? 0,
                                fehler: z[.fehler] ?? 0, uebersprungen: z[.uebersprungen] ?? 0)
    }

    // MARK: - Texte

    /// Statuszeile mit konkretem Grund.
    public var statusText: String {
        let zahl = { (n: Int) in n.formatted(.number) }
        switch phase {
        case .aus:
            return "Aus"
        case .liest:
            return "Liest deine Mediathek …"
        case .prueft(let erledigt, let gesamt):
            return "Vergleicht mit dem Server · \(zahl(erledigt)) von \(zahl(gesamt))"
        case .sichert:
            return "Sichert \(zahl(uebersicht.offen)) \(uebersicht.offen == 1 ? "Objekt" : "Objekte") …"
        case .halt(let grund):
            return grund
        case .bereit:
            if uebersicht.offen == 0, let letzter = letzterAbschluss {
                return "Alles gesichert · zuletzt \(letzter.formatted(date: .omitted, time: .shortened))"
            }
            return uebersicht.offen == 0 ? "Alles gesichert" : "\(zahl(uebersicht.offen)) noch nicht gesichert"
        }
    }

    /// „8.412 von 9.030 gesichert“
    public var zaehlerText: String {
        "\(uebersicht.gesichert.formatted(.number)) von \(uebersicht.gesamt.formatted(.number)) gesichert"
    }

    /// Alles gesichert, nichts offen, keine Fehler (für den Vollmond-Moment).
    public var allesGesichert: Bool {
        aktiv && phase == .bereit && uebersicht.gesamt > 0 && uebersicht.offen == 0 && uebersicht.fehler == 0
    }

    /// Ob der Vollmond-Moment schon gezeigt wurde (nur einmal pro Konto).
    public var vollmondGezeigt: Bool {
        get { speicher.bool(forKey: "lilith.backup.vollmond.\(konto)") }
        set { speicher.set(newValue, forKey: "lilith.backup.vollmond.\(konto)") }
    }

    public var laeuft: Bool {
        switch phase {
        case .liest, .prueft, .sichert: true
        default: false
        }
    }
}
