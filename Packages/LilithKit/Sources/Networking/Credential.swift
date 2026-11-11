import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Womit sich Lilith beim Server ausweist.
public enum Credential: Hashable, Codable, Sendable {
    /// Token aus der Anmeldung mit E-Mail und Passwort.
    case accessToken(String)
    /// API-Key, in Immich unter Kontoeinstellungen erstellt.
    case apiKey(String)
}

/// Hängt die Zugangsdaten an jede Anfrage an.
struct AuthMiddleware: ClientMiddleware {
    let credential: Credential?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        switch credential {
        case .accessToken(let token):
            request.headerFields[.authorization] = "Bearer \(token)"
        case .apiKey(let key):
            request.headerFields[HTTPField.Name("x-api-key")!] = key
        case nil:
            break
        }
        return try await next(request, body, baseURL)
    }
}
