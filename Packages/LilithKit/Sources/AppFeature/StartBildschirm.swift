import SwiftUI
import DesignSystem

/// Ladebildschirm beim Start: derselbe Nachthimmel mit Mond wie der Startbildschirm von iOS,
/// damit der Übergang nahtlos ist. Der Mond nimmt zu, der Name erscheint, bis die Bibliothek bereit ist.
/// Ist die Bibliothek geladen, wird der Mond voll und kommt auf einen zu: In seiner Mitte öffnet sich
/// ein Kreis, durch den man in die App fällt (`oeffnung` von 0 bis 1).
struct StartBildschirm: View {
    /// Erst wird der Mond voll, dann geht es hinein.
    var vollmond = false
    var oeffnung: Double = 0
    @State private var phase = 0.35
    /// Steht sofort da, genau wie im Startbild von iOS davor.
    @State private var nameSichtbar = true
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    /// Farbe wie „StartFarbe“ im Asset-Katalog der App.
    static let nacht = Color(red: 0x12 / 255, green: 0x0E / 255, blue: 0x10 / 255)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Nachthimmel mit einem Loch in der Mitte. Das Loch sitzt im Mond und wächst mit ihm.
                NachtMitLoch(loch: 120 * (1 + 7 * oeffnung) * oeffnung * 1.15)
                    .fill(Self.nacht, style: FillStyle(eoFill: true))
                // Mitte des ganzen Bildschirms, 120 pt groß: genau wie das Bild im Startbildschirm.
                MondSymbol(phase: vollmond || oeffnung > 0 ? 1 : phase)
                    .frame(width: 120, height: 120)
                    .scaleEffect(1 + 7 * oeffnung)
                    .opacity(1 - max((oeffnung - 0.5) / 0.5, 0))
                VStack(spacing: 6) {
                    Text("Lilith")
                        .font(.system(size: 34, weight: .semibold))
                    Text("von Jannick Stahn")
                        .font(.subheadline)
                        .opacity(0.6)
                }
                .foregroundStyle(Color(red: 0xF4 / 255, green: 0xED / 255, blue: 0xE4 / 255))
                // Oberkante wie vorher (Name 110 pt unter der Mitte), der Untertitel hängt darunter.
                .offset(y: 124 + 200 * oeffnung)
                    .opacity(nameSichtbar ? 1 - min(oeffnung * 3, 1) : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(oeffnung == 0)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lilith wird geladen")
        .task {
            guard !wenigBewegung else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = 0.8 }
        }
    }
}

/// Bildschirmfläche mit einem runden Loch in der Mitte (gerade-ungerade gefüllt).
private struct NachtMitLoch: Shape {
    var loch: CGFloat

    var animatableData: CGFloat {
        get { loch }
        set { loch = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if loch > 0.5 {
            p.addEllipse(in: CGRect(x: rect.midX - loch / 2, y: rect.midY - loch / 2, width: loch, height: loch))
        }
        return p
    }
}
