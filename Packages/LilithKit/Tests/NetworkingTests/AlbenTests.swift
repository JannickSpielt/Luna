import Foundation
import Testing
@testable import Networking

@Suite("Alben und Mehrfach-Aktionen")
struct AlbenTests {
    let adresse = ServerAddress(eingabe: "foto.example.de")!
    var client: (MockTransport) -> ImmichClient {
        { ImmichClient(address: adresse, credential: .apiKey("k"), transport: $0) }
    }

    static func album(_ id: String, _ name: String, _ anzahl: Int, geteilt: Bool = false) -> String {
        """
        {"id":"\(id)","albumName":"\(name)","albumThumbnailAssetId":null,"albumUsers":[],"assetCount":\(anzahl),
         "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z","description":"",
         "hasSharedLink":false,"isActivityEnabled":true,"shared":\(geteilt)}
        """
    }

    @Test("Alben werden geladen und nach Name sortiert")
    func alben() async throws {
        let transport = MockTransport(["getAllAlbums": (200, "[\(Self.album("b", "Ostsee", 96)),\(Self.album("a", "Familie", 1832, geteilt: true))]")])
        let alben = try await client(transport).alben()
        #expect(alben.map(\.name) == ["Familie", "Ostsee"])
        #expect(alben[0].geteilt && alben[0].anzahl == 1832)
    }

    @Test("Album anlegen")
    func anlegen() async throws {
        let transport = MockTransport(["createAlbum": (201, Self.album("n", "Neu", 2))])
        let album = try await client(transport).erstelleAlbum(name: "Neu", assetIds: ["x", "y"])
        #expect(album.id == "n" && album.anzahl == 2)
        #expect(transport.anfragen.first?.method == .post)
    }

    @Test("Zu Album hinzufügen zählt nur neue Fotos")
    func hinzufuegen() async throws {
        let transport = MockTransport(["addAssetsToAlbum": (200, #"[{"id":"x","success":true},{"id":"y","success":false,"error":"duplicate"}]"#)])
        let neu = try await client(transport).fuegeZuAlbum(albumId: "a", assetIds: ["x", "y"])
        #expect(neu == 1)
        #expect(transport.anfragen.first?.path == "/albums/a/assets")
    }

    @Test("Favorit, Archiv, Löschen und Wiederherstellen schicken die richtigen Anfragen")
    func aktionen() async throws {
        let transport = MockTransport([
            "updateAssets": (204, ""), "deleteAssets": (204, ""), "restoreAssets": (200, #"{"count":2}"#),
        ])
        let c = client(transport)
        try await c.aendere(assetIds: ["x"], favorit: true)
        try await c.aendere(assetIds: ["x"], archiviert: true)
        try await c.loesche(assetIds: ["x", "y"])
        try await c.stelleWiederHer(assetIds: ["x", "y"])
        #expect(transport.anfragen.map { "\($0.method.rawValue) \($0.path ?? "")" }
                == ["PUT /assets", "PUT /assets", "DELETE /assets", "POST /trash/restore/assets"])
        // Ohne Fotos wird gar nichts geschickt.
        try await c.loesche(assetIds: [])
        #expect(transport.anfragen.count == 4)
    }

    @Test("Abgelaufene Anmeldung wird erkannt")
    func abgelaufen() async {
        let transport = MockTransport(["deleteAssets": (401, #"{"message":"Unauthorized"}"#)])
        await #expect(throws: ImmichError.sitzungAbgelaufen) { try await client(transport).loesche(assetIds: ["x"]) }
    }

    @Test("Filter werden in die richtigen Abfragen übersetzt")
    func filter() async throws {
        let transport = MockTransport(["getTimeBuckets": (200, "[]")])
        let c = client(transport)
        for f in [TimelineFilter.alle, .favoriten, .archiv, .papierkorb, .album("a1")] { _ = try await c.timelineMonate(f) }
        let pfade = transport.anfragen.compactMap(\.path)
        #expect(pfade[0].contains("visibility=timeline") && !pfade[0].contains("isFavorite"))
        #expect(pfade[1].contains("isFavorite=true"))
        #expect(pfade[2].contains("visibility=archive"))
        #expect(pfade[3].contains("isTrashed=true") && !pfade[3].contains("visibility"))
        #expect(pfade[4].contains("albumId=a1"))
    }

    @Test("Im Papierkorb bleiben gelöschte Fotos sichtbar")
    func papierkorbInhalt() async throws {
        let json = """
        {"id":["a","b"],"isImage":[true,true],"duration":[null,null],"isFavorite":[false,false],"isTrashed":[true,true],
         "livePhotoVideoId":[null,null],"ratio":[1,1],"thumbhash":[null,null],"createdAt":["",""],"fileCreatedAt":["",""],
         "localOffsetHours":[0,0],"ownerId":["o","o"],"projectionType":[null,null],"visibility":["timeline","timeline"]}
        """
        let monat = TimelineMonat(schluessel: "2026-10-01", anzahl: 2)
        let imPapierkorb = try await client(MockTransport(["getTimeBucket": (200, json)])).timelineInhalt(monat, filter: .papierkorb)
        let normal = try await client(MockTransport(["getTimeBucket": (200, json)])).timelineInhalt(monat)
        #expect(imPapierkorb.count == 2 && normal.isEmpty)
    }
}
