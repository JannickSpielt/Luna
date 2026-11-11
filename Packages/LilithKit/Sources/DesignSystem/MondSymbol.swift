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
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(LilithColor.mondlicht)
                Circle()
                    .frame(width: size, height: size)
                    .offset(x: size * phase * 1.1, y: -size * 0.12 * phase)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
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
