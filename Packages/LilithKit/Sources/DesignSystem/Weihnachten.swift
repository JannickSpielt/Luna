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
}

/// Leiser Schneefall: wenige, langsame Flocken. Bei „Bewegung reduzieren“ ruhend.
public struct Schneefall: View {
    var anzahl: Int
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    public init(anzahl: Int = 60) { self.anzahl = anzahl }

    private struct Flocke {
        let x: Double, groesse: Double, tempo: Double, versatz: Double, wiegen: Double
    }

    private static func flocken(_ n: Int) -> [Flocke] {
        var g = SystemRandomNumberGenerator()
        return (0..<n).map { _ in
            Flocke(x: .random(in: 0...1, using: &g), groesse: .random(in: 1.5...4, using: &g),
                   tempo: .random(in: 0.04...0.11, using: &g), versatz: .random(in: 0...1, using: &g),
                   wiegen: .random(in: 0...(2 * .pi), using: &g))
        }
    }

    @State private var liste: [Flocke] = []

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: wenigBewegung)) { zeit in
            Canvas { ctx, groesse in
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
        .onAppear { if liste.isEmpty { liste = Self.flocken(anzahl) } }
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
