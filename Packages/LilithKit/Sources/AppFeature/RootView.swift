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
    /// Noch im allerersten Startbildschirm.
    @State private var warStart = true
    @Environment(\.scenePhase) private var szenePhase

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
                StartBildschirm()
            case .abgemeldet:
                OnboardingView()
            case .angemeldet(let account):
                HauptView(account: account)
            }
        }
        .environment(session)
        .lilithSperre()
        .tint(LilithColor.nachtrose)
        .preferredColorScheme(DesignZustand.shared.design.schema)
        // Kommt die App wieder nach vorn, gilt vielleicht ein anderes Design (Beginn oder Ende der Weihnachtszeit).
        .onChange(of: szenePhase) { _, neu in if neu == .active { DesignZustand.shared.pruefe() } }
        // Vom Startbildschirm aus ohne Überblenden: Zwei halb durchsichtige Ebenen ergäben ein graues Bild.
        .animation(warStart ? nil : .smooth, value: session.phase)
        .onChange(of: session.phase) { _, _ in warStart = false }
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
    @State private var zeigeVollmond = false
    /// Der Ladebildschirm bleibt, bis die Bibliothek das erste Mal geladen ist.
    @State private var startVorbei = false
    /// 0 = Mond, 1 = App ganz offen.
    @State private var startOeffnung = 0.0
    @State private var startVollmond = false
    @State private var startGeladen = false
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    private var quelle: TimelineQuelle? { timeline ?? demo }

    /// „Erinnerungen“ kommt erst in Version 1.x.
    private let zeigeErinnerungen = false

    var body: some View {
        inhalt
            // Unter allem der Nachthimmel, solange gestartet wird: kein graues Bild beim Wechsel.
            .background { if !startVorbei { StartBildschirm.nacht.ignoresSafeArea() } }
    }

    @ViewBuilder
    private var inhalt: some View {
        if let kontext {
            tabs
                .environment(kontext)
                #if os(iOS)
                // Weihnachtszeit: Schnee über der App, der auf der Tab-Leiste liegen bleibt (unter der Fotoansicht).
                .overlay { if Weihnachten.aktiv { SchneeWelt(laeuft: kontext.detail == nil && startVorbei) } }
                #endif
                .overlay { DetailEbene(kontext: kontext) }
                // Die App kommt aus dem Mond leicht auf einen zu.
                .scaleEffect(1 + 0.08 * (1 - startOeffnung))
                .overlay {
                    if !startVorbei {
                        // Kein Überblenden: Er liegt nahtlos über dem Startbildschirm davor.
                        StartBildschirm(vollmond: startVollmond, geladen: startGeladen, oeffnung: startOeffnung).transition(.identity)
                    }
                }
                .task {
                    // Höchstens 5 Sekunden: Ist der Server langsam, zeigt die Bibliothek selbst an, dass sie lädt.
                    let start = Date.now
                    while timeline?.zustand == .laedt, Date.now.timeIntervalSince(start) < 5 {
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                    if wenigBewegung {
                        startGeladen = true; startOeffnung = 1
                        withAnimation(.easeOut(duration: 0.45)) { startVorbei = true }
                    } else {
                        // 1. Unten erscheint „von Jannick Stahn“: alles geladen.
                        withAnimation(.easeOut(duration: 0.35)) { startGeladen = true }
                        try? await Task.sleep(for: .milliseconds(550))
                        // 2. Der Mond wird voll.
                        withAnimation(.easeInOut(duration: 0.4)) { startVollmond = true }
                        try? await Task.sleep(for: .milliseconds(380))
                        // 3. Hinein: erst gemächlich, dann immer schneller („pschuh“).
                        withAnimation(.timingCurve(0.6, 0, 0.85, 0.35, duration: 0.55)) { startOeffnung = 1 }
                        try? await Task.sleep(for: .milliseconds(570))
                        startVorbei = true
                    }
                }
                .overlay {
                    if zeigeVollmond {
                        VollmondMoment { withAnimation(.easeIn(duration: 0.4)) { zeigeVollmond = false } }
                            .transition(.opacity)
                    }
                }
                #if DEBUG
                .onAppear {
                    // Zum Ansehen: „-LilithVollmond YES“ zeigt den Moment sofort.
                    if UserDefaults.standard.bool(forKey: "LilithVollmond") { zeigeVollmond = true }
                    #if os(iOS)
                    if UserDefaults.standard.bool(forKey: "LilithLiveVorschau") { UploadLiveSteuerung.shared.zeigeVorschau() }
                    #endif
                }
                #endif
                // In einer eigenen kleinen Ansicht: Der Upload-Fortschritt tickt oft und soll nicht
                // jedes Mal die ganze App samt Leisten und Menüs neu berechnen.
                .background {
                    FortschrittBeobachter(kontext: kontext) {
                        withAnimation(.easeOut(duration: 0.4)) { zeigeVollmond = true }
                    }
                }
                // Vom Widget: das angetippte Foto öffnen (inmitten seines Tages, zum Weiterblättern).
                .onOpenURL { url in oeffneLink(url) }
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
            // Derselbe Nachthimmel wie davor, damit beim Wechsel nichts grau aufblitzt.
            StartBildschirm().onAppear(perform: richteEin)
        }
    }

    private var tabs: some View {
        TabView(selection: $auswahl) {
            // (Tab-Wechsel wirbelt in der Weihnachtszeit den Schnee auf, siehe .onChange unten.)
            Tab("Fotos", systemImage: "photo.on.rectangle", value: Bereich.bibliothek) {
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
            Tab("Sammlungen", systemImage: "rectangle.stack", value: Bereich.alben) {
                AlbenView(konto: (String(account.user.name.prefix(1)).uppercased(), { zeigeKonto = true }))
            }
            Tab("Suchen", systemImage: "magnifyingglass", value: Bereich.suche, role: .search) {
                SucheView()
            }
        }
        .modifier(TabStil())
        #if os(iOS)
        .onChange(of: auswahl) { _, _ in SchneeImpuls.melde(900) }
        #endif
        .background {
            // Unsichtbare Knöpfe nur für Tastenkürzel (Mac, iPad mit Tastatur).
            Group {
                Button("Fotos") { auswahl = .bibliothek }.keyboardShortcut("1", modifiers: .command)
                Button("Sammlungen") { auswahl = .alben }.keyboardShortcut("2", modifiers: .command)
                Button("Suche") { auswahl = .suche }.keyboardShortcut("3", modifiers: .command)
                Button("Suchen") { auswahl = .suche }.keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $zeigeKonto) {
            KontoView(account: account, backup: kontext?.backup, uploads: kontext?.uploads, client: session.client)
        }
    }

    private func oeffneLink(_ url: URL) {
        guard let (id, aufgenommen) = FotoLink.lies(url) else { return }
        auswahl = .bibliothek
        Task {
            // Beim Kaltstart kurz warten, bis die Anmeldung steht.
            var versuche = 0
            while (kontext?.client == nil) && versuche < 50 {
                try? await Task.sleep(for: .milliseconds(100)); versuche += 1
            }
            guard let kontext, let client = kontext.client else { return }
            let tag = TimelineStore(client: client, filter: .tag(aufgenommen))
            await tag.laden()
            var start = DetailPosition(section: 0, index: 0)
            suche: for s in tag.sections.indices {
                for i in 0..<tag.sections[s].anzahl where tag.item(section: s, index: i)?.id == id {
                    start = DetailPosition(section: s, index: i)
                    break suche
                }
            }
            guard !tag.sections.isEmpty else { return }
            kontext.detail = DetailAnzeige(quelle: tag, store: tag, start: start, rahmen: .zero, loeschen: nil,
                                           schliessen: { [weak kontext] _ in kontext?.detail = nil })
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
        uploads?.onDurchgangFertig = { [weak neu] in neu?.meldeGebuendelt() }
        backup?.starte()
        if let client = session.client {
            let store = TimelineStore(client: client)
            store.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
            if let backup {
                // Nicht gesicherte Fotos vom Gerät in der Bibliothek zeigen (abschaltbar im Ansicht-Menü).
                store.lokaleFotos = { [weak backup] in
                    guard let backup, UserDefaults.standard.object(forKey: NichtGesicherte.schluessel) as? Bool ?? true else { return [] }
                    return await backup.nichtGesicherteImHintergrund().map(LokalerEintrag.init)
                }
                store.lokalesBildLader = { [weak backup] id, pixel in await backup?.vorschau(id, kante: pixel) }
                backup.onAenderung = { [weak neu] in neu?.meldeGebuendelt() }
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

    var body: some View {
        // Außen: Abstände zu Notch und Home-Leiste messen. Innen: von Anfang an den ganzen Bildschirm nutzen.
        GeometryReader { aussen in
            let rand = aussen.safeAreaInsets
            ZStack {
                if let d = kontext.detail {
                    // Erst sofort ein schwarzer Grund mit Ladeanzeige, dann das Foto. Kein Zoom aus der Kachel mehr:
                    // Der blieb auf manchen Geräten auf halbem Weg stehen.
                    DetailView(quelle: d.quelle, store: d.store, start: d.start, loeschen: d.loeschen, schliessen: d.schliessen)
                        .safeAreaPadding(rand)
                        .environment(kontext)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .animation(.easeOut(duration: 0.18), value: kontext.detail)
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

/// iPhone: normale Tab-Leiste, damit die Suche wie in Apples Fotos-App als eigener runder Knopf rechts steht.
/// iPad und Mac: Seitenleiste.
private struct TabStil: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            if #available(iOS 26, *) {
                // Damit steht die Suche wie in Apples Fotos-App als eigener runder Knopf rechts.
                content.tabViewStyle(.automatic).tabViewSearchActivation(.searchTabSelection)
            } else {
                content.tabViewStyle(.automatic)
            }
        } else {
            content.tabViewStyle(.sidebarAdaptable)
        }
        #else
        content.tabViewStyle(.sidebarAdaptable)
        #endif
    }
}

/// Beobachtet Upload-Fortschritt und Backup-Stand, ohne dass `HauptView` davon abhängt.
private struct FortschrittBeobachter: View {
    let kontext: BibliothekKontext
    let vollmond: () -> Void

    var body: some View {
        Color.clear
            #if os(iOS)
            .onChange(of: kontext.uploads?.stand) { _, neu in
                if let neu { UploadLiveSteuerung.shared.aktualisiere(neu) }
            }
            #endif
            .onChange(of: kontext.backup?.allesGesichert ?? false) { _, fertig in
                // Nur einmal: nach dem ersten kompletten Backup.
                guard fertig, let backup = kontext.backup, !backup.vollmondGezeigt else { return }
                backup.vollmondGezeigt = true
                vollmond()
            }
            .accessibilityHidden(true)
    }
}
