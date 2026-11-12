import SwiftUI
import DesignSystem

/// Schnelles Springen durch die Timeline: Leiste am rechten Rand.
/// Beim Ziehen zeigt eine Blase den Monat, bei jedem Monatswechsel gibt es einen haptischen Tick.
public struct Scrubber: View {
    let quelle: TimelineQuelle
    /// Aktuelle Scroll-Position (0…1), damit der Griff mitwandert.
    let anteil: Double
    let springe: (Int) -> Void

    @State private var ziehend = false
    @State private var fingerAnteil = 0.0
    @State private var zielSection: Int?
    @State private var sichtbar = false
    @State private var ausblenden: Task<Void, Never>?
    @State private var letzteBewegung = Date.distantPast

    public init(quelle: TimelineQuelle, anteil: Double, springe: @escaping (Int) -> Void) {
        self.quelle = quelle
        self.anteil = anteil
        self.springe = springe
    }

    public var body: some View {
        GeometryReader { geo in
            let hoehe = max(geo.size.height - 40, 1)
            let position = ziehend ? fingerAnteil : min(max(anteil, 0), 1)
            ZStack(alignment: .topTrailing) {
                Color.clear
                if sichtbar || ziehend {
                    Capsule()
                        .fill(ziehend ? LilithColor.nachtroseFill : LilithColor.mondlicht)
                        .frame(width: 6, height: 40)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: -6, y: position * hoehe)
                        .transition(.opacity)
                }
                if ziehend, let zielSection, zielSection < quelle.sections.count {
                    Text(quelle.sections[zielSection].titel)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .offset(x: -30, y: position * hoehe + 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 220, alignment: .trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .overlay(alignment: .trailing) {
                // Nur ein schmaler Streifen am Rand nimmt Gesten an, damit das Grid bedienbar bleibt.
                Color.clear
                    .frame(width: 36)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { wert in
                                if !ziehend { withAnimation(.easeOut(duration: 0.15)) { ziehend = true } }
                                fingerAnteil = min(max((wert.location.y - 20) / hoehe, 0), 1)
                                if let ziel = quelle.section(beiAnteil: fingerAnteil), ziel != zielSection {
                                    zielSection = ziel
                                    springe(ziel)
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.25)) { ziehend = false }
                                zeigeKurz()
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Zeitleiste")
                    .accessibilityValue(zielSection.map { quelle.sections[$0].titel } ?? "")
                    .accessibilityAdjustableAction { richtung in
                        let aktuell = zielSection ?? quelle.section(beiAnteil: anteil) ?? 0
                        let neu = richtung == .increment ? min(aktuell + 1, quelle.sections.count - 1) : max(aktuell - 1, 0)
                        zielSection = neu
                        springe(neu)
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: zielSection)
        .onChange(of: anteil) { _, _ in if !ziehend { zeigeKurz() } }
    }

    /// Griff beim Scrollen einblenden und nach kurzer Ruhe wieder ausblenden.
    /// Beim Scrollen kommt das bis zu 120-mal pro Sekunde: nur die Zeit merken, eine einzige Aufgabe wartet.
    private func zeigeKurz() {
        letzteBewegung = .now
        if !sichtbar { withAnimation(.easeOut(duration: 0.2)) { sichtbar = true } }
        guard ausblenden == nil else { return }
        ausblenden = Task {
            while !Task.isCancelled {
                let rest = 1.5 - Date.now.timeIntervalSince(letzteBewegung)
                if rest <= 0 { break }
                try? await Task.sleep(for: .seconds(rest))
            }
            ausblenden = nil
            guard !ziehend else { return }
            withAnimation(.easeIn(duration: 0.3)) { sichtbar = false }
        }
    }
}
