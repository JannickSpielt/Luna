import Foundation
import Testing
@testable import DesignSystem

@Suite("Weihnachten")
struct WeihnachtenTests {
    func datum(_ m: Int, _ t: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: m, day: t))!
    }

    @Test("Zeitraum 1. Dezember bis 6. Januar")
    func zeitraum() {
        #expect(Weihnachten.zeitraum(datum(12, 1)))
        #expect(Weihnachten.zeitraum(datum(12, 24)))
        #expect(Weihnachten.zeitraum(datum(1, 6)))
        #expect(!Weihnachten.zeitraum(datum(1, 7)))
        #expect(!Weihnachten.zeitraum(datum(11, 30)))
    }
}
