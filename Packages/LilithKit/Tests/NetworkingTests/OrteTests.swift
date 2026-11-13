import Testing
@testable import Networking

@Suite("Orte")
struct OrteTests {
    @Test("Kartenpunkte werden je Stadt zusammengefasst, die meisten zuerst")
    func gruppieren() {
        let orte = ImmichClient.gruppiereOrte([
            ("a", "Berlin", "Deutschland", 52.0, 13.0),
            ("b", "Paris", "Frankreich", 48.0, 2.0),
            ("c", "Berlin", "Deutschland", 54.0, 15.0),
        ])
        #expect(orte.map(\.stadt) == ["Berlin", "Paris"])
        #expect(orte[0].anzahl == 2)
        #expect(orte[0].breite == 53.0)
        #expect(orte[0].titelBildId == "a")
    }
}
