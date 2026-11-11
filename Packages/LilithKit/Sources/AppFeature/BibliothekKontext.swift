import Foundation
import Observation
import Networking

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

    init(client: ImmichClient?, papierkorbAktiv: Bool, smartSearch: Bool = false) {
        self.client = client
        self.papierkorbAktiv = papierkorbAktiv
        self.smartSearch = smartSearch
    }

    /// Meldet eine Änderung an Fotos oder Alben. `quelle` hat sich schon selbst aktualisiert.
    func melde(von quelle: AnyObject?) {
        letzteQuelle = quelle
        stand += 1
    }

    func pruefe(_ error: any Error) {
        if case ImmichError.sitzungAbgelaufen = error { onSitzungAbgelaufen?() }
    }
}
