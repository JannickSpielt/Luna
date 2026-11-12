import Foundation
import ImmichAPI
import OpenAPIRuntime
import OpenAPIURLSession

/// Der angemeldete Nutzer.
public struct ImmichUser: Hashable, Codable, Sendable {
    public let id: String
    public let email: String
    public let name: String
    public let isAdmin: Bool

    public init(id: String, email: String, name: String, isAdmin: Bool) {
        self.id = id
        self.email = email
        self.name = name
        self.isAdmin = isAdmin
    }
}

/// Fassade vor dem generierten API-Code. Nur hier sieht die App die Immich-API,
/// damit Änderungen an der API an genau einer Stelle aufgefangen werden.
public struct ImmichClient: Sendable {
    public let address: ServerAddress
    let credential: Credential?
    let client: ImmichAPI.Client
    /// Für Uploads, die direkt über `URLSession` laufen (Datei statt Speicher, mit Fortschritt).
    let uploadSession: URLSession

    /// Standard-Session für Uploads: lange Zeitgrenze, weil große Videos dauern.
    static let standardUploadSession: URLSession = {
        let konfiguration = URLSessionConfiguration.default
        konfiguration.timeoutIntervalForRequest = 600
        konfiguration.timeoutIntervalForResource = 24 * 3600
        return URLSession(configuration: konfiguration)
    }()

    /// - Parameter transport: Für Tests austauschbar, sonst `URLSession`.
    /// - Parameter uploadSession: Für Tests austauschbar.
    public init(address: ServerAddress, credential: Credential? = nil, transport: (any ClientTransport)? = nil,
                uploadSession: URLSession? = nil) {
        self.address = address
        self.credential = credential
        self.uploadSession = uploadSession ?? Self.standardUploadSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        self.client = ImmichAPI.Client(
            serverURL: address.apiURL,
            configuration: .init(dateTranscoder: ImmichDatum()),
            transport: transport ?? URLSessionTransport(configuration: .init(session: URLSession(configuration: configuration))),
            middlewares: [AuthMiddleware(credential: credential)]
        )
    }

    /// Dieselbe Verbindung mit anderen Zugangsdaten.
    public func with(credential: Credential?, transport: (any ClientTransport)? = nil) -> ImmichClient {
        ImmichClient(address: address, credential: credential, transport: transport)
    }

    // MARK: - Server

    /// Prüft, ob unter der Adresse ein passender Immich-Server antwortet.
    public func serverInfo() async throws -> ServerInfo {
        let ping: Operations.PingServer.Output
        do {
            ping = try await client.pingServer()
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        guard case .ok(let ok) = ping, (try? ok.body.json.res) == "pong" else {
            throw ImmichError.keinImmichServer
        }

        let versionDto = try await rufe { try await client.getServerVersion().ok.body.json }
        let version = ServerVersion(major: versionDto.major, minor: versionDto.minor, patch: versionDto.patch)
        guard version >= .minimum else { throw ImmichError.versionZuAlt(version) }

        // Seit v3.2 als veraltet markiert. Der Nachfolger /public/config liefert aber
        // (Stand v3.3.5) nur OAuth und Passwort-Login, nicht Smart Search, Papierkorb usw.
        // Deshalb bleibt dieser Aufruf, bis Immich einen vollständigen Ersatz hat.
        let f = try await rufe { try await client.getServerFeatures().ok.body.json }
        let capabilities = ServerCapabilities(
            smartSearch: f.smartSearch, trash: f.trash, map: f.map,
            facialRecognition: f.facialRecognition, duplicateDetection: f.duplicateDetection,
            ocr: f.ocr, oauth: f.oauth, passwordLogin: f.passwordLogin
        )
        return ServerInfo(address: address, version: version, capabilities: capabilities)
    }

    // MARK: - Anmeldung

    /// Meldet sich mit E-Mail und Passwort an und gibt das Token zurück.
    public func login(email: String, password: String) async throws -> (Credential, ImmichUser) {
        let output: Operations.Login.Output
        do {
            output = try await client.login(body: .json(.init(email: email, password: password)))
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        switch output {
        case .created(let created):
            let dto = try await rufe { try created.body.json }
            let user = ImmichUser(id: dto.userId, email: dto.userEmail, name: dto.name, isAdmin: dto.isAdmin)
            return (.accessToken(dto.accessToken), user)
        case .undocumented(statusCode: 401, _), .undocumented(statusCode: 400, _):
            throw ImmichError.falscheZugangsdaten
        case .undocumented(let code, _):
            throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Lädt den angemeldeten Nutzer. Dient auch zum Prüfen von Token und API-Key.
    public func currentUser() async throws -> ImmichUser {
        let output: Operations.GetMyUser.Output
        do {
            output = try await client.getMyUser()
        } catch {
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        }
        switch output {
        case .ok(let ok):
            let dto = try await rufe { try ok.body.json }
            return ImmichUser(id: dto.id, email: dto.email, name: dto.name, isAdmin: dto.isAdmin)
        case .undocumented(statusCode: 401, _):
            throw ImmichError.sitzungAbgelaufen
        case .undocumented(let code, _):
            throw ImmichError.unerwarteteAntwort(code)
        }
    }

    /// Meldet sich ab. Fehler werden ignoriert: lokal wird ohnehin abgemeldet.
    public func logout() async {
        _ = try? await client.logout()
    }

    // MARK: - Hilfen

    /// Führt einen Aufruf aus und übersetzt Fehler in `ImmichError`.
    func rufe<T>(_ block: () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch let error as ImmichError {
            throw error
        } catch let error as ClientError {
            if let code = (error.response?.status.code) { throw code == 401 ? ImmichError.sitzungAbgelaufen : ImmichError.unerwarteteAntwort(code) }
            throw ImmichError.nichtErreichbar(Self.kurzerGrund(error))
        } catch {
            throw ImmichError.keinImmichServer
        }
    }

    static func kurzerGrund(_ error: any Error) -> String {
        let underlying = (error as? ClientError)?.underlyingError ?? error
        if let url = underlying as? URLError {
            switch url.code {
            case .timedOut: return "Zeitüberschreitung"
            case .cannotFindHost, .dnsLookupFailed: return "Adresse nicht gefunden"
            case .cannotConnectToHost: return "Verbindung abgelehnt"
            case .notConnectedToInternet: return "Keine Internetverbindung"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .secureConnectionFailed:
                return "Zertifikat nicht vertrauenswürdig"
            default: return url.localizedDescription
            }
        }
        return underlying.localizedDescription
    }
}
