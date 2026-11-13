import Foundation
import Observation
import Networking
import TimelineGrid
import Backup

/// Was alle Ansichten der Bibliothek gemeinsam brauchen: die Verbindung zum Server
/// und ein Zähler, der sich bei jeder Änderung erhöht, damit andere Ansichten neu laden.
@MainActor
@Observable
final class BibliothekKontext {
    /// `nil` im Demo-Modus ohne Server.
    let client: ImmichClient?
    /// Ist der Papierkorb auf dem Server aus, löscht „Löschen“ sofort endgültig.
    let papierkorbAktiv: Bool
    /// Ob der Server Smart Search anbietet (Machine Learning eingeschaltet).
    let smartSearch: Bool
    private(set) var stand = 0
    @ObservationIgnored private(set) weak var letzteQuelle: AnyObject?
    @ObservationIgnored var onSitzungAbgelaufen: (() -> Void)?
    /// Das gerade geöffnete Foto. Die Detailansicht liegt über dem ganzen Fenster, nicht nur über einem Bereich.
    var detail: DetailAnzeige?

    /// Hochladen. `nil` im Demo-Modus oder wenn die Datenbank nicht geöffnet werden konnte.
    let uploads: UploadWarteschlange?
    /// Automatisches Backup (nur iPhone/iPad).
    let backup: BackupDienst?
    /// Für das Profilbild oben rechts.
    let nutzerId: String?

    init(client: ImmichClient?, papierkorbAktiv: Bool, smartSearch: Bool = false, uploads: UploadWarteschlange? = nil,
         backup: BackupDienst? = nil, nutzerId: String? = nil) {
        self.nutzerId = nutzerId
        self.client = client
        self.uploads = uploads
        self.backup = backup
        self.papierkorbAktiv = papierkorbAktiv
        self.smartSearch = smartSearch
    }

    /// Meldet eine Änderung an Fotos oder Alben. `quelle` hat sich schon selbst aktualisiert.
    func melde(von quelle: AnyObject?) {
        letzteQuelle = quelle
        stand += 1
    }

    @ObservationIgnored private var buendel: Task<Void, Never>?

    /// Für Meldungen von Backup und Uploads: höchstens alle 2 Sekunden ein Neuladen,
    /// statt bei jedem einzelnen Ereignis alles neu zu holen.
    func meldeGebuendelt() {
        buendel?.cancel()
        buendel = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.melde(von: nil)
        }
    }

    func pruefe(_ error: any Error) {
        if case ImmichError.sitzungAbgelaufen = error { onSitzungAbgelaufen?() }
    }
}

/// Alles, was die Detailansicht zum Öffnen braucht.
struct DetailAnzeige: Identifiable {
    let id = UUID()
    let quelle: TimelineQuelle
    let store: TimelineStore?
    let start: DetailPosition
    /// Rahmen der angetippten Kachel im Fenster, für den Zoom-Übergang.
    let rahmen: CGRect
    let loeschen: ((String) async -> Bool)?
    let schliessen: (DetailPosition) -> Void
}

extension DetailAnzeige: Equatable {
    static func == (a: DetailAnzeige, b: DetailAnzeige) -> Bool { a.id == b.id }
}
