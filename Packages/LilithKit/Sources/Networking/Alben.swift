import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Welcher Ausschnitt der Bibliothek gezeigt wird.
public enum TimelineFilter: Hashable, Sendable {
    case alle
    case favoriten
    case archiv
    case papierkorb
    case album(String)
}

/// Ein Album.
public struct Album: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var anzahl: Int
    public var coverAssetId: String?
    public var geteilt: Bool
    public var von: Date?
    public var bis: Date?

    public init(id: String, name: String, anzahl: Int, coverAssetId: String? = nil, geteilt: Bool = false,
                von: Date? = nil, bis: Date? = nil) {
        self.id = id; self.name = name; self.anzahl = anzahl; self.coverAssetId = coverAssetId
        self.geteilt = geteilt; self.von = von; self.bis = bis
    }
}

extension ImmichClient {
    static func album(_ d: Components.Schemas.AlbumResponseDto) -> Album {
        Album(id: d.id, name: d.albumName, anzahl: d.assetCount, coverAssetId: d.albumThumbnailAssetId,
              geteilt: d.shared, von: d.startDate, bis: d.endDate)
    }

    /// Alle Alben, eigene und mit mir geteilte, nach Name sortiert.
    public func alben() async throws -> [Album] {
        let output: Operations.GetAllAlbums.Output
        do { output = try await client.getAllAlbums() } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.map(Self.album)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Legt ein Album an, auf Wunsch gleich mit Fotos.
    public func erstelleAlbum(name: String, assetIds: [String] = []) async throws -> Album {
        let output: Operations.CreateAlbum.Output
        do {
            output = try await client.createAlbum(body: .json(.init(albumName: name, assetIds: assetIds.isEmpty ? nil : assetIds)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .created(let created): return Self.album(try await rufe { try created.body.json })
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Fügt Fotos zu einem Album hinzu. Gibt zurück, wie viele neu dazukamen (schon enthaltene zählen nicht).
    @discardableResult
    public func fuegeZuAlbum(albumId: String, assetIds: [String]) async throws -> Int {
        let output: Operations.AddAssetsToAlbum.Output
        do {
            output = try await client.addAssetsToAlbum(path: .init(id: albumId), body: .json(.init(ids: assetIds)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok): return try await rufe { try ok.body.json }.filter(\.success).count
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Setzt bei mehreren Fotos Favorit und/oder Archiv.
    public func aendere(assetIds: [String], favorit: Bool? = nil, archiviert: Bool? = nil) async throws {
        guard !assetIds.isEmpty else { return }
        let output: Operations.UpdateAssets.Output
        do {
            // In v3 als veraltet markiert, der Nachfolger existiert in v3.3.5 aber noch nicht.
            output = try await client.updateAssets(body: .json(.init(
                ids: assetIds, isFavorite: favorit,
                visibility: archiviert.map { $0 ? .archive : .timeline })))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .noContent: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Legt Fotos in den Papierkorb. `endgueltig` löscht sie sofort und unwiderruflich.
    public func loesche(assetIds: [String], endgueltig: Bool = false) async throws {
        guard !assetIds.isEmpty else { return }
        let output: Operations.DeleteAssets.Output
        do {
            output = try await client.deleteAssets(body: .json(.init(force: endgueltig, ids: assetIds)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .noContent: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Holt Fotos aus dem Papierkorb zurück.
    public func stelleWiederHer(assetIds: [String]) async throws {
        guard !assetIds.isEmpty else { return }
        let output: Operations.RestoreAssets.Output
        do {
            output = try await client.restoreAssets(body: .json(.init(ids: assetIds)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    static func fehler(_ code: Int) -> ImmichError {
        code == 401 ? .sitzungAbgelaufen : .unerwarteteAntwort(code)
    }
}
