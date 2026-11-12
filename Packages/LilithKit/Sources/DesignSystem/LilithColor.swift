import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Ein Farbwert als 24-Bit-RGB, z. B. `0xB0305A`.
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

/// Die Farben von Lilith. Flächen und Text kommen vom System (hell und dunkel, erhöhter Kontrast),
/// damit die Fotos die Farbe tragen. Nachtrose ist der einzige Akzent und wird sparsam eingesetzt:
/// gewählter Tab, Auswahl, Favorit, ein Hauptknopf. Mondlicht gehört nur dem Mond (Backup).
public enum LilithColor {
    /// Akzent für Buttons, Auswahl und Favoriten.
    /// Hell 7,2 : 1 auf Weiß, dunkel 7,6 : 1 auf Schwarz.
    public static let nachtrose = Color.lilith(light: 0x9E2A50, dark: 0xE8799A)
    /// Akzent als Fläche (Button-Hintergrund), in beiden Modi gleich.
    public static let nachtroseFill = Color.lilith(light: 0x9E2A50, dark: 0x9E2A50)
    /// Nur für den Mond (Backup-Ring, Statuskarte, Start). Hell 3,5 : 1 auf Weiß.
    public static let mondlicht = Color.lilith(light: 0xA8843E, dark: 0xEBD9B4)
    /// Grundfläche der App.
    public static let hintergrund = system(ui: "systemBackground", mac: "windowBackgroundColor")
    /// Flächen wie Sidebar, Karten und Sheets.
    public static let flaeche = system(ui: "secondarySystemBackground", mac: "controlBackgroundColor")
    /// Haupttext.
    public static let text = Color.primary
    /// Nebentext.
    public static let textLeise = Color.secondary
    /// Schalter (Toggle) wie im System: grün, nicht im Akzent.
    public static let schalter = Color.green
    /// Hintergrund in der Vollbild-Fotoansicht (echtes Schwarz).
    public static let betrachter = Color.black
}

extension LilithColor {
    /// Systemfarbe je Plattform.
    static func system(ui: String, mac: String) -> Color {
        #if canImport(UIKit)
        switch ui {
        case "systemBackground": return Color(uiColor: .systemBackground)
        default: return Color(uiColor: .secondarySystemBackground)
        }
        #else
        switch mac {
        case "windowBackgroundColor": return Color(nsColor: .windowBackgroundColor)
        default: return Color(nsColor: .controlBackgroundColor)
        }
        #endif
    }
}

extension Color {
    /// Eine Farbe, die sich automatisch an Hell- und Dunkelmodus anpasst.
    static func lilith(light: UInt32, dark: UInt32) -> Color {
        let l = RGB(hex: light)
        let d = RGB(hex: dark)
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? d : l
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
        #endif
    }
}
