import SwiftUI

/// Schriften: Serif (New York) für große Titel, SF Pro für alles andere.
/// Beide skalieren mit Dynamic Type.
public enum LilithFont {
    /// Großer Bildschirmtitel, z. B. „Bibliothek“.
    public static let titel = Font.system(.largeTitle, design: .serif, weight: .semibold)
    /// Abschnittstitel, z. B. „Oktober 2026“.
    public static let abschnitt = Font.system(.title3, design: .serif, weight: .semibold)
    /// Albumnamen und Kartentitel.
    public static let karte = Font.system(.headline, design: .serif, weight: .semibold)
}
