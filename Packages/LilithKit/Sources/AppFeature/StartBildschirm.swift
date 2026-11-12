import SwiftUI
import DesignSystem

/// Ladebildschirm beim Start: derselbe Nachthimmel mit Mond wie der Startbildschirm von iOS,
/// damit der Übergang nahtlos ist. Der Mond nimmt zu, der Name erscheint, bis die Bibliothek bereit ist.
struct StartBildschirm: View {
    @State private var phase = 0.35
    @State private var nameSichtbar = false
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    /// Farbe wie „StartFarbe“ im Asset-Katalog der App.
    static let nacht = Color(red: 0x12 / 255, green: 0x0E / 255, blue: 0x10 / 255)

    var body: some View {
        ZStack {
            Self.nacht.ignoresSafeArea()
            // Mitte des ganzen Bildschirms, 120 pt groß: genau wie das Bild im Startbildschirm.
            MondSymbol(phase: phase)
                .frame(width: 120, height: 120)
            Text("Lilith")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color(red: 0xF4 / 255, green: 0xED / 255, blue: 0xE4 / 255))
                .offset(y: 110)
                .opacity(nameSichtbar ? 1 : 0)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lilith wird geladen")
        .task {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { nameSichtbar = true }
            guard !wenigBewegung else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { phase = 0.8 }
        }
    }
}
