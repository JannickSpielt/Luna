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

/// Die Farbpalette „Nachtrose“. Dark Mode ist das Herzstück,
/// der Light Mode wirkt warm wie Papier.
public enum LilithColor {
    /// Akzent für Buttons, Auswahl und Favoriten.
    public static let nachtrose = Color.lilith(light: 0xB0305A, dark: 0xE46A8C)
    /// Akzent als Fläche (Button-Hintergrund), in beiden Modi gleich.
    public static let nachtroseFill = Color.lilith(light: 0xB0305A, dark: 0xB0305A)
    /// Warmer Mondlicht-Ton für Highlights und den Mond.
    public static let mondlicht = Color.lilith(light: 0xC9A96A, dark: 0xEBD9B4)
    /// Grundfläche der App.
    public static let hintergrund = Color.lilith(light: 0xFAF5EE, dark: 0x120E10)
    /// Flächen wie Sidebar, Karten und Sheets.
    public static let flaeche = Color.lilith(light: 0xF1E9DE, dark: 0x1A1517)
    /// Haupttext.
    public static let text = Color.lilith(light: 0x1E1719, dark: 0xF4EDE4)
    /// Nebentext.
    public static let textLeise = Color.lilith(light: 0x6B5F59, dark: 0xB8ADA6)
    /// Hintergrund in der Vollbild-Fotoansicht (echtes Schwarz).
    public static let betrachter = Color.black
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
