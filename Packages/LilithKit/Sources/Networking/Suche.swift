import Foundation
import ImmichAPI
import OpenAPIRuntime

extension ImmichClient {
    /// Smart Search: findet Fotos, die zu einer Beschreibung passen („Katze auf dem Sofa“).
    /// Die Treffer sind nach Relevanz sortiert. Braucht Machine Learning auf dem Server.
    public func sucheSmart(_ text: String, anzahl: Int = 500) async throws -> [TimelineAsset] {
        let output: Operations.SearchSmart.Output
        do {
            output = try await client.searchSmart(body: .json(.init(
                query: text, size: min(max(anzahl, 1), 1000), visibility: .timeline)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.assets.items.filter { !$0.isTrashed }.map(Self.timelineAsset)
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    static func timelineAsset(_ d: Components.Schemas.AssetResponseDto) -> TimelineAsset {
        let verhaeltnis: Double = {
            guard let b = d.width, let h = d.height, b > 0, h > 0 else { return 1 }
            return Double(b) / Double(h)
        }()
        return TimelineAsset(id: d.id, istBild: d._type != .video, dauerMs: d.duration, istFavorit: d.isFavorite,
                             livePhotoVideoId: d.livePhotoVideoId, seitenverhaeltnis: verhaeltnis,
                             thumbhash: d.thumbhash, stadt: d.exifInfo?.city)
    }
}
