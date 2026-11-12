import SwiftUI
import DesignSystem

/// Einmal nach dem ersten kompletten Backup: Der Mond geht auf. „Alles sicher. Gute Nacht.“
struct VollmondMoment: View {
    let fertig: () -> Void
    @State private var phase = 0.0
    @State private var aufgegangen = false
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 22) {
                MondSymbol(phase: phase)
                    .frame(width: 140, height: 140)
                    .shadow(color: LilithColor.mondlicht.opacity(0.6), radius: aufgegangen ? 40 : 0)
                    .offset(y: aufgegangen ? 0 : 120)
                VStack(spacing: 6) {
                    Text("Alles sicher.")
                        .font(.largeTitle.bold())
                    Text("Gute Nacht.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .opacity(aufgegangen ? 1 : 0)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: fertig)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alles sicher. Dein erstes Backup ist fertig.")
        .accessibilityAddTraits(.isButton)
        .task {
            if wenigBewegung {
                phase = 1
                aufgegangen = true
            } else {
                withAnimation(.easeOut(duration: 2.2)) { aufgegangen = true }
                withAnimation(.easeInOut(duration: 2.6)) { phase = 1 }
            }
            try? await Task.sleep(for: .seconds(5))
            fertig()
        }
    }
}
