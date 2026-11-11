import SwiftUI
import DesignSystem
import TimelineGrid

/// Schritt 3: Prototyp mit 100.000 erfundenen Fotos, um die Grid-Technik zu wählen.
/// Wird in Schritt 4 durch die echte Timeline ersetzt.
struct GridPrototypView: View {
    enum Technik: String, CaseIterable, Identifiable {
        case nativ = "Nativ"
        case swiftUI = "SwiftUI"
        var id: Self { self }
    }

    @Binding var zeigeKonto: Bool
    let kontoBuchstabe: String

    @State private var model: GridModel?
    @State private var aufbauMs = 0.0
    @State private var technik: Technik = .nativ
    @State private var zoom: GridZoom = Self.startZoom
    @State private var monitor = PerformanceMonitor()
    @State private var zeigeMessung = true
    @State private var sprung: SprungAnfrage?
    @State private var scrollAnteil = 0.0

    private func springe(ansEnde: Bool) {
        guard let model else { return }
        monitor.zuruecksetzen()
        sprung = SprungAnfrage(section: ansEnde ? model.sections.count - 1 : 0)
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
            Group {
                if let model {
                    switch technik {
                    case .nativ:
                        TimelineGridView(model: model, zoom: $zoom, sprung: sprung) { scrollAnteil = $0 }
                            .ignoresSafeArea(edges: .bottom)
                    case .swiftUI:
                        SwiftUITimelineGrid(model: model, zoom: zoom, sprung: sprung) { scrollAnteil = $0 }
                    }
                } else {
                    ProgressView("Erzeuge 100.000 Testfotos …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(LilithColor.hintergrund)
            .overlay(alignment: .bottomTrailing) {
                if zeigeMessung { messung.padding(.trailing, 12).padding(.bottom, 96) }
            }
            .navigationTitle("Bibliothek")
            .toolbar { werkzeuge }
        }
        .task {
            let start = ContinuousClock.now
            let erzeugt = await Task.detached(priority: .userInitiated) { GridModel.beispiel() }.value
            let dauer = (ContinuousClock.now - start).components
            aufbauMs = Double(dauer.seconds) * 1000 + Double(dauer.attoseconds) / 1e15
            model = erzeugt
            monitor.start()
            #if DEBUG
            // Zum Messen: „-LilithSprung YES“ springt nach 2 Sekunden ans Ende.
            if UserDefaults.standard.bool(forKey: "LilithSprung") {
                try? await Task.sleep(for: .seconds(2))
                springe(ansEnde: true)
                try? await Task.sleep(for: .seconds(3))
                print("LILITH-MESSUNG technik=\(technik.rawValue) spalten=\(zoom.spalten) fps=\(monitor.fps) "
                      + "ruckler=\(monitor.ruckler) maxBildMs=\(Int(monitor.laengstesBildMs)) "
                      + "speicherMB=\(Int(monitor.speicherMB)) datenMs=\(Int(aufbauMs)) "
                      + "position=\(Int(scrollAnteil * 100))%")
                fflush(stdout)
            }
            #endif
        }
        .onDisappear { monitor.stop() }
        .onChange(of: technik) { _, _ in monitor.zuruecksetzen() }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "LilithGrid") == "swiftui" { technik = .swiftUI }
        }
        #endif
    }

    private var messung: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PROTOTYP · \(technik.rawValue) · \(zoom.spalten) Spalten").font(.caption2.weight(.bold))
            Text("\(monitor.fps) fps · \(monitor.ruckler) Ruckler · max \(Int(monitor.laengstesBildMs)) ms")
            Text("\(Int(monitor.speicherMB)) MB · Position \(Int(scrollAnteil * 100)) %")
        }
        .font(.caption.monospacedDigit())
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .onTapGesture { monitor.zuruecksetzen() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Messwerte")
    }

    @ToolbarContentBuilder
    private var werkzeuge: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Technik", selection: $technik) {
                    ForEach(Technik.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Button("Zum ältesten Monat springen", systemImage: "arrow.down.to.line") { springe(ansEnde: true) }
                Button("Zum neuesten Monat springen", systemImage: "arrow.up.to.line") { springe(ansEnde: false) }
                Divider()
                Button("Größer (weniger Spalten)", systemImage: "plus.magnifyingglass") { zoom.groesser() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Kleiner (mehr Spalten)", systemImage: "minus.magnifyingglass") { zoom.kleiner() }
                    .keyboardShortcut("-", modifiers: .command)
                Toggle("Messwerte anzeigen", isOn: $zeigeMessung)
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
