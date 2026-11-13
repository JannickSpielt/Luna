import SwiftUI

/// Der Lilith-Mond. `phase` reicht von 0 (Neumond) bis 1 (Vollmond).
/// Wird später auch für den Verbindungsstatus genutzt
/// (voll = Heimnetz, Sichel = unterwegs, Neumond = offline).
public struct MondSymbol: View {
    public var phase: Double

    public init(phase: Double = 0.35) {
        self.phase = min(max(phase, 0), 1)
    }

    public var body: some View {
        // Nur der beleuchtete Teil wird gezeichnet (Kreis minus Schatten-Kreis). Kein Ausstanzen mehr:
        // Das ließ auf Glas-Hintergründen einen zweiten Kreis durchscheinen.
        MondForm(phase: phase)
            .fill(LilithColor.mondlicht)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// Mondsichel als Form, damit sich die Phase weich animieren lässt.
public struct MondForm: Shape {
    public var phase: Double

    public init(phase: Double) { self.phase = min(max(phase, 0), 1) }

    public var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let kante = min(rect.width, rect.height)
        let mond = CGRect(x: rect.midX - kante / 2, y: rect.midY - kante / 2, width: kante, height: kante)
        // Bei Vollmond ist der Schatten ganz weg.
        guard phase < 0.999 else { return Path(ellipseIn: mond) }
        let schatten = mond.offsetBy(dx: kante * phase * 1.1, dy: -kante * 0.12 * phase)
        return Path(ellipseIn: mond).subtracting(Path(ellipseIn: schatten))
    }
}

#Preview {
    HStack(spacing: 24) {
        MondSymbol(phase: 0).frame(width: 48)
        MondSymbol(phase: 0.35).frame(width: 48)
        MondSymbol(phase: 1).frame(width: 48)
    }
    .padding()
    .background(LilithColor.hintergrund)
}
