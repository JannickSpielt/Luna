import Testing
@testable import Networking

@Suite("Ordner")
struct OrdnerTests {
    let alle = [
        "/upload/library/admin/2024/01",
        "/upload/library/admin/2024/02",
        "/upload/library/admin/2025/Urlaub",
    ]

    @Test("Gemeinsamer Anfang und Unterordner")
    func baum() {
        let start = OrdnerBaum.gemeinsamerAnfang(alle)
        #expect(start == "/upload/library/admin")
        #expect(OrdnerBaum.unterordner(von: start, in: alle).map(\.name) == ["2024", "2025"])
        #expect(OrdnerBaum.unterordner(von: "/upload/library/admin/2024", in: alle).map(\.pfad)
                == ["/upload/library/admin/2024/01", "/upload/library/admin/2024/02"])
        #expect(OrdnerBaum.hatFotos("/upload/library/admin/2024/01", in: alle))
        #expect(!OrdnerBaum.hatFotos("/upload/library/admin/2024", in: alle))
    }
}
