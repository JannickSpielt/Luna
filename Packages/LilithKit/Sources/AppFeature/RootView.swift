import SwiftUI
import DesignSystem

/// Die Hauptbereiche der App.
public enum Bereich: Hashable, Sendable {
    case bibliothek
    case erinnerungen
    case alben
    case suche
}

/// Wurzel der App: Tab Bar auf dem iPhone, Sidebar auf iPad und Mac.
public struct RootView: View {
    @State private var auswahl: Bereich = .bibliothek

    /// „Erinnerungen“ kommt erst in Version 1.x.
    private let zeigeErinnerungen = false

    public init() {}

    public var body: some View {
        TabView(selection: $auswahl) {
            Tab("Bibliothek", systemImage: "square.grid.2x2", value: Bereich.bibliothek) {
                Platzhalter(titel: "Bibliothek", symbol: "square.grid.2x2",
                            text: "Hier erscheint bald deine Timeline.")
            }
            if zeigeErinnerungen {
                Tab("Erinnerungen", systemImage: "moon", value: Bereich.erinnerungen) {
                    Platzhalter(titel: "Erinnerungen", symbol: "moon",
                                text: "Rückblicke kommen in einer späteren Version.")
                }
            }
            Tab("Alben", systemImage: "rectangle.stack", value: Bereich.alben) {
                Platzhalter(titel: "Alben", symbol: "rectangle.stack",
                            text: "Hier erscheinen bald deine Alben.")
            }
            Tab(value: Bereich.suche, role: .search) {
                Platzhalter(titel: "Suche", symbol: "magnifyingglass",
                            text: "Smart Search kommt bald.")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(LilithColor.nachtrose)
    }
}

/// Vorläufiger Inhalt, bis die echten Bereiche gebaut sind.
struct Platzhalter: View {
    let titel: String
    let symbol: String
    let text: String

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
        }
    }
}

#Preview {
    RootView()
}
