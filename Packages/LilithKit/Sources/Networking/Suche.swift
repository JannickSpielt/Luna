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

    /// Was in den letzten Tagen auf den Server kam, nach Hochladezeit sortiert (neueste zuerst).
    /// Immich kann nicht nach Hochladezeit sortieren, nur danach filtern: Lilith sortiert selbst.
    public func kuerzlichHinzugefuegt(tage: Int = 30, anzahl: Int = 1000) async throws -> [TimelineAsset] {
        let ab = Date.now.addingTimeInterval(-Double(tage) * 86_400)
        let output: Operations.SearchAssets.Output
        do {
            output = try await client.searchAssets(body: .json(.init(
                createdAfter: ab, size: min(max(anzahl, 1), 1000), visibility: .timeline)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.assets.items
                .filter { !$0.isTrashed }
                .sorted { $0.createdAt > $1.createdAt }
                .map(Self.timelineAsset)
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Kürzlich Hochgeladenes nach Tagen (neuester Tag zuerst): Tag, Anzahl und das neueste Foto als Titelbild.
    public func kuerzlichNachTagen(tage: Int = 30) async throws -> [HochladeTag] {
        let ab = Date.now.addingTimeInterval(-Double(tage) * 86_400)
        let output: Operations.SearchAssets.Output
        do {
            output = try await client.searchAssets(body: .json(.init(createdAfter: ab, size: 1000, visibility: .timeline)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            let items = try await rufe { try ok.body.json }.assets.items.filter { !$0.isTrashed }
            let kalender = Calendar.current
            var tage: [Date: (anzahl: Int, neuestes: Components.Schemas.AssetResponseDto)] = [:]
            for d in items {
                let tag = kalender.startOfDay(for: d.createdAt)
                if let alt = tage[tag] {
                    tage[tag] = (alt.anzahl + 1, d.createdAt > alt.neuestes.createdAt ? d : alt.neuestes)
                } else {
                    tage[tag] = (1, d)
                }
            }
            return tage.map { HochladeTag(tag: $0.key, anzahl: $0.value.anzahl, titelBildId: $0.value.neuestes.id) }
                .sorted { $0.tag > $1.tag }
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

/// Ein Tag, an dem Fotos auf den Server kamen.
public struct HochladeTag: Hashable, Sendable, Identifiable, Codable {
    public let tag: Date
    public let anzahl: Int
    public let titelBildId: String
    public var id: Date { tag }
}
