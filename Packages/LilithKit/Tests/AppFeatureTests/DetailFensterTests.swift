import Testing
import TimelineGrid
@testable import AppFeature

@MainActor
@Suite("Detailansicht: Blättern")
struct DetailFensterTests {
    let quelle = BeispielQuelle(anzahl: 1_000)

    @Test("Vor und zurück über Monatsgrenzen")
    func grenzen() {
        let ersterMonat = quelle.sections[0].anzahl
        let letztes = DetailPosition(section: 0, index: ersterMonat - 1)
        #expect(DetailView.danach(letztes, quelle: quelle) == DetailPosition(section: 1, index: 0))
        #expect(DetailView.davor(DetailPosition(section: 1, index: 0), quelle: quelle) == letztes)
        #expect(DetailView.davor(DetailPosition(section: 0, index: 0), quelle: quelle) == nil)
        let ende = DetailPosition(section: quelle.sections.count - 1, index: quelle.sections.last!.anzahl - 1)
        #expect(DetailView.danach(ende, quelle: quelle) == nil)
    }

    @Test("Fenster ist lückenlos, begrenzt und enthält die Mitte")
    func fenster() {
        let mitte = DetailPosition(section: 1, index: 3)
        let seiten = DetailView.fenster(um: mitte, quelle: quelle, radius: 40)
        #expect(seiten.count == 81)
        #expect(seiten[40] == mitte)
        for (a, b) in zip(seiten, seiten.dropFirst()) {
            #expect(DetailView.danach(a, quelle: quelle) == b)
        }
        // Am Anfang der Bibliothek gibt es davor nichts.
        let anfang = DetailView.fenster(um: DetailPosition(section: 0, index: 0), quelle: quelle, radius: 40)
        #expect(anfang.first == DetailPosition(section: 0, index: 0) && anfang.count == 41)
    }
}
