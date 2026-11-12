import Testing
@testable import DesignSystem

@Suite("RGB")
struct RGBTests {
    @Test("Nachtrose wird korrekt zerlegt")
    func nachtrose() {
        let c = RGB(hex: 0xC8102E)
        #expect(c.red == 200.0 / 255)
        #expect(c.green == 16.0 / 255)
        #expect(c.blue == 46.0 / 255)
    }

    @Test("Schwarz und Weiß")
    func grenzen() {
        #expect(RGB(hex: 0x000000) == RGB(hex: 0))
        let weiss = RGB(hex: 0xFFFFFF)
        #expect(weiss.red == 1 && weiss.green == 1 && weiss.blue == 1)
    }
}
