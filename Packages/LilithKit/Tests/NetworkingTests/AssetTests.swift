import Foundation
import Testing
@testable import Networking

@Suite("Einzelnes Foto")
struct AssetTests {
    let adresse = ServerAddress(eingabe: "foto.example.de")!

    static let asset = """
    {"id":"a1","checksum":"x","createdAt":"2026-10-18T18:00:00.000Z","duration":null,
     "fileCreatedAt":"2026-10-18T18:42:10.000Z","fileModifiedAt":"2026-10-18T18:42:10.000Z","hasMetadata":true,
     "height":3024,"width":4032,"isArchived":false,"isEdited":false,"isFavorite":true,"isOffline":false,"isTrashed":false,
     "localDateTime":"2026-10-18T19:42:10.000Z","originalFileName":"IMG_0042.HEIC","originalPath":"/x","ownerId":"o",
     "thumbhash":null,"type":"IMAGE","updatedAt":"2026-10-18T18:42:10Z","visibility":"timeline","livePhotoVideoId":"v9",
     "exifInfo":{"make":"Canon","model":"Canon EOS R6","lensModel":"RF 24-70","fNumber":1.8,"iso":80,"exposureTime":"1/120",
                 "focalLength":24.0,"fileSizeInByte":6200000,"latitude":38.71,"longitude":-9.13,
                 "city":"Lissabon","state":null,"country":"Portugal","description":"  "},
     "people":[{"id":"p1","name":"Lena","isHidden":false,"birthDate":null,"thumbnailPath":"","otherPeople":[],"sharedBy":[],"sharedWith":[]},
               {"id":"p2","name":"Versteckt","isHidden":true,"birthDate":null,"thumbnailPath":"","otherPeople":[],"sharedBy":[],"sharedWith":[]},
               {"id":"p3","name":"","isHidden":false,"birthDate":null,"thumbnailPath":"","otherPeople":[],"sharedBy":[],"sharedWith":[]}]}
    """

    @Test("Foto-Infos werden gelesen und aufbereitet")
    func info() async throws {
        let transport = MockTransport(["getAssetInfo": (200, Self.asset)])
        let info = try await ImmichClient(address: adresse, credential: .apiKey("k"), transport: transport).assetInfo(id: "a1")
        #expect(info.dateiname == "IMG_0042.HEIC")
        #expect(info.istFavorit && !info.istVideo)
        #expect(info.livePhotoVideoId == "v9")
        #expect(info.kamera == "Canon EOS R6")          // Hersteller nicht doppelt
        #expect(info.objektiv == "RF 24-70")
        #expect(info.blende == 1.8 && info.iso == 80 && info.belichtung == "1/120" && info.brennweite == 24)
        #expect(info.breite == 4032 && info.hoehe == 3024 && info.dateigroesse == 6_200_000)
        #expect(info.ort == "Lissabon, Portugal")
        #expect(info.beschreibung == nil)               // nur Leerzeichen zählt nicht
        #expect(info.personen == ["Lena"])              // versteckte und namenlose Personen fallen raus
        // Ortszeit der Aufnahme: 19:42 Uhr, unabhängig von der eigenen Zeitzone.
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = .gmt
        #expect(kalender.component(.hour, from: info.aufgenommenLokal) == 19)
    }

    @Test("Datum mit und ohne Sekundenbruchteile")
    func datum() throws {
        let t = ImmichDatum()
        #expect(try t.decode("2026-10-18T18:42:10.000Z") == t.decode("2026-10-18T18:42:10Z"))
        #expect(throws: (any Error).self) { try t.decode("gestern") }
    }

    @Test("Favorit setzen schickt die richtige Anfrage")
    func favorit() async throws {
        let transport = MockTransport(["updateAsset": (200, Self.asset)])
        try await ImmichClient(address: adresse, credential: .apiKey("k"), transport: transport).setzeFavorit(id: "a1", true)
        let anfrage = try #require(transport.anfragen.first)
        #expect(anfrage.method == .put)
        #expect(anfrage.path == "/assets/a1")
    }

    @Test("Favorit: abgelaufene Anmeldung wird erkannt")
    func favoritAbgelaufen() async {
        let transport = MockTransport(["updateAsset": (401, #"{"message":"Unauthorized"}"#)])
        await #expect(throws: ImmichError.sitzungAbgelaufen) {
            try await ImmichClient(address: adresse, transport: transport).setzeFavorit(id: "a1", false)
        }
    }

    @Test("Video- und Original-Adressen mit Anmeldung")
    func adressen() {
        let client = ImmichClient(address: adresse, credential: .accessToken("t"))
        #expect(client.videoAnfrage(assetId: "v1").url?.absoluteString == "https://foto.example.de/api/assets/v1/video/playback")
        #expect(client.originalAnfrage(assetId: "a1").url?.absoluteString == "https://foto.example.de/api/assets/a1/original")
        #expect(client.originalAnfrage(assetId: "a1").value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(client.anmeldeHeader == ["Authorization": "Bearer t"])
    }
}
