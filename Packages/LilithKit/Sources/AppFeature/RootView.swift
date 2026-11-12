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
                    // Backup nur bei geöffneter App (Hintergrund kommt in Etappe 3).
                    switch neu {
                    case .active:
                        kontext.backup?.aktualisiereZugriff()
                        kontext.backup?.starte()
                    case .background:
                        kontext.backup?.halteAn()
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
            KontoView(account: account, backup: kontext?.backup)
        }
    }

    private func richteEin() {
        guard kontext == nil else { return }
        let sitzung = session
        // Upload-Warteschlange mit eigener Datenbank. Schlägt das Öffnen fehl, gibt es eben keinen Upload.
        var uploads: UploadWarteschlange?
        var backup: BackupDienst?
        if let client = session.client, let db = try? Datenbank.standard() {
            let schlange = UploadWarteschlange(client: client, db: db, konto: account.id)
            uploads = schlange
            #if os(iOS)
            // Auf dem Mac nur per Hand (Entscheidung im Backup-Plan).
            backup = BackupDienst(client: client, db: db, konto: account.id, mediathek: FotoMediathek(), uploads: schlange)
            #endif
        }
        #if DEBUG && os(iOS)
        if UserDefaults.standard.bool(forKey: "LilithBackupVorschau") {
            backup = BackupDienst.vorschau(mediathek: FotoMediathek())
        }
        #endif
        let neu = BibliothekKontext(client: session.client, papierkorbAktiv: account.server.capabilities.trash,
                                    smartSearch: account.server.capabilities.smartSearch, uploads: uploads, backup: backup)
        backup?.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
        neu.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
        uploads?.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
        // Nach dem Hochladen alle Ansichten neu laden, damit die neuen Fotos erscheinen.
        uploads?.onDurchgangFertig = { [weak neu] in neu?.melde(von: nil) }
        uploads?.start()
        backup?.starte()
        if let client = session.client {
            let store = TimelineStore(client: client)
            store.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
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
        GeometryReader { geo in
            if let d = kontext.detail {
                let flaeche = geo.frame(in: .global)
                DetailView(quelle: d.quelle, store: d.store, start: d.start, loeschen: d.loeschen, schliessen: d.schliessen)
                    .environment(kontext)
                    .transition(wenigBewegung ? .opacity : .scale(scale: 0.15, anchor: UnitPoint(
                        x: (d.rahmen.midX - flaeche.minX) / max(flaeche.width, 1),
                        y: (d.rahmen.midY - flaeche.minY) / max(flaeche.height, 1))).combined(with: .opacity))
            }
        }
        .animation(wenigBewegung ? .easeInOut(duration: 0.2) : .spring(duration: 0.32), value: kontext.detail)
    }
}
