import Foundation
import Backup
import Networking
import Persistence
#if os(iOS)
import BackgroundTasks
#endif

/// Hält Upload-Warteschlange und Backup einmal pro App-Start, damit Oberfläche und Hintergrund-Läufe
/// dieselben benutzen. iOS kann Lilith ohne Bildschirm starten (nachts, nach fertigen Uploads).
@MainActor
public final class BackupZentrale {
    public static let shared = BackupZentrale()

    static let nachtKennung = "app.lilith.backup.nacht"
    static let kurzKennung = "app.lilith.backup.kurz"

    private(set) var konto: String?
    private(set) var uploads: UploadWarteschlange?
    private(set) var backup: BackupDienst?

    private init() {}

    /// Für ein Konto einrichten (oder die vorhandenen zurückgeben).
    func einrichten(account: Account, client: ImmichClient) -> (UploadWarteschlange?, BackupDienst?) {
        if konto == account.id { return (uploads, backup) }
        guard let db = try? Datenbank.standard() else { return (nil, nil) }
        let schlange = UploadWarteschlange(client: client, db: db, konto: account.id)
        var dienst: BackupDienst?
        #if os(iOS)
        // Auf dem Mac nur per Hand (Entscheidung im Backup-Plan).
        dienst = BackupDienst(client: client, db: db, konto: account.id, mediathek: FotoMediathek(), uploads: schlange,
                              umgebung: GeraeteUmgebung.geteilt)
        #endif
        konto = account.id
        uploads = schlange
        backup = dienst
        schlange.start()
        return (schlange, dienst)
    }

    /// Ohne Oberfläche gestartet: gespeicherte Anmeldung laden und einrichten.
    func bereit() async -> (UploadWarteschlange, BackupDienst?)? {
        if let uploads { return (uploads, backup) }
        let sitzung = SessionStore()
        await sitzung.start()
        guard case .angemeldet(let account) = sitzung.phase, let client = sitzung.client else { return nil }
        let (u, b) = einrichten(account: account, client: client)
        return u.map { ($0, b) }
    }

    /// Beim Verlassen der App: Uploads an iOS übergeben und die nächsten Läufe anmelden.
    func inDenHintergrund() {
        backup?.halteAn()
        uploads?.uebergibAnHintergrund()
        planeHintergrund()
    }

    // MARK: - Hintergrund (iOS)

    /// Vom App-Delegate: iOS hat Lilith geweckt, weil Hintergrund-Uploads fertig sind.
    public static func hintergrundUploadsGeweckt(_ fertig: @escaping () -> Void) {
        HintergrundUpload.geteilt.setzeSystemAbschluss(fertig)
        // Die Warteschlange muss existieren, damit die Ergebnisse eingetragen werden. Danach gleich die nächsten übergeben.
        Task { @MainActor in
            if let (uploads, _) = await shared.bereit() { uploads.uebergibAnHintergrund() }
        }
    }

    /// Einmal beim App-Start (vor dem Ende des Startvorgangs) aufrufen.
    public static func registriereHintergrund() {
        #if os(iOS)
        for kennung in [nachtKennung, kurzKennung] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: kennung, using: nil) { aufgabe in
                let gesendet = Gesendet(aufgabe)
                Task { @MainActor in await shared.fuehreAus(gesendet.wert) }
            }
        }
        #endif
    }

    func planeHintergrund() {
        #if os(iOS)
        guard backup?.aktiv == true else { return }
        // Nachts am Ladekabel: viel Zeit für Prüfsummen, iCloud-Originale und große Uploads.
        let nacht = BGProcessingTaskRequest(identifier: Self.nachtKennung)
        nacht.requiresExternalPower = true
        nacht.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(nacht)
        // Zwischendurch kurz: neue Fotos übergeben.
        let kurz = BGAppRefreshTaskRequest(identifier: Self.kurzKennung)
        kurz.earliestBeginDate = Date.now.addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(kurz)
        #endif
    }

    #if os(iOS)
    private func fuehreAus(_ aufgabe: BGTask) async {
        planeHintergrund()
        guard let (uploads, backup) = await bereit(), let backup, backup.aktiv else {
            aufgabe.setTaskCompleted(success: false)
            return
        }
        planeHintergrund()
        let gesendet = Gesendet(aufgabe)
        aufgabe.expirationHandler = {
            Task { @MainActor in
                // Zeit ist um: anhalten, Fertiges an iOS übergeben, damit es ohne Lilith weiterläuft.
                backup.halteAn()
                uploads.uebergibAnHintergrund()
                gesendet.wert.setTaskCompleted(success: false)
            }
        }
        await backup.durchgang()
        uploads.uebergibAnHintergrund()
        aufgabe.setTaskCompleted(success: true)
    }
    #endif
}

/// Hält einen Wert, der nicht als `Sendable` markiert ist, über eine Thread-Grenze (z. B. `BGTask`).
private struct Gesendet<Wert>: @unchecked Sendable {
    let wert: Wert
    init(_ wert: Wert) { self.wert = wert }
}
