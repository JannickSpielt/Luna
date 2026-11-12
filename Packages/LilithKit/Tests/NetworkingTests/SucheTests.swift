import Foundation
import Testing
@testable import Networking

@Suite("Smart Search")
struct SucheTests {
    let adresse = ServerAddress(eingabe: "foto.example.de")!

    @Test("Treffer werden in Reihenfolge der Relevanz geliefert, Gelöschtes fällt raus")
    func treffer() async throws {
        let geloescht = AssetTests.asset.replacingOccurrences(of: #""id":"a1""#, with: #""id":"weg""#)
            .replacingOccurrences(of: #""isTrashed":false"#, with: #""isTrashed":true"#)
        let zweites = AssetTests.asset.replacingOccurrences(of: #""id":"a1""#, with: #""id":"a2""#)
        let json = """
        {"albums":{"count":0,"facets":[],"items":[],"total":0},
         "assets":{"count":3,"facets":[],"items":[\(AssetTests.asset),\(geloescht),\(zweites)],"nextCursor":null,"nextPage":null,"total":3}}
        """
        let transport = MockTransport(["searchSmart": (200, json)])
        let treffer = try await ImmichClient(address: adresse, credential: .apiKey("k"), transport: transport).sucheSmart("Katze")
        #expect(treffer.map(\.id) == ["a1", "a2"])
        #expect(treffer[0].istBild && treffer[0].istFavorit && treffer[0].livePhotoVideoId == "v9")
        #expect(abs(treffer[0].seitenverhaeltnis - 4032.0 / 3024.0) < 0.001)
        #expect(transport.anfragen.first?.path == "/search/smart")
    }

    @Test("Fehler vom Server wird gemeldet")
    func fehler() async {
        let transport = MockTransport(["searchSmart": (500, #"{"message":"ML down"}"#)])
        await #expect(throws: ImmichError.unerwarteteAntwort(500)) {
            try await ImmichClient(address: adresse, transport: transport).sucheSmart("Katze")
        }
    }

    @Test("Kürzlich hinzugefügt: nach Hochladezeit sortiert, neueste zuerst")
    func kuerzlich() async throws {
        let alt = AssetTests.asset.replacingOccurrences(of: #""id":"a1""#, with: #""id":"alt""#)
            .replacingOccurrences(of: #""createdAt":"2026-10-18T18:00:00.000Z""#, with: #""createdAt":"2026-11-01T08:00:00.000Z""#)
        let neu = AssetTests.asset.replacingOccurrences(of: #""id":"a1""#, with: #""id":"neu""#)
            .replacingOccurrences(of: #""createdAt":"2026-10-18T18:00:00.000Z""#, with: #""createdAt":"2026-11-12T09:00:00.000Z""#)
        let json = """
        {"albums":{"count":0,"facets":[],"items":[],"total":0},
         "assets":{"count":2,"facets":[],"items":[\(alt),\(neu)],"nextCursor":null,"nextPage":null,"total":2}}
        """
        let transport = MockTransport(["searchAssets": (200, json)])
        let liste = try await ImmichClient(address: adresse, credential: .apiKey("k"), transport: transport).kuerzlichHinzugefuegt()
        #expect(liste.map(\.id) == ["neu", "alt"])
        #expect(transport.anfragen.first?.path == "/search/metadata")
    }
}
