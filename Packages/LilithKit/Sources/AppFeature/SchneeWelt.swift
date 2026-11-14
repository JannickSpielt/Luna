#if os(iOS)
import SwiftUI
import UIKit
import DesignSystem

/// Weihnachtszeit: Schnee fällt über die App und bleibt oben auf der Tab-Leiste liegen.
/// Bewegt man sich (Scrollen, Tab-Wechsel), springt er hoch und fällt mit Schwerkraft zurück.
/// Liegt zu viel, rutscht er an den Seiten der Leiste herunter. Fängt keine Berührungen ab.
struct SchneeWelt: View {
    /// `false`: angehalten (z. B. solange ein Foto groß offen ist).
    var laeuft: Bool
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung
    @State private var welt = SchneeSimulation()

    var body: some View {
        if wenigBewegung {
            // Ruhig: nur der leise, stehende Schnee.
            Schneefall(anzahl: 45, laeuft: false).ignoresSafeArea()
        } else {
            GeometryReader { geo in
                let ursprung = geo.frame(in: .global).origin
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !laeuft)) { zeit in
                    Canvas { ctx, groesse in
                        welt.schritt(zeit.date.timeIntervalSinceReferenceDate, groesse: groesse, ursprung: ursprung)
                        welt.zeichne(in: &ctx)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Simulation

/// Die Physik dahinter. Absichtlich eine Klasse ohne Beobachtung: Sie ändert sich 60-mal pro Sekunde,
/// das soll keine Ansicht neu aufbauen – nur das Bild wird neu gezeichnet.
@MainActor
final class SchneeSimulation {
    /// Eine Flocke in der Luft.
    struct Flocke {
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, r: CGFloat
        /// `true`: schwebt leise herab (frischer Schnee). `false`: fliegt mit Schwerkraft (hochgewirbelt, abgerutscht).
        var schwebt: Bool
        var wiegen: CGFloat
    }

    /// Eine Glas-Kapsel der Tab-Leiste mit dem Schnee darauf (Höhe je Spalte).
    struct Kapsel {
        var rahmen: CGRect
        var hoehe: [CGFloat]
    }

    private var flocken: [Flocke] = []
    private var kapseln: [Kapsel] = []
    private let ortung = LeistenOrtung()
    private var letzteZeit: TimeInterval?
    private var groesse: CGSize = .zero
    private var zufall = SystemRandomNumberGenerator()

    // Stellschrauben
    private let spalte: CGFloat = 2              // Breite einer Schneespalte
    private let schwerkraft: CGFloat = 1700      // pt/s² – bewusst kräftig, nicht schwebend
    private let frischeFlocken = 45              // gleichzeitig herabschwebend
    private let hoechstensFlocken = 420
    private let maxHoehe: CGFloat = 9            // mehr bleibt nicht liegen, der Rest rutscht ab
    private let stufe: CGFloat = 1.1             // größter Höhenunterschied zwischen Nachbarspalten
    private let startHoehe: CGFloat = 3.5        // so viel liegt schon, wenn die Leiste erscheint
    private let flockenFlaeche: CGFloat = 9      // so viel Schnee (pt²) bringt eine Flocke mit

    // MARK: Schritt

    func schritt(_ jetzt: TimeInterval, groesse: CGSize, ursprung: CGPoint) {
        let dt = CGFloat(min(max(jetzt - (letzteZeit ?? jetzt), 0), 1.0 / 20))
        letzteZeit = jetzt
        self.groesse = groesse
        aktualisiereKapseln(ursprung: ursprung, dt: dt)
        wirbleAuf(SchneeImpuls.nimm())
        ergaenzeFrischen()
        bewege(dt)
        lasseRutschen()
    }

    /// Kapseln nachführen. Fährt die Leiste schneller weg, als Schnee fallen kann, bleibt er in der Luft.
    private func aktualisiereKapseln(ursprung: CGPoint, dt: CGFloat) {
        let neu = ortung.rahmen()
            .map { $0.offsetBy(dx: -ursprung.x, dy: -ursprung.y) }
            .filter { $0.width > 20 && $0.maxY > 0 && $0.minY < groesse.height }
            .sorted { $0.minX < $1.minX }
        if neu.count != kapseln.count {
            // Leiste neu oder anders aufgeteilt: Was lag, fällt herunter; die neuen Kapseln haben schon etwas Schnee.
            for k in kapseln { loese(k, vy: 0) }
            kapseln = neu.map { Kapsel(rahmen: $0, hoehe: Self.anfangsSchnee(breite: $0.width, spalte: spalte, hoehe: startHoehe)) }
            return
        }
        for i in kapseln.indices {
            let alt = kapseln[i].rahmen
            let r = neu[i]
            if abs(r.width - alt.width) > 1 {
                kapseln[i].hoehe = Self.verteile(kapseln[i].hoehe, auf: max(1, Int(r.width / spalte)))
            }
            // Schneller weg nach unten als die Schwerkraft: Der Schnee hebt ab und fällt hinterher.
            if dt > 0, (r.minY - alt.minY) / dt > 600 {
                loese(kapseln[i], vy: 0)
                kapseln[i].hoehe = Array(repeating: 0, count: kapseln[i].hoehe.count)
            }
            kapseln[i].rahmen = r
        }
    }

    /// Bewegung in der App: Ein Teil des liegenden Schnees springt hoch.
    private func wirbleAuf(_ tempo: CGFloat) {
        guard tempo > 120 else { return }
        let anteil = min(0.85, (tempo - 120) / 1600)
        let wurf = min(120 + tempo * 0.16, 620)
        for k in kapseln.indices {
            for s in kapseln[k].hoehe.indices where kapseln[k].hoehe[s] > 0.15 {
                let weg = kapseln[k].hoehe[s] * anteil
                kapseln[k].hoehe[s] -= weg
                var menge = weg * spalte / flockenFlaeche * 2.2
                let x = kapseln[k].rahmen.minX + (CGFloat(s) + 0.5) * spalte
                let y = oberflaeche(kapseln[k], s) - kapseln[k].hoehe[s]
                while menge > 0, flocken.count < hoechstensFlocken {
                    if menge < 1, CGFloat.random(in: 0...1, using: &zufall) > menge { break }
                    menge -= 1
                    flocken.append(Flocke(x: x, y: y - 1, vx: .random(in: -70...70, using: &zufall),
                                          vy: -wurf * .random(in: 0.45...1.15, using: &zufall),
                                          r: .random(in: 1.1...2.2, using: &zufall), schwebt: false, wiegen: 0))
                }
            }
        }
    }

    /// Immer etwa gleich viel frischer Schnee in der Luft.
    private func ergaenzeFrischen() {
        let schwebend = flocken.reduce(0) { $0 + ($1.schwebt ? 1 : 0) }
        guard schwebend < frischeFlocken, groesse.width > 0 else { return }
        // Beim allerersten Bild über die ganze Höhe verteilt, danach von oben.
        let ganzeHoehe = flocken.isEmpty
        for _ in schwebend..<frischeFlocken {
            flocken.append(Flocke(x: .random(in: 0...groesse.width, using: &zufall),
                                  y: ganzeHoehe ? .random(in: 0...groesse.height, using: &zufall) : -.random(in: 4...40, using: &zufall),
                                  vx: 0, vy: .random(in: 38...85, using: &zufall),
                                  r: .random(in: 1...2.5, using: &zufall), schwebt: true,
                                  wiegen: .random(in: 0...(2 * .pi), using: &zufall)))
        }
    }

    private func bewege(_ dt: CGFloat) {
        guard dt > 0 else { return }
        var bleiben: [Flocke] = []
        bleiben.reserveCapacity(flocken.count)
        for var f in flocken {
            let vorher = f.y
            if f.schwebt {
                f.wiegen += dt * 0.8
                f.x += sin(f.wiegen) * 9 * dt
                f.y += f.vy * dt
            } else {
                f.vy = min(f.vy + schwerkraft * dt, 1100)
                f.x += f.vx * dt
                f.y += f.vy * dt
            }
            if f.vy > 0, lande(f, von: vorher) { continue }
            if f.y < groesse.height + 10, f.x > -20, f.x < groesse.width + 20 { bleiben.append(f) }
        }
        flocken = bleiben
    }

    /// Trifft die Flocke von oben auf den Schnee einer Kapsel, bleibt sie dort liegen.
    private func lande(_ f: Flocke, von vorher: CGFloat) -> Bool {
        for k in kapseln.indices {
            let r = kapseln[k].rahmen
            guard f.x >= r.minX, f.x < r.maxX else { continue }
            let s = min(max(Int((f.x - r.minX) / spalte), 0), kapseln[k].hoehe.count - 1)
            let flaeche = oberflaeche(kapseln[k], s) - kapseln[k].hoehe[s]
            guard f.y + f.r >= flaeche, vorher + f.r <= flaeche + 6, f.y < r.midY else { continue }
            // Etwas breiter verteilen, damit keine Nadeln entstehen.
            let menge = flockenFlaeche / spalte * (f.schwebt ? 1 : 0.45)
            for (d, teil) in [(-2, 0.1), (-1, 0.2), (0, 0.4), (1, 0.2), (2, 0.1)] as [(Int, CGFloat)] {
                let j = s + d
                if kapseln[k].hoehe.indices.contains(j) { kapseln[k].hoehe[j] += menge * teil }
            }
            return true
        }
        return false
    }

    /// Schnee sucht sich seinen Weg: zu steil oder zu hoch rutscht zur Seite, am Rand fällt er herunter.
    private func lasseRutschen() {
        for k in kapseln.indices {
            let n = kapseln[k].hoehe.count
            guard n > 1 else { continue }
            for _ in 0..<2 {
                for s in 0..<n where kapseln[k].hoehe[s] > 0.05 {
                    let hier = oberflaeche(kapseln[k], s) - kapseln[k].hoehe[s]
                    // Zum Rand hin (die Kapsel ist an den Enden rund): ab einer gewissen Menge rutscht er ab.
                    if s == 0 || s == n - 1 {
                        if kapseln[k].hoehe[s] > 0.6 {
                            let weg = kapseln[k].hoehe[s] - 0.6
                            kapseln[k].hoehe[s] = 0.6
                            fallHerunter(kapseln[k], spalte: s, menge: weg, nachLinks: s == 0)
                        }
                        continue
                    }
                    var ziel = -1
                    var gefaelle: CGFloat = 0
                    for j in [s - 1, s + 1] {
                        let dort = oberflaeche(kapseln[k], j) - kapseln[k].hoehe[j]
                        let d = dort - hier  // > 0: Nachbar liegt tiefer
                        if d > gefaelle { gefaelle = d; ziel = j }
                    }
                    var weg: CGFloat = 0
                    if ziel >= 0, gefaelle > stufe { weg = (gefaelle - stufe) * 0.5 }
                    // Zu hoch: zur näheren Seite schieben, dort fällt es irgendwann herunter.
                    if kapseln[k].hoehe[s] > maxHoehe {
                        weg = max(weg, kapseln[k].hoehe[s] - maxHoehe)
                        if ziel < 0 { ziel = s < n / 2 ? s - 1 : s + 1 }
                    }
                    weg = min(weg, kapseln[k].hoehe[s])
                    if weg > 0, ziel >= 0 {
                        kapseln[k].hoehe[s] -= weg
                        kapseln[k].hoehe[ziel] += weg
                    }
                }
            }
        }
    }

    /// Schnee rutscht über den Rand: kleine Brocken fallen seitlich herunter.
    private func fallHerunter(_ k: Kapsel, spalte s: Int, menge: CGFloat, nachLinks: Bool) {
        var anzahl = menge * spalte / flockenFlaeche * 2.5
        let x = nachLinks ? k.rahmen.minX + 1 : k.rahmen.maxX - 1
        let y = oberflaeche(k, s) - 1
        while anzahl > 0, flocken.count < hoechstensFlocken {
            if anzahl < 1, CGFloat.random(in: 0...1, using: &zufall) > anzahl { break }
            anzahl -= 1
            flocken.append(Flocke(x: x, y: y, vx: (nachLinks ? -1 : 1) * .random(in: 15...55, using: &zufall),
                                  vy: .random(in: -20...10, using: &zufall),
                                  r: .random(in: 1...2, using: &zufall), schwebt: false, wiegen: 0))
        }
    }

    /// Alles, was auf der Kapsel liegt, wird zu fallenden Flocken.
    private func loese(_ k: Kapsel, vy: CGFloat) {
        for s in k.hoehe.indices where k.hoehe[s] > 0.2 {
            var anzahl = k.hoehe[s] * spalte / flockenFlaeche * 2
            let x = k.rahmen.minX + (CGFloat(s) + 0.5) * spalte
            let y = oberflaeche(k, s) - k.hoehe[s] / 2
            while anzahl > 0, flocken.count < hoechstensFlocken {
                if anzahl < 1, CGFloat.random(in: 0...1, using: &zufall) > anzahl { break }
                anzahl -= 1
                flocken.append(Flocke(x: x, y: y, vx: .random(in: -25...25, using: &zufall), vy: vy,
                                      r: .random(in: 1...2, using: &zufall), schwebt: false, wiegen: 0))
            }
        }
    }

    /// Oberkante der Kapsel über Spalte `s` (an den runden Enden tiefer).
    private func oberflaeche(_ k: Kapsel, _ s: Int) -> CGFloat {
        let r = k.rahmen
        let radius = r.height / 2
        let x = r.minX + (CGFloat(s) + 0.5) * spalte
        let abstand = max(r.minX + radius - x, x - (r.maxX - radius), 0)
        return r.midY - sqrt(max(radius * radius - abstand * abstand, 0)) + 0.5
    }

    // MARK: Zeichnen

    func zeichne(in ctx: inout GraphicsContext) {
        ctx.addFilter(.shadow(color: Color(red: 0.2, green: 0.28, blue: 0.4).opacity(0.35), radius: 1.2))
        // Liegender Schnee: eine weiche Haube, die der Form der Kapsel folgt.
        for k in kapseln {
            var p = Path()
            let n = k.hoehe.count
            guard n > 1 else { continue }
            func punkt(_ s: Int) -> CGPoint {
                CGPoint(x: k.rahmen.minX + (CGFloat(s) + 0.5) * spalte, y: oberflaeche(k, s) - k.hoehe[s])
            }
            p.move(to: CGPoint(x: k.rahmen.minX + spalte / 2, y: oberflaeche(k, 0) + 1))
            p.addLine(to: punkt(0))
            for s in 1..<n {
                let a = punkt(s - 1), b = punkt(s)
                p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
            }
            p.addLine(to: punkt(n - 1))
            for s in stride(from: n - 1, through: 0, by: -1) {
                p.addLine(to: CGPoint(x: k.rahmen.minX + (CGFloat(s) + 0.5) * spalte, y: oberflaeche(k, s) + 1))
            }
            p.closeSubpath()
            ctx.fill(p, with: .color(.white))
        }
        // Flocken in der Luft.
        for f in flocken {
            let r = CGRect(x: f.x - f.r, y: f.y - f.r, width: f.r * 2, height: f.r * 2)
            ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(f.schwebt ? 0.55 + f.r / 8 : 0.95)))
        }
    }

    // MARK: Hilfen

    /// Gleichmäßig verteilter Anfangsschnee, zu den runden Enden hin weniger.
    static func anfangsSchnee(breite: CGFloat, spalte: CGFloat, hoehe: CGFloat) -> [CGFloat] {
        let n = max(1, Int(breite / spalte))
        return (0..<n).map { s in
            let rand = min(CGFloat(s), CGFloat(n - 1 - s)) * spalte
            let welle = 1 + 0.18 * sin(CGFloat(s) * 0.35) + 0.1 * sin(CGFloat(s) * 0.9)
            return hoehe * min(rand / 22, 1) * welle
        }
    }

    /// Schnee auf eine neue Spaltenzahl umrechnen (die Kapsel ist breiter oder schmaler geworden).
    static func verteile(_ alt: [CGFloat], auf n: Int) -> [CGFloat] {
        guard !alt.isEmpty else { return Array(repeating: 0, count: n) }
        return (0..<n).map { i in alt[min(alt.count - 1, i * alt.count / n)] }
    }
}

// MARK: - Wo liegt die Tab-Leiste?

/// Findet die Glas-Kapseln der Tab-Leiste im Fenster (auch während sie ein- und ausfährt).
/// Findet sie nichts (andere iOS-Version), bleibt der Schnee einfach nicht liegen.
@MainActor
final class LeistenOrtung {
    private final class Schwach { weak var view: UIView?; init(_ v: UIView) { view = v } }
    private var kapseln: [Schwach] = []
    private var zuletztGesucht: CFTimeInterval = 0

    func rahmen() -> [CGRect] {
        let jetzt = CACurrentMediaTime()
        if kapseln.isEmpty || kapseln.contains(where: { $0.view?.window == nil }) ? jetzt - zuletztGesucht > 0.5 : jetzt - zuletztGesucht > 3 {
            suche()
            zuletztGesucht = jetzt
        }
        guard let fenster = kapseln.lazy.compactMap({ $0.view?.window }).first else { return [] }
        let fensterEbene = fenster.layer.presentation() ?? fenster.layer
        return kapseln.compactMap { s in
            guard let v = s.view, v.window != nil, Self.sichtbar(v) else { return nil }
            let ebene = v.layer.presentation() ?? v.layer
            return ebene.convert(ebene.bounds, to: fensterEbene)
        }
    }

    private func suche() {
        let fenster = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard let fenster, let leiste = Self.finde(UITabBar.self, in: fenster) else { kapseln = []; return }
        var gefunden: [UIView] = []
        Self.sammleKapseln(in: leiste, nach: &gefunden)
        kapseln = gefunden.map(Schwach.init)
    }

    private static func finde<T: UIView>(_ typ: T.Type, in v: UIView) -> T? {
        if let t = v as? T { return t }
        for s in v.subviews { if let t = finde(typ, in: s) { return t } }
        return nil
    }

    /// Die Kapseln heißen intern „…ItemPlatterView“; darin wird nicht weitergesucht.
    private static func sammleKapseln(in v: UIView, nach liste: inout [UIView]) {
        for s in v.subviews {
            if String(describing: type(of: s)).contains("PlatterView") { liste.append(s) } else { sammleKapseln(in: s, nach: &liste) }
        }
    }

    private static func sichtbar(_ v: UIView) -> Bool {
        var aktuell: UIView? = v
        while let a = aktuell {
            if a.isHidden || a.alpha < 0.05 { return false }
            aktuell = a.superview
        }
        return true
    }
}
#endif
