#if os(iOS)
import ActivityKit
import Foundation
import Backup
import LiveAktivitaet

/// Startet und aktualisiert die Live Activity, wenn viele Fotos per Hand hochgeladen werden.
@MainActor
final class UploadLiveSteuerung {
    static let shared = UploadLiveSteuerung()
    /// Ab so vielen Fotos lohnt sich die Anzeige auf dem Sperrbildschirm.
    static let abAnzahl = 20

    private var aktivitaet: Activity<UploadAktivitaet>?
    private var letzteMeldung = Date.distantPast

    func aktualisiere(_ s: UploadWarteschlange.Stand) {
        guard let aktivitaet else {
            guard s.laeuft, s.manuell >= Self.abAnzahl, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            self.aktivitaet = try? Activity.request(attributes: UploadAktivitaet(),
                                                    content: .init(state: Self.zustand(s), staleDate: nil))
            letzteMeldung = .now
            return
        }
        if !s.laeuft {
            self.aktivitaet = nil
            var ende = Self.zustand(s)
            ende.fertig = true
            let a = AktivitaetBox(aktivitaet)
            Task { await a.wert.end(.init(state: ende, staleDate: nil), dismissalPolicy: .after(.now + 60)) }
            return
        }
        // Nicht öfter als nötig: iOS begrenzt die Zahl der Aktualisierungen.
        guard Date.now.timeIntervalSince(letzteMeldung) > 1.5 else { return }
        letzteMeldung = .now
        let z = Self.zustand(s)
        let a = AktivitaetBox(aktivitaet)
        Task { await a.wert.update(.init(state: z, staleDate: nil)) }
    }

    #if DEBUG
    /// Zum Ansehen ohne echten Upload: „-LilithLiveVorschau YES“.
    func zeigeVorschau() {
        guard aktivitaet == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        aktivitaet = try? Activity.request(attributes: UploadAktivitaet(),
                                           content: .init(state: .init(erledigt: 17, gesamt: 48, anteil: 0.36), staleDate: nil))
    }
    #endif

    static func zustand(_ s: UploadWarteschlange.Stand) -> UploadAktivitaet.ContentState {
        .init(erledigt: s.erledigt, gesamt: s.gesamt, anteil: s.gesamtAnteil, fehler: s.fehler)
    }
}
/// `Activity` ist nicht als `Sendable` markiert, wird aber nur hier benutzt.
private struct AktivitaetBox: @unchecked Sendable {
    let wert: Activity<UploadAktivitaet>
    init(_ wert: Activity<UploadAktivitaet>) { self.wert = wert }
}
#endif
