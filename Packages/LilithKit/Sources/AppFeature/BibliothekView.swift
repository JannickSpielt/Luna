import SwiftUI
import DesignSystem
import Networking
import TimelineGrid

/// Die Bibliothek: alle Fotos und Videos als Timeline mit Scrubber.
struct BibliothekView: View {
    let quelle: TimelineQuelle
    /// Nur bei echter Verbindung gesetzt (nicht im Demo-Modus).
    let store: TimelineStore?
    @Binding var zeigeKonto: Bool
    let kontoBuchstabe: String

    var body: some View {
        NavigationStack {
            TimelineInhalt(titel: "Bibliothek", quelle: quelle, store: store,
                           konto: (kontoBuchstabe, { zeigeKonto = true }))
        }
    }
}

/// Eine Timeline mit Scrubber, Detailansicht und Mehrfachauswahl.
/// Wird für die Bibliothek, Favoriten, Archiv, Papierkorb und Alben benutzt.
struct TimelineInhalt: View {
    let titel: String
    let quelle: TimelineQuelle
    let store: TimelineStore?
    var konto: (buchstabe: String, oeffnen: () -> Void)?

    @Environment(BibliothekKontext.self) private var kontext
    @State private var zoom: GridZoom = Self.startZoom
    @State private var sprung: SprungAnfrage?
    @State private var scrollAnteil = 0.0
    @State private var detail: DetailStart?
    @State private var auswahlModus = false
    @State private var auswahl: [String] = []
    @State private var auswahlStand = 0
    @State private var arbeitet = false
    @State private var frageLoeschen = false
    @State private var zeigeAlbumWahl = false
    @State private var fehler: String?

    /// Welches Foto geöffnet wurde und wo seine Kachel im Fenster liegt (für den Zoom-Übergang).
    struct DetailStart: Equatable {
        let id = UUID()
        let position: DetailPosition
        let rahmen: CGRect
    }

    private var filter: TimelineFilter { store?.filter ?? .alle }

    private static var startZoom: GridZoom {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    var body: some View {
        inhalt
            .background(LilithColor.hintergrund)
            .navigationTitle(auswahl.isEmpty ? titel : "\(auswahl.count) ausgewählt")
            .toolbar { werkzeuge }
            .overlay(alignment: .bottom) {
                if !auswahl.isEmpty && detail == nil {
                    aktionsleiste.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                GeometryReader { geo in
                    if let detail {
                        let flaeche = geo.frame(in: .global)
                        DetailView(quelle: quelle, store: store, start: detail.position,
                                   loeschen: kontext.client == nil || filter == .papierkorb ? nil : { await loescheEinzeln($0) }) { ende in
                            // Das Grid dorthin mitnehmen, wo man beim Blättern gelandet ist.
                            if ende.section != detail.position.section { sprung = SprungAnfrage(section: ende.section) }
                            self.detail = nil
                        }
                        .transition(.scale(scale: 0.15, anchor: UnitPoint(
                            x: (detail.rahmen.midX - flaeche.minX) / max(flaeche.width, 1),
                            y: (detail.rahmen.midY - flaeche.minY) / max(flaeche.height, 1))).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(duration: 0.32), value: detail)
            .animation(.spring(duration: 0.25), value: auswahl.isEmpty)
            #if os(iOS)
            .toolbarVisibility(detail == nil ? .automatic : .hidden, for: .tabBar, .navigationBar)
            #endif
            .task {
                if let store, store.zustand == .laedt { await store.laden() }
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "LilithSprung"), !quelle.sections.isEmpty {
                    try? await Task.sleep(for: .seconds(2))
                    sprung = SprungAnfrage(section: quelle.sections.count - 1)
                }
                #endif
            }
            .onChange(of: kontext.stand) { _, _ in
                // Eine andere Ansicht hat etwas geändert: hier neu laden.
                if kontext.letzteQuelle !== store { Task { await store?.laden() } }
            }
            .confirmationDialog(loeschFrage, isPresented: $frageLoeschen, titleVisibility: .visible) {
                Button(loeschtEndgueltig ? "Endgültig löschen" : "In den Papierkorb", role: .destructive) {
                    let endgueltig = loeschtEndgueltig
                    fuehreAus { try await $0.loesche(assetIds: $1, endgueltig: endgueltig) }
                }
            } message: {
                Text(loeschtEndgueltig ? "Das lässt sich nicht rückgängig machen."
                                       : "Du kannst sie im Papierkorb wiederherstellen.")
            }
            .sheet(isPresented: $zeigeAlbumWahl) {
                AlbumWahl(anzahl: auswahl.count) { ziel in
                    switch ziel {
                    case .vorhanden(let album): fuehreAus { try await $0.fuegeZuAlbum(albumId: album.id, assetIds: $1) }
                    case .neu(let name): fuehreAus { _ = try await $0.erstelleAlbum(name: name, assetIds: $1) }
                    }
                }
            }
            .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
                Button("OK") { fehler = nil }
            } message: { Text($0) }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var inhalt: some View {
        switch store?.zustand ?? .bereit {
        case .laedt:
            VStack(spacing: 16) {
                MondSymbol(phase: 0.5).frame(width: 48, height: 48)
                Text("Wird geladen …").foregroundStyle(LilithColor.textLeise)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .leer:
            let text = Self.leerText(filter)
            ContentUnavailableView {
                Label(text.titel, systemImage: text.symbol)
            } description: {
                Text(text.text)
            }
        case .fehler(let text):
            ContentUnavailableView {
                Label("Nicht geladen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Erneut versuchen") { Task { await store?.laden() } }
                    .buttonStyle(.borderedProminent)
            }
        case .bereit:
            TimelineGridView(quelle: quelle, zoom: $zoom, sprung: sprung,
                             auswahlModus: auswahlModus, auswahlStand: auswahlStand,
                             onAuswahl: { auswahl = $0 },
                             onTap: { section, index, rahmen in
                                 detail = DetailStart(position: DetailPosition(section: section, index: index), rahmen: rahmen)
                             },
                             onScroll: { scrollAnteil = $0 })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .trailing) {
                    Scrubber(quelle: quelle, anteil: scrollAnteil) { sprung = SprungAnfrage(section: $0) }
                        .padding(.vertical, 8)
                }
                .refreshable { await store?.laden() }
        }
    }

    static func leerText(_ filter: TimelineFilter) -> (titel: String, text: String, symbol: String) {
        switch filter {
        case .alle: ("Noch keine Fotos", "Sobald Fotos auf deinem Immich-Server sind, erscheinen sie hier.", "photo.on.rectangle.angled")
        case .favoriten: ("Noch keine Favoriten", "Tippe bei einem Foto auf das Herz, dann findest du es hier wieder.", "heart")
        case .archiv: ("Archiv ist leer", "Archivierte Fotos verschwinden aus der Bibliothek und liegen hier.", "archivebox")
        case .papierkorb: ("Papierkorb ist leer", "Gelöschte Fotos liegen hier, bis der Server sie endgültig entfernt.", "trash")
        case .suche: ("Nichts gefunden", "Versuch es mit anderen Worten, zum Beispiel einem Ort, einem Tier oder einer Farbe.", "magnifyingglass")
        case .album: ("Album ist leer", "Wähle in der Bibliothek Fotos aus und füge sie diesem Album hinzu.", "rectangle.stack")
        }
    }

    // MARK: - Werkzeuge

    @ToolbarContentBuilder
    private var werkzeuge: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            #if os(iOS)
            if kontext.client != nil, store?.zustand == .bereit {
                Button(auswahlModus ? "Fertig" : "Auswählen") {
                    if auswahlModus { beendeAuswahl() } else { auswahlModus = true }
                }
            }
            #endif
            Menu {
                Button("Größer (weniger Spalten)", systemImage: "plus.magnifyingglass") { zoom.groesser() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Kleiner (mehr Spalten)", systemImage: "minus.magnifyingglass") { zoom.kleiner() }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Zum neuesten Monat", systemImage: "arrow.up.to.line") { sprung = SprungAnfrage(section: 0) }
                Button("Zum ältesten Monat", systemImage: "arrow.down.to.line") {
                    sprung = SprungAnfrage(section: max(quelle.sections.count - 1, 0))
                }
                if let store {
                    Divider()
                    Button("Neu laden", systemImage: "arrow.clockwise") { Task { await store.laden() } }
                        .keyboardShortcut("r", modifiers: .command)
                }
            } label: {
                Label("Ansicht", systemImage: "slider.horizontal.3")
            }
            if let konto, !auswahlModus {
                Button(action: konto.oeffnen) {
                    Text(konto.buchstabe)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(LilithColor.nachtroseFill, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Konto und Server")
            }
        }
    }

    /// Leiste mit Aktionen für die ausgewählten Fotos.
    private var aktionsleiste: some View {
        HStack(spacing: 2) {
            if filter == .papierkorb {
                aktion("Wiederherstellen", "arrow.uturn.backward") { fuehreAus { try await $0.stelleWiederHer(assetIds: $1) } }
                aktion("Endgültig löschen", "trash.slash", rot: true) { frageLoeschen = true }
            } else {
                if filter == .favoriten {
                    aktion("Favorit entfernen", "heart.slash") { fuehreAus { try await $0.aendere(assetIds: $1, favorit: false) } }
                } else {
                    aktion("Favorit", "heart") { fuehreAus { try await $0.aendere(assetIds: $1, favorit: true) } }
                }
                if filter == .archiv {
                    aktion("Aus Archiv holen", "arrow.uturn.backward") { fuehreAus { try await $0.aendere(assetIds: $1, archiviert: false) } }
                } else {
                    aktion("Archivieren", "archivebox") { fuehreAus { try await $0.aendere(assetIds: $1, archiviert: true) } }
                }
                aktion("Zu Album", "rectangle.stack.badge.plus") { zeigeAlbumWahl = true }
                aktion("Löschen", "trash", rot: true) { frageLoeschen = true }
            }
            if arbeitet { ProgressView().padding(.horizontal, 10) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.bottom, 12)
        .disabled(arbeitet)
    }

    private func aktion(_ titel: String, _ symbol: String, rot: Bool = false, _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.body)
                Text(titel).font(.caption2)
            }
            .frame(minWidth: 62, minHeight: 44)
            .foregroundStyle(rot ? Color.red : LilithColor.text)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Aktionen

    private var loeschtEndgueltig: Bool { filter == .papierkorb || !kontext.papierkorbAktiv }

    private var loeschFrage: String {
        let n = auswahl.count
        let was = n == 1 ? "1 Objekt" : "\(n) Objekte"
        return loeschtEndgueltig ? "\(was) endgültig löschen?" : "\(was) in den Papierkorb legen?"
    }

    private func beendeAuswahl() {
        auswahlModus = false
        auswahl = []
        auswahlStand += 1
    }

    /// Führt eine Aktion für die ausgewählten Fotos aus und lädt danach neu.
    private func fuehreAus(_ aktion: @escaping (ImmichClient, [String]) async throws -> Void) {
        guard let client = kontext.client, !auswahl.isEmpty, !arbeitet else { return }
        let ids = auswahl
        arbeitet = true
        Task {
            defer { arbeitet = false }
            do {
                try await aktion(client, ids)
                beendeAuswahl()
                await store?.laden()
                kontext.melde(von: store)
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
        }
    }

    /// Löschen aus der Detailansicht. Gibt zurück, ob es geklappt hat.
    private func loescheEinzeln(_ id: String) async -> Bool {
        guard let client = kontext.client else { return false }
        do {
            try await client.loesche(assetIds: [id], endgueltig: !kontext.papierkorbAktiv)
            await store?.laden()
            kontext.melde(von: store)
            return true
        } catch {
            fehler = error.localizedDescription
            kontext.pruefe(error)
            return false
        }
    }
}
