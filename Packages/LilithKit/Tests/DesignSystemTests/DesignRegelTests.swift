import Foundation
import Testing
@testable import DesignSystem

@Suite("Design und Weihnachtsregel")
struct DesignRegelTests {
    private var kalender: Calendar {
        var k = Calendar(identifier: .gregorian)
        k.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return k
    }

    private func tag(_ j: Int, _ m: Int, _ t: Int) -> Date {
        kalender.date(from: DateComponents(year: j, month: m, day: t, hour: 12))!
    }

    @Test("Am 1. Dezember geht Weihnachten von selbst an und merkt sich das Design davor")
    func beginn() {
        let neu = DesignStand(gewaehlt: .nacht).geprueft(heute: tag(2026, 12, 1), kalender: kalender)
        #expect(neu == DesignStand(gewaehlt: .weihnachten, vorher: .nacht, saison: 2026))
    }

    @Test("Eine eigene Wahl in der Weihnachtszeit bleibt")
    func eigeneWahlBleibt() {
        var stand = DesignStand(gewaehlt: .standard).geprueft(heute: tag(2026, 12, 1), kalender: kalender)
        stand.gewaehlt = .schwarz
        let spaeter = stand.geprueft(heute: tag(2026, 12, 20), kalender: kalender)
        #expect(spaeter.gewaehlt == .schwarz)
        let januar = spaeter.geprueft(heute: tag(2027, 1, 3), kalender: kalender)
        #expect(januar.gewaehlt == .schwarz)
    }

    @Test("Am 7. Januar kommt das vorherige Design zurück")
    func ende() {
        let dezember = DesignStand(gewaehlt: .nacht).geprueft(heute: tag(2026, 12, 5), kalender: kalender)
        #expect(dezember.geprueft(heute: tag(2027, 1, 6), kalender: kalender).gewaehlt == .weihnachten)
        let danach = dezember.geprueft(heute: tag(2027, 1, 7), kalender: kalender)
        #expect(danach == DesignStand(gewaehlt: .nacht, vorher: nil, saison: 2026))
    }

    @Test("Nach Weihnachten gewählt und wieder abgewählt: im nächsten Dezember wieder automatisch")
    func naechstesJahr() {
        let danach = DesignStand(gewaehlt: .standard).geprueft(heute: tag(2026, 12, 2), kalender: kalender)
            .geprueft(heute: tag(2027, 2, 1), kalender: kalender)
        #expect(danach.gewaehlt == .standard)
        let neu = danach.geprueft(heute: tag(2027, 12, 1), kalender: kalender)
        #expect(neu == DesignStand(gewaehlt: .weihnachten, vorher: .standard, saison: 2027))
    }

    @Test("Außerhalb der Weihnachtszeit gibt es das Design nicht zur Wahl")
    func waehlbar() {
        #expect(!Design.waehlbar(heute: tag(2026, 11, 14), kalender: kalender).contains(.weihnachten))
        #expect(Design.waehlbar(heute: tag(2026, 12, 24), kalender: kalender).contains(.weihnachten))
        #expect(Design.waehlbar(heute: tag(2027, 1, 6), kalender: kalender).contains(.weihnachten))
    }

    @Test("Im November ändert sich nichts")
    func november() {
        let stand = DesignStand(gewaehlt: .schwarz)
        #expect(stand.geprueft(heute: tag(2026, 11, 30), kalender: kalender) == stand)
    }
}
