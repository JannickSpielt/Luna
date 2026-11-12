import Foundation
import Testing
@testable import Networking

@Suite("Datum aus der Timeline lesen")
struct DatumLesenTests {
    @Test("Z, +00:00, mit und ohne Sekundenbruchteile", arguments: [
        "2026-11-12T08:37:56.000Z", "2026-11-12T08:37:56Z", "2026-11-12T08:37:56+00:00", "2026-11-12T08:37:56.000+00:00",
    ])
    func formate(_ text: String) {
        #expect(ImmichClient.leseDatum(text) == Date(timeIntervalSince1970: 1_794_472_676))
    }
}

@Suite("Ortszeit ohne Zeitzone")
struct OrtszeitTests {
    @Test("Timeline-Format mit wechselnden Nachkommastellen")
    func ortszeit() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = .current
        let erwartet = kalender.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 1, second: 18))!
        #expect(abs(ImmichClient.leseDatum("2026-11-12T10:01:18.975")!.timeIntervalSince(erwartet) - 0.975) < 0.001)
        #expect(abs(ImmichClient.leseDatum("2026-11-12T10:01:18.13")!.timeIntervalSince(erwartet) - 0.13) < 0.001)
        #expect(ImmichClient.leseDatum("2026-11-12T10:01:18") == erwartet)
        #expect(ImmichClient.leseDatum("kein Datum") == nil)
    }
}
