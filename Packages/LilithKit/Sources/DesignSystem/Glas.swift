import SwiftUI

extension View {
    /// Liquid Glass für schwebende Bedienelemente (ab iOS/macOS 26), sonst ein dünnes Material.
    /// Nur für Bedienelemente über Inhalten, nie für Listen oder Karten (siehe Redesign-Plan).
    /// - Parameter klar: klares Glas über Fotos und Videos (statt normalem).
    @ViewBuilder
    public func lilithGlas<S: Shape>(in form: S, klar: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(klar ? .clear : .regular, in: form)
        } else {
            background(.ultraThinMaterial, in: form)
        }
    }

    /// Glas mit leichter Tönung, z. B. hell über dunklen Videos (wie Apple).
    @ViewBuilder
    public func lilithGlas<S: Shape>(in form: S, toenung: Color) -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular.tint(toenung), in: form)
        } else {
            background(toenung, in: form).background(.ultraThinMaterial, in: form)
        }
    }
}
