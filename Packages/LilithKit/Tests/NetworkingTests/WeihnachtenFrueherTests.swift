import Foundation
import Testing
@testable import Networking

@Suite("Weihnachten früher")
struct WeihnachtenFrueherTests {
    private var kalender: Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return k
    }

    private func tag(_ j: Int, _ m: Int, _ t: Int) -> Date {
        kalender.date(from: DateComponents(year: j, month: m, day: t, hour: 12))!
    }

    private let monate = [
        TimelineMonat(schluessel: "2026-12-01", anzahl: 4),
        TimelineMonat(schluessel: "2025-12-01", anzahl: 30),
        TimelineMonat(schluessel: "2025-11-01", anzahl: 8),
        TimelineMonat(schluessel: "2023-12-01T00:00:00.000Z", anzahl: 12),
        TimelineMonat(schluessel: "2022-12-01", anzahl: 0),
    ]

    @Test("Vor dem 27. Dezember zählt das laufende Jahr nicht")
    func vorWeihnachten() {
        #expect(ImmichClient.weihnachtsJahre(monate, heute: tag(2026, 12, 10), kalender: kalender) == [2025, 2023])
        #expect(ImmichClient.weihnachtsJahre(monate, heute: tag(2026, 12, 26), kalender: kalender) == [2025, 2023])
    }

    @Test("Ab dem 27. Dezember zählt auch dieses Jahr")
    func nachWeihnachten() {
        #expect(ImmichClient.weihnachtsJahre(monate, heute: tag(2026, 12, 27), kalender: kalender) == [2026, 2025, 2023])
    }

    @Test("Im Januar ist das Weihnachten vom Vorjahr dabei")
    func imJanuar() {
        #expect(ImmichClient.weihnachtsJahre(monate, heute: tag(2027, 1, 3), kalender: kalender) == [2026, 2025, 2023])
    }

    @Test("Gruppiert nach Jahr, neuestes zuerst, Fotos ohne Datum fallen weg")
    func gruppieren() {
        func foto(_ id: String, _ d: Date?) -> TimelineAsset {
            TimelineAsset(id: id, istBild: true, dauerMs: nil, istFavorit: false, livePhotoVideoId: nil,
                          seitenverhaeltnis: 1, thumbhash: nil, stadt: nil, erstellt: d)
        }
        let gruppen = ImmichClient.gruppiereNachJahr(
            [foto("a", tag(2025, 12, 25)), foto("b", tag(2023, 12, 24)), foto("c", tag(2025, 12, 24)), foto("d", nil)],
            kalender: kalender)
        #expect(gruppen.map(\.jahr) == [2025, 2023])
        #expect(gruppen[0].fotos.map(\.id) == ["a", "c"])
    }
}
