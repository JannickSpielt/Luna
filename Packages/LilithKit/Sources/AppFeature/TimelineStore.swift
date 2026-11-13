import CoreGraphics
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
    /// Hinweis, wenn der Server gerade nicht erreichbar ist, aber schon Fotos geladen sind.
    private(set) var hinweis: String?

    @ObservationIgnored private(set) var sections: [GridSection] = []
    @ObservationIgnored var onMonatGeladen: ((Int, Bool) -> Void)?
    @ObservationIgnored var onAllesNeu: (() -> Void)?
    @ObservationIgnored let filter: TimelineFilter
    /// Server-Monat je Abschnitt. `nil`: Monat nur mit Fotos vom Gerät.
    @ObservationIgnored private var monate: [TimelineMonat?] = []
    /// Nicht gesicherte Fotos vom Gerät je Abschnitt, neueste zuerst.
    @ObservationIgnored private var lokalJeMonat: [[LokalerEintrag]] = []
    /// Aufnahmedatum je Foto, für das Datum oben links.
    @ObservationIgnored private var datumJeId: [String: Date] = [:]
    /// Liefert die nicht gesicherten Fotos vom Gerät (nur Bibliothek, nur wenn das Backup an ist).
    @ObservationIgnored var lokaleFotos: (() -> [LokalerEintrag])?
    /// Lädt Vorschaubilder vom Gerät.
    @ObservationIgnored var lokalesBildLader: ((String, CGFloat) async -> CGImage?)?
    @ObservationIgnored private var inhalte: [Int: [GridItem]] = [:]
    @ObservationIgnored private var laufend: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var sichtbareMonate: Set<Int> = []
    @ObservationIgnored let client: ImmichClient
    /// Wird aufgerufen, wenn der Server die Anmeldung ablehnt.
    @ObservationIgnored var onSitzungAbgelaufen: (() -> Void)?

    init(client: ImmichClient, filter: TimelineFilter = .alle) {
        self.client = client
        self.filter = filter
    }

    func laden() async {
        if sections.isEmpty { zustand = .laedt }
        if case .suche(let text) = filter {
            await ladeListe(titel: "Ergebnisse", untertitel: "beste Treffer zuerst") { try await $0.sucheSmart(text) }
            return
        }
        if case .ort(let stadt, let land) = filter {
            await ladeListe(titel: stadt, untertitel: "neueste zuerst") { try await $0.fotos(inStadt: stadt, land: land) }
            return
        }
        if case .medienart(let art) = filter {
            await ladeListe(titel: art.titel, untertitel: "neueste zuerst") { try await $0.medien(art) }
            return
        }
        if filter == .kuerzlich {
            await ladeListe(titel: "Zuletzt hochgeladen", untertitel: "letzte 30 Tage, neueste zuerst") {
                try await $0.kuerzlichHinzugefuegt()
            }
            return
        }
        do {
            let geladen = try await client.timelineMonate(filter).filter { $0.anzahl > 0 }
            let lokal = filter == .alle ? Self.gruppiere(lokaleFotos?() ?? []) : [:]
            let monatsliste = Self.verbinde(server: geladen, lokal: lokal)
            monate = monatsliste.map(\.server)
            lokalJeMonat = monatsliste.map(\.lokal)
            inhalte = [:]
            laufend.values.forEach { $0.cancel() }
            laufend = [:]
            sections = monatsliste.map { m in
                let anzahl = (m.server?.anzahl ?? 0) + m.lokal.count
                return GridSection(id: m.schluessel, titel: "\(Monatsname.namen[m.monat - 1]) \(m.jahr)",
                                   untertitel: Self.untertitel(anzahl: anzahl, lokal: m.lokal.count), anzahl: anzahl)
            }
            // Monate nur mit Fotos vom Gerät sind sofort fertig.
            for (i, m) in monatsliste.enumerated() where m.server == nil {
                inhalte[i] = m.lokal.map(\.item)
                for l in m.lokal { datumJeId[l.item.id] = l.erstellt }
            }
            gesamt = sections.reduce(0) { $0 + $1.anzahl }
            zustand = sections.isEmpty ? .leer : .bereit
            hinweis = nil
            sichtbareMonate = []
            onAllesNeu?()
        } catch ImmichError.sitzungAbgelaufen {
            onSitzungAbgelaufen?()
        } catch {
            melde(error)
        }
    }

    /// Suchergebnisse und „Kürzlich hinzugefügt“ haben keine Monate: Sie stehen in fester Reihenfolge
    /// in einem einzigen Abschnitt.
    private func ladeListe(titel: String, untertitel: String,
                           _ laden: (ImmichClient) async throws -> [TimelineAsset]) async {
        do {
            let treffer = try await laden(client).map(Self.gridItem)
            monate = []
            lokalJeMonat = []
            laufend.values.forEach { $0.cancel() }
            laufend = [:]
            inhalte = [0: treffer]
            sections = treffer.isEmpty ? [] : [GridSection(
                id: "liste", titel: titel, untertitel: untertitel, anzahl: treffer.count)]
            gesamt = treffer.count
            zustand = treffer.isEmpty ? .leer : .bereit
            hinweis = nil
            sichtbareMonate = []
            onAllesNeu?()
        } catch ImmichError.sitzungAbgelaufen {
            onSitzungAbgelaufen?()
        } catch {
            melde(error)
        }
    }

    /// Sind schon Fotos da, bleiben sie sichtbar und es gibt nur einen Hinweis. Sonst eine Fehlerseite.
    private func melde(_ error: any Error) {
        if sections.isEmpty {
            zustand = .fehler(error.localizedDescription)
        } else {
            hinweis = error.localizedDescription
        }
    }

    // MARK: - TimelineQuelle

    func item(section: Int, index: Int) -> GridItem? {
        guard let liste = inhalte[section], index < liste.count else { return nil }
        return liste[index]
    }

    func datum(section: Int, index: Int) -> Date? {
        item(section: section, index: index).flatMap { datumJeId[$0.id] }
    }

    /// Monate in der Nähe des Sichtbaren (±1) werden gebraucht, alles andere wurde nur überflogen.
    private func wirdGebraucht(_ section: Int) -> Bool {
        sichtbareMonate.isEmpty || sichtbareMonate.contains { abs($0 - section) <= 1 }
    }

    func sichtbar(_ sections: Set<Int>) {
        sichtbareMonate = sections
        // Ladevorgänge für überflogene Monate abbrechen, damit der Zielmonat schneller drankommt.
        for (section, aufgabe) in laufend where !wirdGebraucht(section) {
            aufgabe.cancel()
            laufend[section] = nil
        }
    }

    func ladeMonat(_ section: Int) {
        ladeMonat(section, erzwingen: false)
    }

    /// `erzwingen`: sofort laden, auch wenn der Monat im Grid gerade nicht zu sehen ist (für die Detailansicht).
    func ladeMonat(_ section: Int, erzwingen: Bool) {
        guard section >= 0, section < monate.count, inhalte[section] == nil, laufend[section] == nil,
              let monat = monate[section] else { return }
        laufend[section] = Task {
            defer { if laufend[section] != nil, !Task.isCancelled { laufend[section] = nil } }
            // Kurz warten: Beim schnellen Scrubben ist der Monat danach oft schon wieder weg.
            if !erzwingen {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, wirdGebraucht(section) else {
                    laufend[section] = nil
                    return
                }
            }
            do {
                let assets = try await client.timelineInhalt(monat, filter: filter)
                guard !Task.isCancelled else { return }
                // Die Monate könnten inzwischen neu geladen worden sein.
                guard section < monate.count, monate[section] == monat else { return }
                let lokal = section < lokalJeMonat.count ? lokalJeMonat[section] : []
                inhalte[section] = Self.mische(assets, lokal: lokal)
                for a in assets { if let d = a.erstellt { datumJeId[a.id] = d } }
                for l in lokal { datumJeId[l.item.id] = l.erstellt }
                let alteAnzahl = sections[section].anzahl
                let neueAnzahl = assets.count + lokal.count
                sections[section].anzahl = neueAnzahl
                sections[section].untertitel = Self.untertitel(assets, lokal: lokal.count)
                onMonatGeladen?(section, neueAnzahl != alteAnzahl)
            } catch ImmichError.sitzungAbgelaufen {
                onSitzungAbgelaufen?()
            } catch {
                // Kein Absturz und keine Fehlermeldung pro Monat: Beim nächsten Anzeigen wird es erneut versucht.
            }
        }
    }

    /// Setzt oder entfernt den Favoriten: sofort in der Ansicht, dann auf dem Server. Bei Fehler wird zurückgestellt.
    func setzeFavorit(section: Int, index: Int, _ favorit: Bool) async throws {
        guard let alt = item(section: section, index: index) else { return }
        ersetze(alt.mit(favorit: favorit), section: section, index: index)
        do {
            try await client.setzeFavorit(id: alt.id, favorit)
        } catch {
            if item(section: section, index: index)?.id == alt.id { ersetze(alt, section: section, index: index) }
            if case ImmichError.sitzungAbgelaufen = error { onSitzungAbgelaufen?() }
            throw error
        }
    }

    private func ersetze(_ neu: GridItem, section: Int, index: Int) {
        inhalte[section]?[index] = neu
        onMonatGeladen?(section, false)
    }

    func ladeOriginal(_ item: GridItem) async throws -> URL {
        guard item.lokal == nil else { throw CocoaError(.featureUnsupported) }
        let name = (try? await client.assetInfo(id: item.id).dateiname) ?? item.id
        return try await client.ladeOriginal(assetId: item.id, dateiname: name)
    }

    func lokalesBild(fuer item: GridItem, pixel: CGFloat) async -> CGImage? {
        guard let id = item.lokaleId else { return nil }
        return await lokalesBildLader?(id, pixel)
    }

    func bildAnfragen(fuer item: GridItem, pixel: CGFloat) -> [URLRequest] {
        guard item.lokal == nil else { return [] }
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
                        dauer: (asset.dauerMs ?? 0) / 1000, liveVideoId: asset.livePhotoVideoId)
    }

    static func titel(_ monat: TimelineMonat) -> String {
        guard let (jahr, m) = monat.jahrMonat else { return monat.schluessel }
        return "\(Monatsname.namen[m - 1]) \(jahr)"
    }

    /// „Lissabon · 214 Objekte“: der häufigste Ort des Monats, falls bekannt.
    static func untertitel(_ assets: [TimelineAsset], lokal: Int = 0) -> String {
        var zaehler: [String: Int] = [:]
        for case let stadt? in assets.map(\.stadt) where !stadt.isEmpty { zaehler[stadt, default: 0] += 1 }
        let anzahl = untertitel(anzahl: assets.count + lokal, lokal: lokal)
        guard let ort = zaehler.max(by: { $0.value < $1.value })?.key else { return anzahl }
        return "\(ort) · \(anzahl)"
    }

    static func untertitel(anzahl: Int, lokal: Int) -> String {
        let text = "\(anzahl.formatted()) Objekte"
        return lokal == 0 ? text : "\(text) · \(lokal.formatted()) nicht gesichert"
    }

    // MARK: - Fotos vom Gerät

    struct Monatsliste {
        let schluessel: String
        let jahr: Int
        let monat: Int
        let server: TimelineMonat?
        let lokal: [LokalerEintrag]
    }

    /// Lokale Fotos nach Monat („2026-10“), jeweils neueste zuerst.
    static func gruppiere(_ eintraege: [LokalerEintrag]) -> [String: [LokalerEintrag]] {
        let kalender = Calendar.current
        var ergebnis: [String: [LokalerEintrag]] = [:]
        for e in eintraege {
            let t = kalender.dateComponents([.year, .month], from: e.erstellt)
            ergebnis[schluessel(t.year ?? 0, t.month ?? 1), default: []].append(e)
        }
        return ergebnis.mapValues { $0.sorted { $0.erstellt > $1.erstellt } }
    }

    static func schluessel(_ jahr: Int, _ monat: Int) -> String { String(format: "%04d-%02d", jahr, monat) }

    /// Server-Monate und Monate mit Fotos vom Gerät zu einer Liste, neueste zuerst.
    static func verbinde(server: [TimelineMonat], lokal: [String: [LokalerEintrag]]) -> [Monatsliste] {
        var liste: [Monatsliste] = []
        var rest = lokal
        for m in server {
            guard let (jahr, monat) = m.jahrMonat else {
                liste.append(Monatsliste(schluessel: m.schluessel, jahr: 0, monat: 1, server: m, lokal: []))
                continue
            }
            let k = schluessel(jahr, monat)
            liste.append(Monatsliste(schluessel: m.schluessel, jahr: jahr, monat: monat, server: m,
                                     lokal: rest.removeValue(forKey: k) ?? []))
        }
        for (k, eintraege) in rest {
            let teile = k.split(separator: "-").compactMap { Int($0) }
            guard teile.count == 2 else { continue }
            liste.append(Monatsliste(schluessel: "lokal-\(k)", jahr: teile[0], monat: teile[1], server: nil, lokal: eintraege))
        }
        return liste.sorted { ($0.jahr, $0.monat) > ($1.jahr, $1.monat) }
    }

    /// Fotos vom Gerät nach Datum zwischen die Server-Fotos (beide neueste zuerst).
    static func mische(_ assets: [TimelineAsset], lokal: [LokalerEintrag]) -> [GridItem] {
        guard !lokal.isEmpty else { return assets.map(gridItem) }
        var ergebnis: [GridItem] = []
        ergebnis.reserveCapacity(assets.count + lokal.count)
        var l = 0
        for a in assets {
            while l < lokal.count, let datum = a.erstellt, lokal[l].erstellt > datum {
                ergebnis.append(lokal[l].item)
                l += 1
            }
            ergebnis.append(gridItem(a))
        }
        ergebnis.append(contentsOf: lokal[l...].map(\.item))
        return ergebnis
    }
}

/// Ein Foto vom Gerät, das noch nicht auf dem Server ist.
struct LokalerEintrag: Sendable {
    let item: GridItem
    let erstellt: Date
}
