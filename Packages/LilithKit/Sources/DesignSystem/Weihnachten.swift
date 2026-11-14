import SwiftUI

/// Weihnachtszeit: vom 1. Dezember bis 6. Januar automatisch, abschaltbar in den Einstellungen.
public enum Weihnachten {
    public static let schluessel = "luna.weihnachten"

    /// Liegt das Datum in der Weihnachtszeit?
    public static func zeitraum(_ datum: Date = .now, kalender: Calendar = .current) -> Bool {
        let t = kalender.dateComponents([.month, .day], from: datum)
        return t.month == 12 || (t.month == 1 && (t.day ?? 99) <= 6)
    }

    /// Weihnachtsdesign zeigen? (Zeitraum und Schalter; zum Ansehen: „-LilithWeihnachten YES“.)
    public static var aktiv: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "LilithWeihnachten") { return true }
        #endif
        let an = UserDefaults.standard.object(forKey: schluessel) as? Bool ?? true
        return an && zeitraum()
    }

    /// Tannengrün als zweiter, festlicher Akzent neben dem Kirschrot.
    public static let tanne = Color.lilith(light: 0x1E6B45, dark: 0x5FC48F)
    /// Farbe der Flocken über der App: im hellen Modus ein zartes Blaugrau (Weiß wäre unsichtbar), im dunklen Weiß.
    public static let flocke = Color.lilith(light: 0x7F95AD, dark: 0xFFFFFF)
}

/// Leiser Schneefall: wenige, langsame Flocken. Bei „Bewegung reduzieren“ ruhend.
public struct Schneefall: View {
    var anzahl: Int
    /// `false` hält den Schnee an (z. B. solange ein Foto groß offen ist: spart Akku).
    var laeuft: Bool
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    private let liste: [Flocke]

    public init(anzahl: Int = 60, laeuft: Bool = true) {
        self.anzahl = anzahl; self.laeuft = laeuft
        liste = Self.flocken(anzahl)
    }

    private struct Flocke {
        let x: Double, groesse: Double, tempo: Double, versatz: Double, wiegen: Double
    }

    /// Feste Pseudozufallszahlen: Die Flocken stehen sofort bereit und springen beim Neuzeichnen nicht.
    private static func flocken(_ n: Int) -> [Flocke] {
        var zustand: UInt64 = 0x9E37_79B9_7F4A_7C15
        func zahl(_ bereich: ClosedRange<Double>) -> Double {
            zustand = zustand &* 6364136223846793005 &+ 1442695040888963407
            let anteil = Double(zustand >> 11) / Double(1 << 53)
            return bereich.lowerBound + anteil * (bereich.upperBound - bereich.lowerBound)
        }
        return (0..<n).map { _ in
            Flocke(x: zahl(0...1), groesse: zahl(2...5), tempo: zahl(0.04...0.1),
                   versatz: zahl(0...1), wiegen: zahl(0...(2 * .pi)))
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: wenigBewegung || !laeuft)) { zeit in
            Canvas { ctx, groesse in
                // Hauchzarter Schatten: So sind weiße Flocken auch auf hellem Grund zu sehen.
                ctx.addFilter(.shadow(color: Color(red: 0.2, green: 0.28, blue: 0.4).opacity(0.35), radius: 1.2))
                let t = zeit.date.timeIntervalSinceReferenceDate
                for f in liste {
                    let y = (f.versatz + t * f.tempo).truncatingRemainder(dividingBy: 1.05) - 0.05
                    let x = f.x + sin(t * 0.6 + f.wiegen) * 0.012
                    let r = CGRect(x: x * groesse.width, y: y * groesse.height, width: f.groesse, height: f.groesse)
                    ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.35 + f.groesse / 10)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Kleiner Stern (z. B. neben dem Mond).
public struct WeihnachtsStern: View {
    public init() {}
    public var body: some View {
        Image(systemName: "sparkle")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(LilithColor.mondlicht)
            .accessibilityHidden(true)
    }
}
