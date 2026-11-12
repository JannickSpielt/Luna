import SwiftUI
import DesignSystem
import Networking

/// Verbinden und Anmelden: Serveradresse prüfen, dann mit Passwort oder API-Key anmelden.
struct OnboardingView: View {
    @Environment(SessionStore.self) private var session

    @State private var adresse = ""
    @State private var server: ServerInfo?
    @State private var pruefend = false
    @State private var fehler: String?

    @State private var mitAPIKey = false
    @State private var email = ""
    @State private var passwort = ""
    @State private var apiKey = ""
    @State private var anmeldend = false

    @FocusState private var fokus: Feld?
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung
    private enum Feld { case adresse, email, passwort, apiKey }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                kopf
                adressBereich
                if let server {
                    anmeldeBereich(server)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(LilithColor.hintergrund.ignoresSafeArea())
        .animation(wenigBewegung ? nil : .smooth, value: server)
        .animation(wenigBewegung ? nil : .smooth, value: fehler)
        .onAppear {
            if adresse.isEmpty, let letzte = session.letzteAdresse { adresse = letzte }
            #if DEBUG
            // Zum Testen: Start mit „-LilithServer <adresse>“ füllt die Adresse vor und prüft sie.
            if adresse.isEmpty, let vorgabe = UserDefaults.standard.string(forKey: "LilithServer") {
                adresse = vorgabe
                pruefen()
            }
            #endif
        }
    }

    // MARK: - Teile

    private var kopf: some View {
        VStack(spacing: 16) {
            MondSymbol(phase: server == nil ? 0.15 : 1)
                .frame(width: 88, height: 88)
                .animation(wenigBewegung ? nil : .easeInOut(duration: 0.9), value: server == nil)
            Text("Deine Fotos.\nDein Server.")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(LilithColor.text)
            Text("Verbinde Lilith mit deiner Immich-Instanz. Deine Fotos bleiben bei dir.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(LilithColor.textLeise)
            if let hinweis = session.hinweis {
                Label(hinweis, systemImage: "clock.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(LilithColor.nachtrose)
            }
        }
    }

    private var adressBereich: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Serveradresse").font(.footnote.weight(.semibold)).foregroundStyle(LilithColor.textLeise)
            HStack(spacing: 10) {
                TextField("fotos.example.de", text: $adresse)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .submitLabel(.next)
                    .focused($fokus, equals: .adresse)
                    .onSubmit(pruefen)
                    .onChange(of: adresse) { _, _ in
                        if server != nil { server = nil }
                        fehler = nil
                    }
                    .lilithFeld()
                if server == nil {
                    Button(action: pruefen) {
                        if pruefend { ProgressView() } else { Text("Verbinden") }
                    }
                    .buttonStyle(LilithButtonStyle(kompakt: true))
                    .disabled(adresse.isEmpty || pruefend)
                }
            }
            if let server {
                Label("Verbunden · Immich \(server.version)" + (server.capabilities.smartSearch ? " · Smart Search verfügbar" : ""),
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else if let fehler {
                Label(fehler, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(LilithColor.nachtrose)
            }
        }
    }

    private func anmeldeBereich(_ server: ServerInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if mitAPIKey || !server.capabilities.passwordLogin {
                feld("API-Key") {
                    SecureField("Aus den Immich-Kontoeinstellungen", text: $apiKey)
                        .focused($fokus, equals: .apiKey)
                        .onSubmit(anmelden)
                }
            } else {
                feld("E-Mail") {
                    TextField("name@beispiel.de", text: $email)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .submitLabel(.next)
                        .focused($fokus, equals: .email)
                        .onSubmit { fokus = .passwort }
                }
                feld("Passwort") {
                    SecureField("Passwort", text: $passwort)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($fokus, equals: .passwort)
                        .onSubmit(anmelden)
                }
            }

            Button(action: anmelden) {
                if anmeldend { ProgressView().tint(.white) } else { Text("Anmelden") }
            }
            .buttonStyle(LilithButtonStyle())
            .disabled(!kannAnmelden(server) || anmeldend)
            .padding(.top, 6)

            if let fehler {
                Label(fehler, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(LilithColor.nachtrose)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if server.capabilities.passwordLogin {
                Button(mitAPIKey ? "Mit E-Mail und Passwort anmelden" : "Mit API-Key anmelden") {
                    mitAPIKey.toggle()
                    fehler = nil
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LilithColor.nachtrose)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func feld<Inhalt: View>(_ titel: String, @ViewBuilder inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titel).font(.footnote.weight(.semibold)).foregroundStyle(LilithColor.textLeise)
            inhalt().lilithFeld()
        }
    }

    // MARK: - Aktionen

    private func kannAnmelden(_ server: ServerInfo) -> Bool {
        if mitAPIKey || !server.capabilities.passwordLogin { return !apiKey.isEmpty }
        return !email.isEmpty && !passwort.isEmpty
    }

    private func pruefen() {
        guard !adresse.isEmpty, !pruefend else { return }
        pruefend = true
        fehler = nil
        Task {
            defer { pruefend = false }
            do {
                server = try await session.pruefe(adresse: adresse)
                fokus = mitAPIKey ? .apiKey : .email
            } catch {
                fehler = error.localizedDescription
            }
        }
    }

    private func anmelden() {
        guard let server, kannAnmelden(server), !anmeldend else { return }
        anmeldend = true
        fehler = nil
        Task {
            defer { anmeldend = false }
            do {
                if mitAPIKey || !server.capabilities.passwordLogin {
                    try await session.anmelden(bei: server, apiKey: apiKey)
                } else {
                    try await session.anmelden(bei: server, email: email, passwort: passwort)
                }
            } catch {
                fehler = error.localizedDescription
                self.server = server
            }
        }
    }
}

// MARK: - Stil

extension View {
    /// Eingabefeld im Lilith-Stil.
    func lilithFeld() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(LilithColor.flaeche, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LilithColor.text.opacity(0.12)))
    }
}

/// Hauptbutton in Nachtrose.
struct LilithButtonStyle: ButtonStyle {
    var kompakt = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: kompakt ? nil : .infinity, minHeight: 50)
            .padding(.horizontal, kompakt ? 18 : 0)
            .background(LilithColor.nachtroseFill, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(.capsule)
    }
}

#Preview {
    OnboardingView().environment(SessionStore())
}
