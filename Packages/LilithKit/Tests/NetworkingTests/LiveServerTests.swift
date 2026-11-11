import Foundation
import Testing
@testable import Networking

/// Spricht mit einem echten Immich-Server. Läuft nur, wenn die Adresse gesetzt ist:
///   LILITH_LIVE_SERVER=https://fotos.example.de swift test
@Suite("Echter Server", .enabled(if: ProcessInfo.processInfo.environment["LILITH_LIVE_SERVER"] != nil))
struct LiveServerTests {
    let adresse = ServerAddress(eingabe: ProcessInfo.processInfo.environment["LILITH_LIVE_SERVER"] ?? "")

    @Test("Serverprüfung gegen echten Server")
    func serverInfo() async throws {
        let adresse = try #require(adresse)
        let info = try await ImmichClient(address: adresse).serverInfo()
        #expect(info.version >= .minimum)
        print("Live:", info.version, info.capabilities)
    }

    @Test("Falsches Passwort wird vom echten Server abgelehnt")
    func falschesPasswort() async throws {
        let adresse = try #require(adresse)
        await #expect(throws: ImmichError.falscheZugangsdaten) {
            try await ImmichClient(address: adresse).login(email: "lilith-test@example.invalid", password: "falsch")
        }
    }

    @Test("Ungültiger API-Key wird erkannt")
    func falscherKey() async throws {
        let adresse = try #require(adresse)
        await #expect(throws: ImmichError.sitzungAbgelaufen) {
            try await ImmichClient(address: adresse, credential: .apiKey("ungueltig")).currentUser()
        }
    }
}
