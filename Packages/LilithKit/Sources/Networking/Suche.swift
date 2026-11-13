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

/// Fotos vom heutigen Kalendertag in einem früheren Jahr.
public struct Rueckblick: Identifiable, Hashable, Sendable, Codable {
    /// Wie viele Jahre zurück.
    public let jahreZurueck: Int
    /// Der Tag damals (Beginn, Ortszeit).
    public let tag: Date
    public let anzahl: Int
    public let titelBildId: String
    public var id: Int { jahreZurueck }

    public init(jahreZurueck: Int, tag: Date, anzahl: Int, titelBildId: String) {
        self.jahreZurueck = jahreZurueck; self.tag = tag; self.anzahl = anzahl; self.titelBildId = titelBildId
    }
}

extension ImmichClient {
    /// „Heute vor … Jahren“: für jedes frühere Jahr die Fotos vom selben Tag (bis `jahre` zurück).
    public func rueckblicke(heute: Date = .now, jahre: Int = 20) async throws -> [Rueckblick] {
        let kalender = Calendar.current
        let start = kalender.startOfDay(for: heute)
        return try await withThrowingTaskGroup(of: Rueckblick?.self) { gruppe in
            for n in 1...jahre {
                guard let tag = kalender.date(byAdding: .year, value: -n, to: start) else { continue }
                gruppe.addTask {
                    let fotos = try await self.fotos(amTag: tag, hoechstens: 200)
                    guard let erstes = fotos.first else { return nil }
                    return Rueckblick(jahreZurueck: n, tag: tag, anzahl: fotos.count, titelBildId: erstes.id)
                }
            }
            var ergebnis: [Rueckblick] = []
            for try await r in gruppe { if let r { ergebnis.append(r) } }
            return ergebnis.sorted { $0.jahreZurueck < $1.jahreZurueck }
        }
    }

    /// Alle Fotos eines Tages (aufgenommen), neueste zuerst.
    public func fotos(amTag tag: Date, hoechstens: Int = 1000) async throws -> [TimelineAsset] {
        let kalender = Calendar.current
        let von = kalender.startOfDay(for: tag)
        guard let bis = kalender.date(byAdding: .day, value: 1, to: von) else { return [] }
        let output: Operations.SearchAssets.Output
        do {
            output = try await client.searchAssets(body: .json(.init(
                size: min(max(hoechstens, 1), 1000), takenAfter: von, takenBefore: bis, visibility: .timeline)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.assets.items
                .filter { !$0.isTrashed }
                .sorted { $0.fileCreatedAt > $1.fileCreatedAt }
                .map(Self.timelineAsset)
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }
}
