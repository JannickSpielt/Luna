#if os(iOS)
import UIKit

/// Auf dem iPad kann Luna in mehreren Fenstern gleichzeitig offen sein (z. B. zwei nebeneinander).
/// Blätter wie Teilen oder die Fotoauswahl gehören in das Fenster, in dem gerade getippt wurde.
@MainActor
enum AktivesFenster {
    /// Das Fenster, das gerade die Eingaben bekommt. Ohne eindeutiges das erste aktive.
    static var fenster: UIWindow? {
        let szenen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return szenen.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? szenen.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? szenen.first?.keyWindow
    }

    /// Ist noch irgendein Luna-Fenster zu sehen? Schließt man eines von zweien, läuft die App weiter.
    static var nochEinesSichtbar: Bool {
        UIApplication.shared.connectedScenes.contains {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
    }
}
#endif
