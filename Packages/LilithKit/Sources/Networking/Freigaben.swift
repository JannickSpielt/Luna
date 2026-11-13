import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein Freigabe-Link: Wer ihn hat, sieht die Fotos auch ohne Konto (Immich „Shared Link“).
public struct Freigabe: Identifiable, Hashable, Sendable {
    public let id: String
    public let link: URL
    /// Albumname oder „N Fotos“.
    public let titel: String
    public let ablauf: Date?
    public let mitPasswort: Bool
    public let erlaubtDownload: Bool
    public let erstellt: Date

    public init(id: String, link: URL, titel: String, ablauf: Date?, mitPasswort: Bool, erlaubtDownload: Bool, erstellt: Date) {
        self.id = id; self.link = link; self.titel = titel; self.ablauf = ablauf
        self.mitPasswort = mitPasswort; self.erlaubtDownload = erlaubtDownload; self.erstellt = erstellt
    }

    public var abgelaufen: Bool { ablauf.map { $0 < .now } ?? false }
}

extension ImmichClient {
    /// Legt einen Freigabe-Link für ein Album oder einzelne Fotos an.
    public func erstelleFreigabe(album: String? = nil, fotos: [String] = [], ablauf: Date?, passwort: String?,
                                 download: Bool) async throws -> Freigabe {
        var dto = Components.Schemas.SharedLinkCreateDto(_type: album != nil ? .album : .individual)
        dto.albumId = album
        dto.assetIds = album == nil ? fotos : nil
        dto.expiresAt = ablauf
        dto.password = passwort?.isEmpty == false ? passwort : nil
        dto.allowDownload = download
        dto.showMetadata = true
        let output: Operations.CreateSharedLink.Output
        do { output = try await client.createSharedLink(body: .json(dto)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .created(let c): return freigabe(try await rufe { try c.body.json })
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Alle eigenen Freigabe-Links, neueste zuerst.
    public func freigaben() async throws -> [Freigabe] {
        let output: Operations.GetAllSharedLinks.Output
        do { output = try await client.getAllSharedLinks() } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok): return try await rufe { try ok.body.json }.map(freigabe).sorted { $0.erstellt > $1.erstellt }
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Link löschen: Danach öffnet er nichts mehr. Die Fotos bleiben unberührt.
    public func loescheFreigabe(_ id: String) async throws {
        let output: Operations.RemoveSharedLink.Output
        do { output = try await client.removeSharedLink(path: .init(id: id)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .noContent: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    private func freigabe(_ d: Components.Schemas.SharedLinkResponseDto) -> Freigabe {
        // Immich-Web zeigt Freigaben unter /share/<key> (mit eigenem Kurznamen unter /s/<slug>).
        let link = d.slug.map { address.url.appending(path: "s").appending(path: $0) }
            ?? address.url.appending(path: "share").appending(path: d.key)
        let titel = d.album?.albumName ?? (d.assets.count == 1 ? "1 Foto" : "\(d.assets.count) Fotos")
        return Freigabe(id: d.id, link: link, titel: titel, ablauf: d.expiresAt, mitPasswort: d.password != nil,
                        erlaubtDownload: d.allowDownload, erstellt: d.createdAt)
    }
}
