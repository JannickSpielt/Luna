import SwiftUI
import DesignSystem
import TimelineGrid

/// Kleine Vorschaubilder unter dem Foto, wie in Apple Fotos: das aktuelle etwas breiter, Antippen springt hin.
struct VorschauLeiste: View {
    let seiten: [DetailPosition]
    let aktuell: DetailPosition?
    let quelle: TimelineQuelle
    let waehle: (DetailPosition) -> Void

    /// Nur die Nachbarn zeigen, damit die Leiste leicht bleibt.
    private var sichtbar: [DetailPosition] {
        guard let aktuell, let i = seiten.firstIndex(of: aktuell) else { return [] }
        return Array(seiten[max(0, i - 20)...min(seiten.count - 1, i + 20)])
    }

    var body: some View {
        ScrollViewReader { leser in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(sichtbar, id: \.self) { p in
                        let istAktuell = p == aktuell
                        LeistenBild(item: quelle.item(section: p.section, index: p.index), quelle: quelle)
                            .frame(width: istAktuell ? 40 : 21, height: 32)
                            .clipShape(.rect(cornerRadius: 3))
                            .padding(.horizontal, istAktuell ? 6 : 0)
                            .contentShape(.rect)
                            .onTapGesture { waehle(p) }
                            .id(p)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 180, for: .scrollContent)
            .frame(height: 34)
            .onAppear { leser.scrollTo(aktuell, anchor: .center) }
            .onChange(of: aktuell) { _, neu in
                withAnimation(.smooth(duration: 0.25)) { leser.scrollTo(neu, anchor: .center) }
            }
            .animation(.smooth(duration: 0.25), value: aktuell)
        }
        .accessibilityHidden(true)
    }
}

/// Ein Vorschaubild der Leiste (Server oder Gerät).
private struct LeistenBild: View {
    let item: Kachel?
    let quelle: TimelineQuelle
    @State private var bild: Image?
    @Environment(\.displayScale) private var skala

    var body: some View {
        Color(rgb: item?.farbe ?? 0x333333)
            .overlay { bild?.resizable().scaledToFill() }
            .clipped()
            .task(id: item?.id) {
                guard let item else { bild = nil; return }
                if item.lokal != nil {
                    if let cg = await quelle.lokalesBild(fuer: item, pixel: 44 * skala) {
                        bild = Image(decorative: cg, scale: skala)
                    }
                } else if let anfrage = quelle.bildAnfragen(fuer: item, pixel: 44 * skala).first,
                          let p = try? await BilderCache.lade(anfrage) {
                    bild = Image(plattform: p)
                }
            }
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
