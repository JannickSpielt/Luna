import Foundation
import Observation
import Networking
import TimelineGrid

/// Lädt die Timeline vom Immich-Server: zuerst alle Monate mit Anzahl,
/// dann den Inhalt eines Monats erst, wenn das Grid ihn braucht.
@MainActor
@Observable
final class TimelineStore: TimelineQuelle {
    enum Zustand: Equatable {
        case laedt
        case bereit
        case leer
        case fehler(String)
    }

    private(set) var zustand: Zustand = .laedt
    private(set) var gesamt = 0

    @ObservationIgnored private(set) var sections: [GridSection] = []
    @ObservationIgnored var onMonatGeladen: ((Int, Bool) -> Void)?
    @ObservationIgnored private var monate: [TimelineMonat] = []
    @ObservationIgnored private var inhalte: [Int: [GridItem]] = [:]
    @ObservationIgnored private var laufend: Set<Int> = []
    @ObservationIgnored private let client: ImmichClient
    /// Wird aufgerufen, wenn der Server die Anmeldung ablehnt.
    @ObservationIgnored var onSitzungAbgelaufen: (() -> Void)?

    init(client: ImmichClient) {
        self.client = client
    }

    func laden() async {
        if sections.isEmpty { zustand = .laedt }
        do {
            let geladen = try await client.timelineMonate().filter { $0.anzahl > 0 }
            monate = geladen
            inhalte = [:]
            laufend = []
            sections = geladen.map { monat in
                GridSection(id: monat.schluessel, titel: Self.titel(monat),
                            untertitel: "\(monat.anzahl.formatted()) Objekte", anzahl: monat.anzahl)
            }
            gesamt = geladen.reduce(0) { $0 + $1.anzahl }
            zustand = geladen.isEmpty ? .leer : .bereit
        } catch ImmichError.sitzungAbgelaufen {
            onSitzungAbgelaufen?()
        } catch {
            zustand = .fehler(error.localizedDescription)
        }
    }

    // MARK: - TimelineQuelle

    func item(section: Int, index: Int) -> GridItem? {
        guard let liste = inhalte[section], index < liste.count else { return nil }
        return liste[index]
    }

    func ladeMonat(_ section: Int) {
        guard section < monate.count, inhalte[section] == nil, !laufend.contains(section) else { return }
        laufend.insert(section)
        let monat = monate[section]
        Task {
            defer { laufend.remove(section) }
            do {
                let assets = try await client.timelineInhalt(monat)
                // Die Monate könnten inzwischen neu geladen worden sein.
                guard section < monate.count, monate[section] == monat else { return }
                inhalte[section] = assets.map(Self.gridItem)
                let alteAnzahl = sections[section].anzahl
                sections[section].anzahl = assets.count
                sections[section].untertitel = Self.untertitel(assets)
                onMonatGeladen?(section, assets.count != alteAnzahl)
            } catch ImmichError.sitzungAbgelaufen {
                onSitzungAbgelaufen?()
            } catch {
                // Kein Absturz und keine Fehlermeldung pro Monat: Beim nächsten Anzeigen wird es erneut versucht.
            }
        }
    }

    func bildAnfragen(fuer item: GridItem, pixel: CGFloat) -> [URLRequest] {
        // Immichs „thumbnail“ hat ca. 250 px und kommt schnell. Für große Kacheln danach die schärfere Vorschau.
        let klein = client.vorschauAnfrage(assetId: item.id, groesse: .thumbnail)
        return pixel > 320 ? [klein, client.vorschauAnfrage(assetId: item.id, groesse: .preview)] : [klein]
    }

    // MARK: - Umwandlung

    static func gridItem(_ asset: TimelineAsset) -> GridItem {
        let art: GridItemKind = !asset.istBild ? .video : (asset.livePhotoVideoId != nil ? .livePhoto : .foto)
        let farbe = asset.thumbhash.flatMap(Thumbhash.durchschnittsfarbe)
            ?? GridPalette.farben[asset.id.utf8.reduce(0) { $0 &+ Int($1) } % GridPalette.farben.count]
        return GridItem(id: asset.id, farbe: farbe, art: art, favorit: asset.istFavorit,
                        dauer: (asset.dauerMs ?? 0) / 1000)
    }

    static func titel(_ monat: TimelineMonat) -> String {
        guard let (jahr, m) = monat.jahrMonat else { return monat.schluessel }
        return "\(Monatsname.namen[m - 1]) \(jahr)"
    }

    /// „Lissabon · 214 Objekte“: der häufigste Ort des Monats, falls bekannt.
    static func untertitel(_ assets: [TimelineAsset]) -> String {
        var zaehler: [String: Int] = [:]
        for case let stadt? in assets.map(\.stadt) where !stadt.isEmpty { zaehler[stadt, default: 0] += 1 }
        let anzahl = "\(assets.count.formatted()) Objekte"
        guard let ort = zaehler.max(by: { $0.value < $1.value })?.key else { return anzahl }
        return "\(ort) · \(anzahl)"
    }
}
