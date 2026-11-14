import SwiftUI
import DesignSystem

/// Konto → Design: große Vorschau-Karten, live gezeichnet in den Farben jedes Designs.
struct DesignAuswahl: View {
    private var zustand: DesignZustand { .shared }
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16)], spacing: 20) {
                ForEach(zustand.waehlbar) { design in
                    Button {
                        withAnimation(wenigBewegung ? nil : .easeInOut(duration: 0.3)) { zustand.waehle(design) }
                    } label: {
                        DesignKarte(design: design, gewaehlt: zustand.design == design)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(design.name)
                    .accessibilityHint(design.beschreibung)
                    .accessibilityAddTraits(zustand.design == design ? .isSelected : [])
                }
            }
            .padding(20)

            Text(zustand.waehlbar.contains(.weihnachten)
                 ? "Weihnachten gibt es vom 1. Dezember bis 6. Januar. Am 1. Dezember geht es von selbst an, am 7. Januar kommt dein vorheriges Design zurück."
                 : "Im Dezember kommt das Design „Weihnachten“ dazu und geht von selbst an.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(LilithColor.hintergrund)
        .navigationTitle("Design")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Eine Karte: kleines Abbild von Luna, darunter Name und ein Satz.
private struct DesignKarte: View {
    let design: Design
    let gewaehlt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DesignMiniatur(design: design)
                .environment(\.colorScheme, design.schema ?? umgebung)
                .aspectRatio(0.62, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(gewaehlt ? LilithColor.nachtrose : Color.primary.opacity(0.1),
                                      lineWidth: gewaehlt ? 3 : 1)
                }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: gewaehlt ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(gewaehlt ? LilithColor.nachtrose : Color.secondary)
                    .accessibilityHidden(true)
                Text(design.name).font(.headline)
            }
            Text(design.beschreibung)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
    }

    @Environment(\.colorScheme) private var umgebung
}

/// Ein kleines Luna: Titel, Fotoraster, Tab-Leiste. Bei Nacht ein paar Sterne, bei Weihnachten Schnee.
private struct DesignMiniatur: View {
    let design: Design

    /// Ruhige Farbflächen statt echter Fotos: Himmel, Sand, Wald, Abendlicht, Stein.
    private static let fotos: [Color] = [
        Color(red: 0.55, green: 0.68, blue: 0.80), Color(red: 0.84, green: 0.76, blue: 0.62),
        Color(red: 0.36, green: 0.50, blue: 0.40), Color(red: 0.86, green: 0.58, blue: 0.45),
        Color(red: 0.62, green: 0.60, blue: 0.58), Color(red: 0.42, green: 0.52, blue: 0.66),
        Color(red: 0.74, green: 0.66, blue: 0.52), Color(red: 0.50, green: 0.60, blue: 0.46),
        Color(red: 0.78, green: 0.52, blue: 0.50), Color(red: 0.30, green: 0.38, blue: 0.50),
        Color(red: 0.88, green: 0.82, blue: 0.70), Color(red: 0.58, green: 0.46, blue: 0.40),
    ]

    var body: some View {
        let p = design.palette
        GeometryReader { geo in
            let breite = geo.size.width
            let rand = breite * 0.07
            let kachel = (breite - 2 * rand - 4) / 3
            ZStack(alignment: .topLeading) {
                p.hintergrund
                if design == .nacht { Sterne(anzahl: 22).opacity(0.8) }

                VStack(alignment: .leading, spacing: breite * 0.05) {
                    Text("Fotos")
                        .font(.system(size: breite * 0.11, weight: .bold))
                        .foregroundStyle(.primary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(kachel), spacing: 2), count: 3), spacing: 2) {
                        ForEach(Self.fotos.indices, id: \.self) { i in
                            Self.fotos[i].frame(width: kachel, height: kachel)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 4))
                }
                .padding(.horizontal, rand)
                .padding(.top, rand * 1.4)

                leiste(p: p, breite: breite)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, rand)

                if design == .weihnachten { Schnee(anzahl: 26) }
            }
        }
    }

    private func leiste(p: Palette, breite: CGFloat) -> some View {
        let hoehe = breite * 0.15
        return HStack(spacing: breite * 0.09) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i == 0 ? p.akzent : Color.primary.opacity(0.35))
                    .frame(width: hoehe * 0.32, height: hoehe * 0.32)
            }
        }
        .frame(width: breite * 0.62, height: hoehe)
        .background(.regularMaterial, in: .capsule)
        .overlay(alignment: .top) {
            if design == .weihnachten {
                // Eine Schneekappe auf der Leiste.
                Capsule().fill(.white)
                    .frame(width: breite * 0.5, height: hoehe * 0.2)
                    .offset(y: -hoehe * 0.06)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
        }
    }
}

/// Feste Punkte, damit die Vorschau ruhig steht (gleiches Bild bei jedem Zeichnen).
private struct Sterne: View {
    let anzahl: Int
    var body: some View {
        Canvas { ctx, size in
            var z: UInt64 = 7
            func zufall() -> Double { z = z &* 6364136223846793005 &+ 1442695040888963407; return Double(z >> 33) / Double(1 << 31) }
            for _ in 0..<anzahl {
                let r = 0.5 + zufall() * 1.0
                let pkt = CGPoint(x: zufall() * size.width, y: zufall() * size.height * 0.85)
                ctx.fill(Path(ellipseIn: CGRect(x: pkt.x - r, y: pkt.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white.opacity(0.4 + zufall() * 0.5)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Schnee: View {
    let anzahl: Int
    var body: some View {
        Canvas { ctx, size in
            var z: UInt64 = 31
            func zufall() -> Double { z = z &* 6364136223846793005 &+ 1442695040888963407; return Double(z >> 33) / Double(1 << 31) }
            ctx.addFilter(.shadow(color: Color(red: 0.2, green: 0.28, blue: 0.4).opacity(0.35), radius: 1))
            for _ in 0..<anzahl {
                let r = 1 + zufall() * 1.6
                let pkt = CGPoint(x: zufall() * size.width, y: zufall() * size.height * 0.8)
                ctx.fill(Path(ellipseIn: CGRect(x: pkt.x - r, y: pkt.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white.opacity(0.95)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Grund der Sammlungen: im Design „Nacht“ mit ein paar leisen Sternen.
struct DesignGrund: View {
    var body: some View {
        ZStack {
            LilithColor.hintergrund
            if DesignZustand.shared.design == .nacht { Sterne(anzahl: 40).opacity(0.35) }
        }
    }
}
