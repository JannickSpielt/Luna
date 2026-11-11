import Foundation

/// Version eines Immich-Servers.
public struct ServerVersion: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Älteste Version, die Lilith unterstützt.
    public static let minimum = ServerVersion(major: 3, minor: 0, patch: 0)

    public var description: String { "v\(major).\(minor).\(patch)" }

    public static func < (a: ServerVersion, b: ServerVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

/// Was der Server kann. Danach blendet die App Funktionen ein oder aus.
public struct ServerCapabilities: Hashable, Codable, Sendable {
    public var smartSearch: Bool
    public var trash: Bool
    public var map: Bool
    public var facialRecognition: Bool
    public var duplicateDetection: Bool
    public var ocr: Bool
    public var oauth: Bool
    public var passwordLogin: Bool

    public init(smartSearch: Bool = false, trash: Bool = false, map: Bool = false,
                facialRecognition: Bool = false, duplicateDetection: Bool = false, ocr: Bool = false,
                oauth: Bool = false, passwordLogin: Bool = true) {
        self.smartSearch = smartSearch
        self.trash = trash
        self.map = map
        self.facialRecognition = facialRecognition
        self.duplicateDetection = duplicateDetection
        self.ocr = ocr
        self.oauth = oauth
        self.passwordLogin = passwordLogin
    }
}

/// Ergebnis der Verbindungsprüfung.
public struct ServerInfo: Hashable, Codable, Sendable {
    public let address: ServerAddress
    public let version: ServerVersion
    public let capabilities: ServerCapabilities

    public init(address: ServerAddress, version: ServerVersion, capabilities: ServerCapabilities) {
        self.address = address
        self.version = version
        self.capabilities = capabilities
    }
}
