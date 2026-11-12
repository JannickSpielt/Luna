import LocalAuthentication
import SwiftUI
import DesignSystem

/// App-Sperre mit Face ID, Touch ID oder Gerätecode.
enum Entsperren {
    static let schluessel = "lilith.appSperre"

    /// Name der Methode für die Oberfläche, z. B. „Face ID“.
    static var methode: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Gerätecode"
        }
    }

    /// Ob das Gerät überhaupt entsperren kann (Biometrie oder Code eingerichtet).
    static var verfuegbar: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Fragt Face ID / Touch ID ab, mit Gerätecode als Ausweg.
    static func pruefe(grund: String = "Lilith entsperren") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: grund)) ?? false
    }
}

/// Deckt die App ab: gesperrt (mit Entsperren-Knopf) oder nur als Sichtschutz im App-Umschalter.
struct SperrBildschirm: View {
    let gesperrt: Bool
    let entsperren: () -> Void

    var body: some View {
        ZStack {
            LilithColor.hintergrund.ignoresSafeArea()
            VStack(spacing: 18) {
                MondSymbol(phase: gesperrt ? 0.15 : 0.6).frame(width: 72, height: 72)
                Text("Lilith").font(.largeTitle.bold())
                if gesperrt {
                    Text("Deine Fotos sind gesperrt.").foregroundStyle(LilithColor.textLeise)
                    Button(action: entsperren) {
                        Label("Mit \(Entsperren.methode) entsperren", systemImage: "lock.open")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(LilithButtonStyle(kompakt: true))
                    .padding(.top, 6)
                }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Legt Sperre und Sichtschutz über die App.
struct SperrSchicht: ViewModifier {
    @AppStorage(Entsperren.schluessel) private var sperreAn = false
    @Environment(\.scenePhase) private var phase
    @State private var gesperrt: Bool = UserDefaults.standard.bool(forKey: Entsperren.schluessel)
    @State private var prueft = false
    /// Beim Start ist die App kurz „nicht aktiv“: Da noch nicht verdecken, sonst flackert es.
    @State private var warAktiv = false

    private var verdecken: Bool {
        #if os(iOS)
        // Im App-Umschalter soll niemand die Fotos sehen.
        return gesperrt || (warAktiv && phase != .active)
        #else
        return gesperrt
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if verdecken {
                    SperrBildschirm(gesperrt: gesperrt, entsperren: entsperre)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: verdecken)
            .onChange(of: phase, initial: true) { _, neu in
                if neu == .active { warAktiv = true }
                if neu == .background && sperreAn { gesperrt = true }
                if neu == .active && gesperrt { entsperre() }
            }
            .onChange(of: sperreAn) { _, an in if !an { gesperrt = false } }
            .task { if gesperrt && phase == .active { entsperre() } }
    }

    private func entsperre() {
        guard !prueft else { return }
        prueft = true
        Task {
            if await Entsperren.pruefe() { gesperrt = false }
            prueft = false
        }
    }
}

extension View {
    func lilithSperre() -> some View { modifier(SperrSchicht()) }
}
