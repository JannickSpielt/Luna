import Testing
@testable import AppFeature

@Suite("App-Update")
struct AppUpdateTests {
    @Test("Versionen werden als Zahlen verglichen")
    func vergleich() {
        #expect(AppUpdate.istNeuer("0.10.0", als: "0.9.1"))
        #expect(AppUpdate.istNeuer("1.0", als: "0.9.9"))
        #expect(!AppUpdate.istNeuer("0.9.0", als: "0.9.0"))
        #expect(!AppUpdate.istNeuer("0.9.0-beta", als: "0.9.0"))
        #expect(!AppUpdate.istNeuer("0.8.5", als: "0.9"))
        #expect(AppUpdate.istNeuer("0.9.1", als: "0.9"))
    }
}
