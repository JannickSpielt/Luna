import SwiftUI
import DesignSystem
import TimelineGrid

/// Die Bibliothek: alle Fotos und Videos als Timeline mit Scrubber.
struct BibliothekView: View {
    let quelle: TimelineQuelle
    /// Nur bei echter Verbindung gesetzt (nicht im Demo-Modus).
    let store: TimelineStore?
    @Binding var zeigeKonto: Bool
    let kontoBuchstabe: String

    @State private var zoom: GridZoom = Self.startZoom
    @State private var sprung: SprungAnfrage?
    @State private var scrollAnteil = 0.0
    @State private var detail: DetailStart?

    /// Welches Foto geöffnet wurde und wo seine Kachel im Fenster liegt (für den Zoom-Übergang).
    struct DetailStart: Equatable {
        let id = UUID()
        let position: DetailPosition
        let rahmen: CGRect
    }

    private static var startZoom: GridZoom {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    var body: some View {
        NavigationStack {
            inhalt
                .background(LilithColor.hintergrund)
                .navigationTitle("Bibliothek")
                .toolbar { werkzeuge }
        }
        .overlay {
            GeometryReader { geo in
                if let detail {
                    let flaeche = geo.frame(in: .global)
                    DetailView(quelle: quelle, store: store, start: detail.position) { ende in
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
        #if os(iOS)
        .toolbarVisibility(detail == nil ? .automatic : .hidden, for: .tabBar)
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
    }

    @ViewBuilder
    private var inhalt: some View {
        switch store?.zustand ?? .bereit {
        case .laedt:
            VStack(spacing: 16) {
                MondSymbol(phase: 0.5).frame(width: 48, height: 48)
                Text("Deine Bibliothek wird geladen …").foregroundStyle(LilithColor.textLeise)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .leer:
            ContentUnavailableView {
                Label("Noch keine Fotos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Sobald Fotos auf deinem Immich-Server sind, erscheinen sie hier.")
            }
        case .fehler(let text):
            ContentUnavailableView {
                Label("Bibliothek nicht geladen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Erneut versuchen") { Task { await store?.laden() } }
                    .buttonStyle(.borderedProminent)
            }
        case .bereit:
            TimelineGridView(quelle: quelle, zoom: $zoom, sprung: sprung, onTap: { section, index, rahmen in
                detail = DetailStart(position: DetailPosition(section: section, index: index), rahmen: rahmen)
            }, onScroll: { scrollAnteil = $0 })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .trailing) {
                    Scrubber(quelle: quelle, anteil: scrollAnteil) { sprung = SprungAnfrage(section: $0) }
                        .padding(.vertical, 8)
                }
                .refreshable { await store?.laden() }
        }
    }

    @ToolbarContentBuilder
    private var werkzeuge: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
            Button {
                zeigeKonto = true
            } label: {
                Text(kontoBuchstabe)
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
