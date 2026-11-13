import Foundation
import Testing
@testable import Networking

@Suite("Datum lesen")
struct DatumTests {
    @Test("Ortszeit ohne Zeitzone, mit und ohne Bruchteile")
    func ortszeit() throws {
        var k = DateComponents(); k.year = 2026; k.month = 11; k.day = 12; k.hour = 10; k.minute = 1; k.second = 18
        let erwartet = try #require(Calendar.current.date(from: k))
        #expect(ImmichClient.leseDatum("2026-11-12T10:01:18") == erwartet)
        let mitBruch = try #require(ImmichClient.leseDatum("2026-11-12T10:01:18.975"))
        #expect(abs(mitBruch.timeIntervalSince(erwartet) - 0.975) < 0.0005)
    }

    @Test("Mit Zeitzone über ISO 8601")
    func iso() {
        #expect(ImmichClient.leseDatum("2026-11-12T10:01:18Z") == Date(timeIntervalSince1970: 1_794_477_678))
        #expect(ImmichClient.leseDatum("2026-11-12T10:01:18.500+00:00") == Date(timeIntervalSince1970: 1_794_477_678.5))
        #expect(ImmichClient.leseDatum("Quatsch") == nil)
    }
}
