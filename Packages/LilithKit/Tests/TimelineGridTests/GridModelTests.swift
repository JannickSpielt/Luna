import Testing
@testable import TimelineGrid

@Suite("Grid-Testdaten")
struct GridModelTests {
    let modell = GridModel.beispiel()

    @Test("Genau 100.000 Einträge, lückenlos auf Monate verteilt")
    func vollstaendig() {
        #expect(modell.items.count == 100_000)
        #expect(modell.sections.reduce(0) { $0 + $1.anzahl } == 100_000)
        var erwarteterStart = 0
        for section in modell.sections {
            #expect(section.bereich.lowerBound == erwarteterStart)
            #expect(section.anzahl > 0)
            erwarteterStart = section.bereich.upperBound
        }
    }

    @Test("Neuester Monat zuerst")
    func reihenfolge() {
        #expect(modell.sections.first?.titel == "November 2026")
        #expect(modell.sections[1].titel == "Oktober 2026")
        #expect(modell.sections[11].titel == "Dezember 2025")
    }

    @Test("Gleicher Startwert ergibt gleiche Daten")
    func deterministisch() {
        let nochmal = GridModel.beispiel()
        #expect(nochmal.items == modell.items)
        #expect(nochmal.sections == modell.sections)
    }

    @Test("Zugriff über Monat und Position")
    func zugriff() {
        let zweiter = modell.sections[1]
        #expect(modell[1, 0] == modell.items[zweiter.bereich.lowerBound])
    }

    @Test("Zoomstufen bleiben in den Grenzen")
    func zoom() {
        var zoom = GridZoom.iPhone
        #expect(zoom.spalten == 3)
        let ersterSchritt = zoom.groesser()
        #expect(ersterSchritt)
        #expect(zoom.spalten == 1)
        let zweiterSchritt = zoom.groesser()
        #expect(!zweiterSchritt)
        while zoom.kleiner() {}
        #expect(zoom.spalten == 11)
    }
}
