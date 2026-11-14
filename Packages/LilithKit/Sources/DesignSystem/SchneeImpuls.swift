#if canImport(UIKit)
import QuartzCore
import UIKit

/// Bewegungen in der App (Scrollen, Tab-Wechsel), die liegenden Schnee hochwirbeln.
/// Wer sich bewegt, meldet seine Geschwindigkeit; die Schneewelt holt sie einmal pro Bild ab.
@MainActor
public enum SchneeImpuls {
    private static var staerke: CGFloat = 0

    /// Eine Bewegung mit ihrer Geschwindigkeit in Punkt pro Sekunde (Vorzeichen egal).
    public static func melde(_ geschwindigkeit: CGFloat) {
        guard geschwindigkeit.isFinite else { return }
        staerke = max(staerke, abs(geschwindigkeit))
    }

    /// Holt die stärkste Bewegung seit dem letzten Abholen und setzt sie zurück.
    public static func nimm() -> CGFloat {
        defer { staerke = 0 }
        return staerke
    }
}

/// Misst aus aufeinanderfolgenden Scroll-Positionen die Geschwindigkeit und meldet sie als Impuls.
@MainActor
public final class ScrollTempo {
    private var letzte: (y: CGFloat, zeit: CFTimeInterval)?

    public init() {}

    public func melde(_ y: CGFloat) {
        let jetzt = CACurrentMediaTime()
        if let l = letzte {
            let dt = jetzt - l.zeit
            if dt > 0.004, dt < 0.25 { SchneeImpuls.melde((y - l.y) / CGFloat(dt)) }
        }
        letzte = (y, jetzt)
    }
}
#endif
