import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import Networking

/// Antwortet auf Anfragen mit festen JSON-Antworten, ohne Netzwerk.
final class MockTransport: ClientTransport, @unchecked Sendable {
    typealias Antwort = (status: Int, json: String)
    private let antworten: [String: Antwort]
    private let lock = NSLock()
    private(set) var anfragen: [HTTPRequest] = []

    init(_ antworten: [String: Antwort]) {
        self.antworten = antworten
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        lock.withLock { anfragen.append(request) }
        guard let antwort = antworten[operationID] else {
            throw URLError(.cannotConnectToHost)
        }
        var response = HTTPResponse(status: .init(code: antwort.status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(antwort.json))
    }
}

@Suite("ImmichClient")
struct ImmichClientTests {
    let adresse = ServerAddress(eingabe: "foto.example.de")!

    static let features = """
    {"smartSearch":true,"facialRecognition":true,"duplicateDetection":true,"map":true,"reverseGeocoding":true,
     "importFaces":true,"sidecar":true,"search":true,"trash":true,"oauth":false,"oauthAutoLaunch":false,"ocr":true,
     "passwordLogin":true,"configFile":false,"email":true,"realtimeTranscoding":false}
    """

    @Test("Erkennt einen passenden Server mit Fähigkeiten")
    func serverInfo() async throws {
        let transport = MockTransport([
            "pingServer": (200, #"{"res":"pong"}"#),
            "getServerVersion": (200, #"{"major":3,"minor":3,"patch":5,"prerelease":null}"#),
            "getServerFeatures": (200, Self.features),
        ])
        let info = try await ImmichClient(address: adresse, transport: transport).serverInfo()
        #expect(info.version == ServerVersion(major: 3, minor: 3, patch: 5))
        #expect(info.capabilities.smartSearch)
        #expect(info.capabilities.passwordLogin)
        #expect(!info.capabilities.oauth)
    }

    @Test("Lehnt zu alte Server ab")
    func zuAlt() async {
        let transport = MockTransport([
            "pingServer": (200, #"{"res":"pong"}"#),
            "getServerVersion": (200, #"{"major":2,"minor":7,"patch":5}"#),
        ])
        await #expect(throws: ImmichError.versionZuAlt(.init(major: 2, minor: 7, patch: 5))) {
            try await ImmichClient(address: adresse, transport: transport).serverInfo()
        }
    }

    @Test("Meldet nicht erreichbare Server")
    func nichtErreichbar() async {
        let client = ImmichClient(address: adresse, transport: MockTransport([:]))
        await #expect {
            try await client.serverInfo()
        } throws: { error in
            if case ImmichError.nichtErreichbar = error { return true }
            return false
        }
    }

    @Test("Login liefert Token und Nutzer")
    func login() async throws {
        let transport = MockTransport([
            "login": (201, """
            {"accessToken":"abc123","userId":"u1","userEmail":"tim@example.de","name":"Tim",
             "isAdmin":true,"isOnboarded":true,"profileImagePath":"","shouldChangePassword":false}
            """),
        ])
        let (credential, user) = try await ImmichClient(address: adresse, transport: transport)
            .login(email: "tim@example.de", password: "geheim")
        #expect(credential == .accessToken("abc123"))
        #expect(user == ImmichUser(id: "u1", email: "tim@example.de", name: "Tim", isAdmin: true))
    }

    @Test("Falsches Passwort ergibt verständlichen Fehler")
    func falschesPasswort() async {
        let transport = MockTransport([
            "login": (401, #"{"message":"Incorrect email or password","statusCode":401}"#),
        ])
        await #expect(throws: ImmichError.falscheZugangsdaten) {
            try await ImmichClient(address: adresse, transport: transport).login(email: "a@b.de", password: "x")
        }
    }

    @Test("API-Key wird als Header gesendet, abgelaufene Sitzung erkannt")
    func apiKeyHeader() async throws {
        let transport = MockTransport(["getMyUser": (401, #"{"message":"Invalid API key"}"#)])
        let client = ImmichClient(address: adresse, credential: .apiKey("key-1"), transport: transport)
        await #expect(throws: ImmichError.sitzungAbgelaufen) { try await client.currentUser() }
        let anfrage = try #require(transport.anfragen.first)
        #expect(anfrage.headerFields[HTTPField.Name("x-api-key")!] == "key-1")
    }
}
