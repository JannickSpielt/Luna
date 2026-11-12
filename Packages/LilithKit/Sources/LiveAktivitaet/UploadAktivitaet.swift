#if os(iOS)
import ActivityKit
import Foundation

/// Live Activity für große Uploads (Sperrbildschirm, Dynamic Island).
/// Wird von der App gestartet und vom Widget-Extension-Target angezeigt.
public struct UploadAktivitaet: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var erledigt: Int
        public var gesamt: Int
        /// 0…1 über alle Dateien.
        public var anteil: Double
        public var fertig: Bool
        public var fehler: Int

        public init(erledigt: Int, gesamt: Int, anteil: Double, fertig: Bool = false, fehler: Int = 0) {
            self.erledigt = erledigt; self.gesamt = gesamt; self.anteil = anteil; self.fertig = fertig; self.fehler = fehler
        }

        public var text: String {
            if fertig { return fehler == 0 ? "\(gesamt) hochgeladen" : "\(gesamt - fehler) hochgeladen, \(fehler) Fehler" }
            return "\(erledigt) von \(gesamt)"
        }
    }

    public init() {}
}
#endif
