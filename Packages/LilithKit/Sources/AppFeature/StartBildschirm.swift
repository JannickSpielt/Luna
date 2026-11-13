import SwiftUI
import DesignSystem

/// Ladebildschirm beim Start: derselbe Nachthimmel mit Mond wie der Startbildschirm von iOS,
/// damit der Übergang nahtlos ist. Der Mond nimmt zu, der Name erscheint, bis die Bibliothek bereit ist.
/// Ist die Bibliothek geladen, wird der Mond voll und kommt auf einen zu: In seiner Mitte öffnet sich
/// ein Kreis, durch den man in die App fällt (`oeffnung` von 0 bis 1).
struct StartBildschirm: View {
    /// Erst wird der Mond voll, dann geht es hinein.
    var vollmond = false
    /// Unten „von Jannick Stahn“: erscheint, sobald alles geladen ist (das Zeichen, dass es gleich losgeht).
    var geladen = false
    var oeffnung: Double = 0
    @State private var phase = 0.35
    private let weihnachten = Weihnachten.aktiv
    /// Steht sofort da, genau wie im Startbild von iOS davor.
    @State private var nameSichtbar = true
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    /// Farbe wie „StartFarbe“ im Asset-Katalog der App.
    static let nacht = Color(red: 0x12 / 255, green: 0x0E / 255, blue: 0x10 / 255)
    static let creme = Color(red: 0xF4 / 255, green: 0xED / 255, blue: 0xE4 / 255)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Nachthimmel mit einem Loch in der Mitte. Das Loch sitzt im Mond und wächst mit ihm.
                NachtMitLoch(loch: 120 * (1 + 7 * oeffnung) * oeffnung * 1.15)
                    .fill(Self.nacht, style: FillStyle(eoFill: true))
                if weihnachten {
                    // Weihnachtszeit: leiser Schnee vor dem Nachthimmel und ein Stern am Mond.
                    Schneefall(anzahl: 70)
                        .opacity(1 - min(oeffnung * 2, 1))
                    WeihnachtsStern()
                        .font(.system(size: 22))
                        .offset(x: 58, y: -62)
                        .scaleEffect(1 + 7 * oeffnung)
                        .opacity(geladen ? 1 - min(oeffnung * 3, 1) : 0)
                }
                // Mitte des ganzen Bildschirms, 120 pt groß: genau wie das Bild im Startbildschirm.
                MondSymbol(phase: vollmond || oeffnung > 0 ? 1 : phase)
                    .frame(width: 120, height: 120)
                    .scaleEffect(1 + 7 * oeffnung)
                    .opacity(1 - max((oeffnung - 0.5) / 0.5, 0))
                Text("Luna")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Self.creme)
                    // Wie im Startbild von iOS: 110 pt unter der Mitte.
                    .offset(y: 110 + 200 * oeffnung)
                    .opacity(nameSichtbar ? 1 - min(oeffnung * 3, 1) : 0)
                if weihnachten {
                    Text("Frohe Weihnachten")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LilithColor.mondlicht)
                        .offset(y: 146 + 200 * oeffnung)
                        .opacity(geladen ? 1 - min(oeffnung * 3, 1) : 0)
                }
                // Ganz unten, wie bei vielen Apps der Hinweis, von wem sie ist.
                Text("von Jannick Stahn")
                    .font(.subheadline)
                    .foregroundStyle(Self.creme.opacity(0.6))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    // Über dem Home-Balken.
                    .padding(.bottom, 50)
                    .opacity(geladen ? 1 - min(oeffnung * 3, 1) : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(oeffnung == 0)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Luna wird geladen")
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
