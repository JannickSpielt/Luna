import Foundation
import Testing
@testable import Networking

@Suite("Timeline")
struct TimelineTests {
    let adresse = ServerAddress(eingabe: "foto.example.de")!

    @Test("Monate werden geladen")
    func monate() async throws {
        let transport = MockTransport([
            "getTimeBuckets": (200, #"[{"timeBucket":"2026-10-01","count":214},{"timeBucket":"2026-09-01","count":3}]"#),
        ])
        let monate = try await ImmichClient(address: adresse, credential: .apiKey("k"), transport: transport).timelineMonate()
        #expect(monate == [TimelineMonat(schluessel: "2026-10-01", anzahl: 214), TimelineMonat(schluessel: "2026-09-01", anzahl: 3)])
        #expect(monate[0].jahrMonat! == (2026, 10))
        let anfrage = try #require(transport.anfragen.first)
        #expect(anfrage.path?.contains("visibility=timeline") == true)
    }

    @Test("Spaltenformat wird zu Einträgen, Papierkorb fällt raus")
    func inhalt() async throws {
        let json = """
        {"id":["a","b","c"],"isImage":[true,false,true],"duration":[null,42000,null],
         "isFavorite":[true,false,false],"isTrashed":[false,false,true],
         "livePhotoVideoId":["v1",null,null],"ratio":[1.5,0.5625,1],"thumbhash":["1QcSHQRnh493V4dIh4eXh1h4kJUI",null,null],
         "city":["Lissabon",null,"Porto"],"createdAt":["","",""],"fileCreatedAt":["","",""],
         "localOffsetHours":[0,0,0],"ownerId":["o","o","o"],"projectionType":[null,null,null],
         "visibility":["timeline","timeline","timeline"]}
        """
        let transport = MockTransport(["getTimeBucket": (200, json)])
        let assets = try await ImmichClient(address: adresse, transport: transport)
            .timelineInhalt(TimelineMonat(schluessel: "2026-10-01", anzahl: 3))
        #expect(assets.map(\.id) == ["a", "b"])
        #expect(assets[0].istFavorit && assets[0].livePhotoVideoId == "v1" && assets[0].stadt == "Lissabon")
        #expect(!assets[1].istBild && assets[1].dauerMs == 42000)
    }

    @Test("Vorschau-Anfrage enthält Größe und Anmeldung")
    func vorschau() {
        let a = ImmichClient(address: adresse, credential: .accessToken("t")).vorschauAnfrage(assetId: "x1", groesse: .thumbnail)
        #expect(a.url?.absoluteString == "https://foto.example.de/api/assets/x1/thumbnail?size=thumbnail")
        #expect(a.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        let b = ImmichClient(address: adresse, credential: .apiKey("k")).vorschauAnfrage(assetId: "x1", groesse: .preview)
        #expect(b.value(forHTTPHeaderField: "x-api-key") == "k")
    }

    @Test("Abgelaufene Anmeldung wird erkannt")
    func abgelaufen() async {
        let transport = MockTransport(["getTimeBuckets": (401, #"{"message":"Unauthorized"}"#)])
        await #expect(throws: ImmichError.sitzungAbgelaufen) {
            try await ImmichClient(address: adresse, transport: transport).timelineMonate()
        }
    }
}
