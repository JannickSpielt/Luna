import SwiftUI
import DesignSystem
import Networking
import TimelineGrid
import Backup
import Persistence

/// Die Hauptbereiche der App.
public enum Bereich: Hashable, Sendable {
    case bibliothek
    case erinnerungen
    case alben
    case suche
}

/// Wurzel der App: zuerst Anmeldung, danach Tab Bar (iPhone) bzw. Sidebar (iPad, Mac).
public struct RootView: View {
    @State private var session = SessionStore()

    public init() {}

    /// Einmal beim App-Start aufrufen (Bilder-Cache usw.).
    @MainActor
    public static func einrichten() {
        BilderCache.einrichten()
        GeraeteUmgebung.starte()
        BackupZentrale.registriereHintergrund()
    }

    public var body: some View {
        Group {
            switch session.phase {
            case .startet:
                MondSymbol(phase: 0.6)
                    .frame(width: 64, height: 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LilithColor.hintergrund.ignoresSafeArea())
            case .abgemeldet:
                OnboardingView()
            case .angemeldet(let account):
                HauptView(account: account)
            }
        }
        .environment(session)
        .lilithSperre()
        .tint(LilithColor.nachtrose)
        .animation(.smooth, value: session.phase)
        .task { await session.start() }
    }
}

/// Tab Bar auf dem iPhone, Sidebar auf iPad und Mac.
struct HauptView: View {
    let account: Account
    @Environment(SessionStore.self) private var session
    @State private var auswahl: Bereich = .bibliothek
    @State private var zeigeKonto = false
    /// Einmal pro Anmeldung, damit Daten nicht doppelt geladen werden.
    @State private var timeline: TimelineStore?
    @State private var demo: BeispielQuelle?
    @State private var kontext: BibliothekKontext?
    @Environment(\.scenePhase) private var szene

    private var quelle: TimelineQuelle? { timeline ?? demo }

    /// „Erinnerungen“ kommt erst in Version 1.x.
    private let zeigeErinnerungen = false

    var body: some View {
        if let kontext {
            tabs
                .environment(kontext)
                .overlay { DetailEbene(kontext: kontext) }
                .onChange(of: szene) { _, neu in
                    switch neu {
                    case .active:
                        kontext.backup?.aktualisiereZugriff()
                        kontext.backup?.starte()
                    case .background:
                        // Uploads an iOS übergeben (laufen ohne Lilith weiter) und die nächsten Läufe anmelden.
                        BackupZentrale.shared.inDenHintergrund()
                    default:
                        break
                    }
                }
        } else {
            Color.clear.onAppear(perform: richteEin)
        }
    }

    private var tabs: some View {
        TabView(selection: $auswahl) {
            Tab("Bibliothek", systemImage: "square.grid.2x2", value: Bereich.bibliothek) {
                if let quelle {
                    BibliothekView(quelle: quelle, store: timeline, zeigeKonto: $zeigeKonto,
                                   kontoBuchstabe: String(account.user.name.prefix(1)).uppercased())
                }
            }
            if zeigeErinnerungen {
                Tab("Erinnerungen", systemImage: "moon", value: Bereich.erinnerungen) {
                    Platzhalter(titel: "Erinnerungen", symbol: "moon",
                                text: "Rückblicke kommen in einer späteren Version.",
                                account: account, zeigeKonto: $zeigeKonto)
                }
            }
            Tab("Alben", systemImage: "rectangle.stack", value: Bereich.alben) {
                AlbenView()
            }
            Tab(value: Bereich.suche, role: .search) {
                SucheView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background {
            // Unsichtbare Knöpfe nur für Tastenkürzel (Mac, iPad mit Tastatur).
            Group {
                Button("Bibliothek") { auswahl = .bibliothek }.keyboardShortcut("1", modifiers: .command)
                Button("Alben") { auswahl = .alben }.keyboardShortcut("2", modifiers: .command)
                Button("Suche") { auswahl = .suche }.keyboardShortcut("3", modifiers: .command)
                Button("Suchen") { auswahl = .suche }.keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $zeigeKonto) {
            KontoView(account: account, backup: kontext?.backup, client: session.client)
        }
    }

    private func richteEin() {
        guard kontext == nil else { return }
        let sitzung = session
        // Upload-Warteschlange mit eigener Datenbank. Schlägt das Öffnen fehl, gibt es eben keinen Upload.
        var uploads: UploadWarteschlange?
        var backup: BackupDienst?
        if let client = session.client {
            // Dieselben wie für Läufe im Hintergrund.
            (uploads, backup) = BackupZentrale.shared.einrichten(account: account, client: client)
        }
        #if DEBUG && os(iOS)
        if UserDefaults.standard.bool(forKey: "LilithBackupVorschau") {
            backup = BackupDienst.vorschau(mediathek: FotoMediathek())
        }
        #endif
        let neu = BibliothekKontext(client: session.client, papierkorbAktiv: account.server.capabilities.trash,
                                    smartSearch: account.server.capabilities.smartSearch, uploads: uploads, backup: backup,
                                    nutzerId: account.user.id)
        backup?.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
        neu.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
        uploads?.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
        // Nach dem Hochladen alle Ansichten neu laden, damit die neuen Fotos erscheinen.
        uploads?.onDurchgangFertig = { [weak neu] in neu?.melde(von: nil) }
        backup?.starte()
        if let client = session.client {
            let store = TimelineStore(client: client)
            store.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
            if let backup {
                // Nicht gesicherte Fotos vom Gerät in der Bibliothek zeigen (abschaltbar im Ansicht-Menü).
                store.lokaleFotos = { [weak backup] in
                    guard let backup, UserDefaults.standard.object(forKey: NichtGesicherte.schluessel) as? Bool ?? true else { return [] }
                    return backup.nichtGesicherte().map(LokalerEintrag.init)
                }
                store.lokalesBildLader = { [weak backup] id, pixel in await backup?.vorschau(id, kante: pixel) }
                backup.onAenderung = { [weak neu] in neu?.melde(von: nil) }
            }
            #if DEBUG && os(iOS)
            // Nur zum Prüfen der Anzeige: Fotos der Mediathek als „nicht gesichert“ zeigen, ohne etwas hochzuladen.
            if UserDefaults.standard.bool(forKey: "LilithLokalVorschau") {
                let mediathek = FotoMediathek()
                store.lokalesBildLader = { id, pixel in await mediathek.vorschau(id, kante: pixel) }
                Task { [weak store] in
                    let medien = (try? await mediathek.alleMedien()) ?? []
                    let eintraege = medien.enumerated().map { i, m in
                        LokalerEintrag(item: GridItem(id: GridItem.lokalPraefix + m.id, farbe: 0x8A8A8E, art: m.istVideo ? .video : .foto,
                                                      favorit: false, dauer: 0, lokal: [GridLokal.nurHier, .laedtHoch, .fehler][i % 3]),
                                       erstellt: Date.now.addingTimeInterval(-Double(i) * 3600))
                    }
                    store?.lokaleFotos = { eintraege }
                    await store?.laden()
                }
            }
            #endif
            timeline = store
        } else {
            demo = BeispielQuelle()
        }
        kontext = neu
    }
}

/// Vorläufiger Inhalt, bis die echten Bereiche gebaut sind.
struct Platzhalter: View {
    let titel: String
    let symbol: String
    let text: String
    let account: Account
    @Binding var zeigeKonto: Bool

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(titel, systemImage: symbol)
            } description: {
                Text(text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LilithColor.hintergrund)
            .navigationTitle(titel)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        zeigeKonto = true
                    } label: {
                        Text(String(account.user.name.prefix(1)).uppercased())
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
    }
}

/// Die Detailansicht über dem ganzen Fenster, mit Zoom aus der angetippten Kachel.
struct DetailEbene: View {
    let kontext: BibliothekKontext
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    var body: some View {
        // Außen: Abstände zu Notch und Home-Leiste messen. Innen: von Anfang an den ganzen Bildschirm nutzen.
        // Sonst wächst die Ansicht erst nach dem Zoom auf volle Größe und das Foto springt (es ist zentriert).
        GeometryReader { aussen in
            let rand = aussen.safeAreaInsets
            GeometryReader { geo in
                if let d = kontext.detail {
                    let flaeche = geo.frame(in: .global)
                    DetailView(quelle: d.quelle, store: d.store, start: d.start, loeschen: d.loeschen, schliessen: d.schliessen)
                        .safeAreaPadding(rand)
                        .environment(kontext)
                        .transition(wenigBewegung ? .opacity : .scale(scale: 0.15, anchor: UnitPoint(
                            x: (d.rahmen.midX - flaeche.minX) / max(flaeche.width, 1),
                            y: (d.rahmen.midY - flaeche.minY) / max(flaeche.height, 1))).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
        }
        .animation(wenigBewegung ? .easeInOut(duration: 0.2) : .spring(duration: 0.32), value: kontext.detail)
    }
}

/// Einstellung „Nicht gesicherte zeigen“.
enum NichtGesicherte {
    static let schluessel = "lilith.zeigeNichtGesicherte"
}

extension LokalerEintrag {
    /// Eintrag fürs Grid aus dem Stand in der Datenbank.
    init(_ foto: LokalesFoto) {
        let lokal: GridLokal = switch foto.zustand {
        case .eingereiht: .laedtHoch
        case .fehler: .fehler
        default: .nurHier
        }
        self.init(item: GridItem(id: GridItem.lokalPraefix + foto.lokaleId, farbe: 0x8A8A8E,
                                 art: foto.istVideo ? .video : .foto, favorit: false, dauer: 0, lokal: lokal),
                  erstellt: foto.erstellt)
    }
}
