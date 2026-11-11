import Testing
@testable import TimelineGrid

@MainActor
@Suite("Grid-Testdaten")
struct GridModelTests {
    let quelle = BeispielQuelle()

    @Test("Genau 100.000 Einträge, Anzahl pro Monat stimmt")
    func vollstaendig() {
        #expect(quelle.gesamt == 100_000)
        #expect(quelle.sections.reduce(0) { $0 + $1.anzahl } == 100_000)
        #expect(quelle.item(section: 3, index: quelle.sections[3].anzahl - 1) != nil)
    }

    @Test("Neuester Monat zuerst")
    func reihenfolge() {
        #expect(quelle.sections.first?.titel == "November 2026")
        #expect(quelle.sections[1].titel == "Oktober 2026")
        #expect(quelle.sections[11].titel == "Dezember 2025")
    }

    @Test("Gleicher Startwert ergibt gleiche Daten")
    func deterministisch() {
        let nochmal = BeispielQuelle()
        #expect(nochmal.sections == quelle.sections)
        #expect(nochmal.item(section: 5, index: 7) == quelle.item(section: 5, index: 7))
    }

    @Test("Scrubber-Anteil wird dem richtigen Monat zugeordnet")
    func scrubber() {
        #expect(quelle.section(beiAnteil: 0) == 0)
        #expect(quelle.section(beiAnteil: 1) == quelle.sections.count - 1)
        let mitte = quelle.section(beiAnteil: 0.5)!
        let davor = quelle.sections[..<mitte].reduce(0) { $0 + $1.anzahl }
        #expect(davor <= 50_000)
        #expect(davor + quelle.sections[mitte].anzahl > 50_000)
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

    @Test("Durchschnittsfarbe aus Thumbhash")
    func thumbhash() {
        // Beispiel-Thumbhash aus der Referenz (überwiegend helles Bild).
        let farbe = Thumbhash.durchschnittsfarbe("1QcSHQRnh493V4dIh4eXh1h4kJUI")
        #expect(farbe != nil)
        #expect(Thumbhash.durchschnittsfarbe("kein base64!") == nil)
        #expect(Thumbhash.durchschnittsfarbe("") == nil)
    }
}
