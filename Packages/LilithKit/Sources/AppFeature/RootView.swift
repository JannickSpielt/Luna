import SwiftUI
import DesignSystem
import Networking
import TimelineGrid

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

    private var quelle: TimelineQuelle? { timeline ?? demo }

    /// „Erinnerungen“ kommt erst in Version 1.x.
    private let zeigeErinnerungen = false

    var body: some View {
        if let kontext {
            tabs.environment(kontext)
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
        .sheet(isPresented: $zeigeKonto) {
            KontoView(account: account)
        }
    }

    private func richteEin() {
        guard kontext == nil else { return }
        let sitzung = session
        let neu = BibliothekKontext(client: session.client, papierkorbAktiv: account.server.capabilities.trash,
                                    smartSearch: account.server.capabilities.smartSearch)
        neu.onSitzungAbgelaufen = { [weak sitzung] in sitzung?.sitzungAbgelaufen() }
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
