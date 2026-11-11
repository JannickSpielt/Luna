import Testing
@testable import Networking

@Suite("Serveradresse")
struct ServerAddressTests {
    @Test("Ergänzt https:// und entfernt /api und Schrägstriche", arguments: [
        ("fotos.example.de", "https://fotos.example.de"),
        ("https://fotos.example.de/", "https://fotos.example.de"),
        ("  https://fotos.example.de/api/  ", "https://fotos.example.de"),
        ("http://192.168.1.20:2283", "http://192.168.1.20:2283"),
        ("HTTPS://Fotos.example.de/immich/api", "HTTPS://Fotos.example.de/immich"),
    ])
    func normalisiert(eingabe: String, erwartet: String) throws {
        let adresse = try #require(ServerAddress(eingabe: eingabe))
        #expect(adresse.url.absoluteString == erwartet)
    }

    @Test("API-Adresse hängt /api an")
    func apiURL() throws {
        let adresse = try #require(ServerAddress(eingabe: "fotos.example.de"))
        #expect(adresse.apiURL.absoluteString == "https://fotos.example.de/api")
    }

    @Test("Lehnt Unsinn ab", arguments: ["", "   ", "ftp://server", "zwei wörter", "https://", "https://x.de?a=1"])
    func lehntAb(eingabe: String) {
        #expect(ServerAddress(eingabe: eingabe) == nil)
    }
}

@Suite("Serverversion")
struct ServerVersionTests {
    @Test("Vergleich und Mindestversion")
    func vergleich() {
        let v335 = ServerVersion(major: 3, minor: 3, patch: 5)
        #expect(v335 >= .minimum)
        #expect(ServerVersion(major: 2, minor: 7, patch: 9) < .minimum)
        #expect(v335.description == "v3.3.5")
    }
}
