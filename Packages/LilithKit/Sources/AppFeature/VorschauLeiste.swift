import SwiftUI
import DesignSystem
import TimelineGrid

/// Kleine Vorschaubilder unter dem Foto, wie in Apple Fotos: das aktuelle etwas breiter.
/// Antippen springt hin, Wischen über die Leiste blättert mit. Die Leiste lädt rund um das aktuelle Foto immer nach.
struct VorschauLeiste: View {
    let aktuell: DetailPosition?
    let quelle: TimelineQuelle
    /// Wie die Fotoansicht: in „Fotos“ ältere links, neuere rechts.
    var aeltereLinks = false
    let waehle: (DetailPosition) -> Void
    /// Meldet, ob gerade über die Leiste gewischt wird (dann nichts automatisch ausblenden).
    var wischt: (Bool) -> Void = { _ in }

    /// Wie viele Nachbarn auf jeder Seite. Rückt mit dem aktuellen Foto mit, endet also nie vor Anfang oder Ende.
    private static let radius = 120
    @State private var mitte: DetailPosition?
    @State private var nutzerWischt = false

    private var sichtbar: [DetailPosition] {
        guard let aktuell else { return [] }
        return DetailView.fenster(um: aktuell, quelle: quelle, radius: Self.radius, aeltereLinks: aeltereLinks)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 2) {
                ForEach(sichtbar, id: \.self) { p in
                    let istAktuell = p == aktuell
                    LeistenBild(item: quelle.item(section: p.section, index: p.index), quelle: quelle, section: p.section)
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
        .contentMargins(.horizontal, 200, for: .scrollContent)
        .scrollPosition(id: $mitte, anchor: .center)
        .frame(height: 34)
        .onScrollPhaseChange { _, phase in
            nutzerWischt = phase == .interacting || phase == .decelerating
            wischt(nutzerWischt)
        }
        // Wischt der Nutzer über die Leiste, blättert das Foto mit.
        .onChange(of: mitte) { _, neu in
            if nutzerWischt, let neu, neu != aktuell { waehle(neu) }
        }
        // Blättert der Nutzer im Foto, rückt die Leiste nach.
        .onChange(of: aktuell) { _, neu in
            guard !nutzerWischt else { return }
            withAnimation(.smooth(duration: 0.25)) { mitte = neu }
        }
        .onAppear { mitte = aktuell }
        .animation(.smooth(duration: 0.25), value: aktuell)
        .accessibilityHidden(true)
    }
}

/// Ein Vorschaubild der Leiste (Server oder Gerät).
private struct LeistenBild: View {
    let item: Kachel?
    let quelle: TimelineQuelle
    let section: Int
    @State private var bild: Image?
    @Environment(\.displayScale) private var skala

    var body: some View {
        Color(rgb: item?.farbe ?? 0x333333)
            .overlay { bild?.resizable().scaledToFill() }
            .clipped()
            .task(id: item?.id) {
                // Monat noch nicht geladen: anstoßen, die Leiste zeigt bis dahin die Platzhalterfarbe.
                guard let item else { quelle.ladeMonat(section); bild = nil; return }
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
