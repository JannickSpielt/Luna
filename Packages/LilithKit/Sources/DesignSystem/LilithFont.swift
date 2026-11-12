import SwiftUI

/// Schriften: nur SF mit den Textstilen des Systems (Dynamic Type). Keine Serife:
/// Lilith ist eine Foto-App, die Schrift soll leise sein.
public enum LilithFont {
    /// Großer Bildschirmtitel, z. B. „Bibliothek“.
    public static let titel = Font.largeTitle.bold()
    /// Abschnittstitel, z. B. „Oktober 2026“.
    public static let abschnitt = Font.headline
    /// Albumnamen und Kartentitel.
    public static let karte = Font.subheadline.weight(.medium)
}
