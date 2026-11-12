import Foundation
import Testing
@testable import AppFeature
import Networking
import TimelineGrid

@MainActor
@Suite("Nicht gesicherte Fotos in der Timeline")
struct LokaleFotosTests {
    func datum(_ text: String) -> Date { try! Date.ISO8601FormatStyle().parse(text) }

    func lokal(_ id: String, _ text: String) -> LokalerEintrag {
        LokalerEintrag(item: GridItem(id: GridItem.lokalPraefix + id, farbe: 0, art: .foto, favorit: false, dauer: 0, lokal: .nurHier),
                       erstellt: datum(text))
    }

    func server(_ id: String, _ text: String) -> TimelineAsset {
        TimelineAsset(id: id, istBild: true, dauerMs: nil, istFavorit: false, livePhotoVideoId: nil,
                      seitenverhaeltnis: 1, thumbhash: nil, stadt: nil, erstellt: datum(text))
    }

    @Test("Fotos vom Gerät landen nach Datum zwischen den Server-Fotos")
    func mischen() {
        let assets = [server("s1", "2026-10-20T10:00:00Z"), server("s2", "2026-10-10T10:00:00Z")]
        let lokal = [lokal("l1", "2026-10-25T10:00:00Z"), lokal("l2", "2026-10-15T10:00:00Z"), lokal("l3", "2026-10-01T10:00:00Z")]
        let ids = TimelineStore.mische(assets, lokal: lokal).map(\.id)
        #expect(ids == ["lokal:l1", "s1", "lokal:l2", "s2", "lokal:l3"])
    }

    @Test("Monate nur mit Fotos vom Gerät werden einsortiert")
    func monate() {
        let server = [TimelineMonat(schluessel: "2026-11-01", anzahl: 5), TimelineMonat(schluessel: "2026-09-01", anzahl: 3)]
        let gruppen = TimelineStore.gruppiere([lokal("a", "2026-10-15T12:00:00Z"), lokal("b", "2026-11-03T12:00:00Z")])
        let liste = TimelineStore.verbinde(server: server, lokal: gruppen)
        #expect(liste.map(\.monat) == [11, 10, 9])
        #expect(liste[0].server != nil && liste[0].lokal.count == 1)
        #expect(liste[1].server == nil && liste[1].lokal.map(\.item.id) == ["lokal:a"])
        #expect(liste[2].lokal.isEmpty)
    }

    @Test("Lokale Kennung wird aus der ID gelesen")
    func kennung() {
        let item = GridItem(id: "lokal:ABC/L0/001", farbe: 0, art: .foto, favorit: false, dauer: 0, lokal: .fehler)
        #expect(item.lokaleId == "ABC/L0/001")
        #expect(GridItem(id: "x", farbe: 0, art: .foto, favorit: false, dauer: 0).lokaleId == nil)
    }
}
