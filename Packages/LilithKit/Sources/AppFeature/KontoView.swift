import SwiftUI
import DesignSystem
import Networking
import Backup

/// Konto und Server: wer angemeldet ist, welcher Server, Abmelden.
struct KontoView: View {
    let account: Account
    var backup: BackupDienst?
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var frageAbmelden = false
    @AppStorage(Entsperren.schluessel) private var sperreAn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(String(account.user.name.prefix(1)).uppercased())
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(LilithColor.nachtroseFill, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.user.name).font(.headline)
                            Text(account.user.email).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                #if os(iOS)
                if let backup { BackupKarte(backup: backup) }
                #endif

                Section("Server") {
                    LabeledContent("Adresse", value: account.server.address.description)
                    LabeledContent("Immich", value: account.server.version.description)
                    LabeledContent("Anmeldung", value: account.usesAPIKey ? "API-Key" : "Passwort")
                    if account.user.isAdmin {
                        LabeledContent("Rolle", value: "Administrator")
                    }
                }

                Section("Auf dem Server verfügbar") {
                    Faehigkeit("Smart Search", an: account.server.capabilities.smartSearch)
                    Faehigkeit("Gesichtserkennung", an: account.server.capabilities.facialRecognition)
                    Faehigkeit("Karte", an: account.server.capabilities.map)
                    Faehigkeit("Papierkorb", an: account.server.capabilities.trash)
                    Faehigkeit("Texterkennung (OCR)", an: account.server.capabilities.ocr)
                }

                Section {
                    Toggle("Mit \(Entsperren.methode) sperren", isOn: Binding(
                        get: { sperreAn },
                        set: { neu in
                            // Beim Einschalten einmal prüfen, dass das Entsperren auch wirklich klappt.
                            if neu {
                                Task { if await Entsperren.pruefe(grund: "App-Sperre einschalten") { sperreAn = true } }
                            } else {
                                sperreAn = false
                            }
                        }))
                    .disabled(!Entsperren.verfuegbar)
                } header: {
                    Text("Sicherheit")
                } footer: {
                    Text(Entsperren.verfuegbar
                         ? "Lilith sperrt sich, sobald du die App verlässt."
                         : "Richte auf diesem Gerät zuerst einen Code oder \(Entsperren.methode) ein.")
                }

                Section {
                    Button("Abmelden", role: .destructive) { frageAbmelden = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Konto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Von \(account.server.address.description) abmelden?",
                                isPresented: $frageAbmelden, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) {
                    Task {
                        dismiss()
                        await session.abmelden()
                    }
                }
            } message: {
                Text("Deine Fotos bleiben auf dem Server. Du kannst dich jederzeit wieder anmelden.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }
}

private struct Faehigkeit: View {
    let titel: String
    let an: Bool

    init(_ titel: String, an: Bool) {
        self.titel = titel
        self.an = an
    }

    var body: some View {
        LabeledContent(titel) {
            Image(systemName: an ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(an ? Color.green : Color.secondary)
                .accessibilityLabel(an ? "an" : "aus")
        }
    }
}
