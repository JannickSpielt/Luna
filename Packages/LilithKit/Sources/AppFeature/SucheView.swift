import SwiftUI
import DesignSystem
import Networking

/// Der Suchen-Tab: Smart Search in normaler Sprache.
struct SucheView: View {
    @Environment(BibliothekKontext.self) private var kontext
    @State private var text = ""
    @State private var store: TimelineStore?
    @State private var gesucht = ""

    private let beispiele = ["Katze auf dem Sofa", "Sonnenuntergang am See", "Essen im Restaurant", "Berge mit Schnee", "rotes Auto"]

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    TimelineInhalt(titel: "„\(gesucht)“", quelle: store, store: store)
                        .id(gesucht)
                } else {
                    hinweis
                }
            }
            .background(LilithColor.hintergrund)
            .navigationTitle("Suche")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .searchable(text: $text, prompt: "Fotos beschreiben, z. B. „Hund am Strand“")
        .onSubmit(of: .search) { suche(text) }
        .onChange(of: text) { _, neu in
            // Feld geleert: zurück zum Startbildschirm.
            if neu.isEmpty { store = nil; gesucht = "" }
        }
    }

    @ViewBuilder
    private var hinweis: some View {
        if kontext.client == nil {
            ContentUnavailableView("Suche", systemImage: "magnifyingglass",
                                   description: Text("Die Suche gibt es nur mit einer Verbindung zum Server."))
        } else if !kontext.smartSearch {
            ContentUnavailableView("Smart Search ist aus", systemImage: "magnifyingglass",
                                   description: Text("Auf deinem Immich-Server ist Machine Learning ausgeschaltet. Schalte es dort ein, um Fotos per Beschreibung zu finden."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MondSymbol(phase: 0.3).frame(width: 44, height: 44)
                    Text("Beschreib, was du suchst")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text("Lilith findet Fotos über ihren Inhalt. Du brauchst keine Schlagworte.")
                        .foregroundStyle(LilithColor.textLeise)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(beispiele, id: \.self) { beispiel in
                            Button {
                                text = beispiel
                                suche(beispiel)
                            } label: {
                                Label(beispiel, systemImage: "magnifyingglass")
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(LilithColor.flaeche, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
    }

    private func suche(_ eingabe: String) {
        let anfrage = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anfrage.isEmpty, anfrage != gesucht, kontext.smartSearch, let client = kontext.client else { return }
        let neu = TimelineStore(client: client, filter: .suche(anfrage))
        let k = kontext
        neu.onSitzungAbgelaufen = { [weak k] in k?.onSitzungAbgelaufen?() }
        gesucht = anfrage
        store = neu
    }
}
