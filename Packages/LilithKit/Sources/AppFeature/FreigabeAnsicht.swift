import SwiftUI
import DesignSystem
import Networking

/// Was geteilt werden soll.
struct FreigabeZiel: Identifiable, Hashable {
    enum Art: Hashable {
        case album(id: String, name: String)
        case fotos([String])
    }

    let art: Art
    var id: Art { art }

    var titel: String {
        switch art {
        case .album(_, let name): "„\(name)“ teilen"
        case .fotos(let ids): ids.count == 1 ? "1 Foto teilen" : "\(ids.count) Fotos teilen"
        }
    }
}

/// Freigabe-Link anlegen: Ablauf, Passwort, Download. Danach Link teilen oder kopieren.
struct FreigabeBlatt: View {
    let ziel: FreigabeZiel
    @Environment(BibliothekKontext.self) private var kontext
    @Environment(\.dismiss) private var dismiss

    enum Ablauf: String, CaseIterable, Identifiable {
        case tag = "1 Tag", woche = "7 Tage", monat = "30 Tage", nie = "Nie"
        var id: String { rawValue }
        var datum: Date? {
            switch self {
            case .tag: .now.addingTimeInterval(86_400)
            case .woche: .now.addingTimeInterval(7 * 86_400)
            case .monat: .now.addingTimeInterval(30 * 86_400)
            case .nie: nil
            }
        }
    }

    @State private var ablauf: Ablauf = .woche
    @State private var mitPasswort = false
    @State private var passwort = ""
    @State private var download = true
    @State private var arbeitet = false
    @State private var ergebnis: Freigabe?
    @State private var fehler: String?
    @State private var kopiert = false

    var body: some View {
        NavigationStack {
            Form {
                if let ergebnis {
                    Section {
                        Text(ergebnis.link.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        ShareLink(item: ergebnis.link) { Label("Link senden", systemImage: "square.and.arrow.up") }
                        Button {
                            kopiere(ergebnis.link)
                        } label: {
                            Label(kopiert ? "Kopiert" : "Link kopieren", systemImage: kopiert ? "checkmark" : "doc.on.doc")
                        }
                    } header: {
                        Text("Link ist bereit")
                    } footer: {
                        Text(fusszeile(ergebnis))
                    }
                } else {
                    Section {
                        Picker("Gültig", selection: $ablauf) {
                            ForEach(Ablauf.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("Herunterladen erlauben", isOn: $download).tint(LilithColor.schalter)
                        Toggle("Mit Passwort", isOn: $mitPasswort.animation()).tint(LilithColor.schalter)
                        if mitPasswort {
                            SecureField("Passwort", text: $passwort)
                                .textContentType(.newPassword)
                        }
                    } footer: {
                        Text("Wer den Link hat, sieht die Fotos im Browser, auch ohne Konto. Du kannst den Link jederzeit unter Konto → Geteilte Links löschen.")
                    }
                    Section {
                        Button {
                            erstelle()
                        } label: {
                            HStack {
                                Text("Link erstellen")
                                Spacer()
                                if arbeitet { ProgressView() }
                            }
                        }
                        .disabled(arbeitet || (mitPasswort && passwort.isEmpty))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(ziel.titel)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
                Button("OK") { fehler = nil }
            } message: { Text($0) }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func fusszeile(_ f: Freigabe) -> String {
        var teile: [String] = []
        if let a = f.ablauf { teile.append("Gültig bis \(a.formatted(date: .abbreviated, time: .shortened))") } else { teile.append("Gültig ohne Ablauf") }
        if f.mitPasswort { teile.append("mit Passwort") }
        teile.append(f.erlaubtDownload ? "Herunterladen erlaubt" : "nur ansehen")
        return teile.joined(separator: " · ")
    }

    private func erstelle() {
        guard let client = kontext.client else { return }
        arbeitet = true
        Task {
            do {
                switch ziel.art {
                case .album(let id, _):
                    ergebnis = try await client.erstelleFreigabe(album: id, ablauf: ablauf.datum,
                                                                 passwort: mitPasswort ? passwort : nil, download: download)
                case .fotos(let ids):
                    ergebnis = try await client.erstelleFreigabe(fotos: ids, ablauf: ablauf.datum,
                                                                 passwort: mitPasswort ? passwort : nil, download: download)
                }
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
            arbeitet = false
        }
    }

    private func kopiere(_ url: URL) {
        #if os(iOS)
        UIPasteboard.general.url = url
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
        withAnimation { kopiert = true }
    }
}

/// Alle eigenen Freigabe-Links: teilen, kopieren, löschen.
struct FreigabenListe: View {
    let client: ImmichClient?
    @State private var liste: [Freigabe]?
    @State private var fehler: String?

    var body: some View {
        Group {
            if let liste {
                if liste.isEmpty {
                    ContentUnavailableView("Keine geteilten Links", systemImage: "link",
                                           description: Text("Teile ein Album über das Ansicht-Menü oder ausgewählte Fotos über „Link“."))
                } else {
                    List {
                        ForEach(liste) { f in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.titel).font(.body.weight(.medium))
                                Text(f.link.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                Text(f.abgelaufen ? "Abgelaufen" : (f.ablauf.map { "Gültig bis \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Ohne Ablauf"))
                                    .font(.caption).foregroundStyle(f.abgelaufen ? .red : .secondary)
                            }
                            .contextMenu {
                                ShareLink(item: f.link) { Label("Senden", systemImage: "square.and.arrow.up") }
                                Button("Löschen", systemImage: "trash", role: .destructive) { loesche(f) }
                            }
                            .swipeActions {
                                Button("Löschen", role: .destructive) { loesche(f) }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Geteilte Links")
        .task { await lade() }
        .refreshable { await lade() }
        .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
            Button("OK") { fehler = nil }
        } message: { Text($0) }
    }

    private func lade() async {
        guard let client else { liste = []; return }
        do { liste = try await client.freigaben() } catch {
            if liste == nil { liste = [] }
            fehler = error.localizedDescription
        }
    }

    private func loesche(_ f: Freigabe) {
        guard let client else { return }
        Task {
            do {
                try await client.loescheFreigabe(f.id)
                withAnimation { liste?.removeAll { $0.id == f.id } }
            } catch { fehler = error.localizedDescription }
        }
    }
}
