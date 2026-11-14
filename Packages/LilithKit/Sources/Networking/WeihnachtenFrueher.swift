import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein früheres Weihnachten (24. bis 26. Dezember eines Jahres) mit Titelbild.
public struct WeihnachtsJahr: Identifiable, Hashable, Sendable {
    public let jahr: Int
    public let anzahl: Int
    public let titelBildId: String
    public var id: Int { jahr }

    public init(jahr: Int, anzahl: Int, titelBildId: String) {
        self.jahr = jahr; self.anzahl = anzahl; self.titelBildId = titelBildId
    }
}

extension ImmichClient {
    /// Die Jahre, deren Weihnachten schon vorbei ist und in deren Dezember es Fotos gibt (neuestes zuerst).
    /// Ab dem 27. Dezember zählt auch das laufende Jahr.
    public static func weihnachtsJahre(_ monate: [TimelineMonat], heute: Date, kalender: Calendar = .current) -> [Int] {
        let t = kalender.dateComponents([.year, .month, .day], from: heute)
        guard let jetzt = t.year else { return [] }
        let vorbei = t.month == 12 && (t.day ?? 0) >= 27
        let bisJahr = vorbei ? jetzt : jetzt - 1
        let jahre = monate.compactMap { m -> Int? in
            guard m.anzahl > 0, let jm = m.jahrMonat, jm.monat == 12, jm.jahr <= bisJahr else { return nil }
            return jm.jahr
        }
        return Array(Set(jahre)).sorted(by: >)
    }

    /// Fotos und Videos vom 24. bis 26. Dezember früherer Jahre, neueste zuerst.
    /// Mit `jahr` nur aus diesem einen Jahr.
    public func weihnachtsFotos(jahr: Int? = nil, heute: Date = .now) async throws -> [TimelineAsset] {
        let jahre: [Int]
        if let jahr {
            jahre = [jahr]
        } else {
            jahre = Self.weihnachtsJahre(try await timelineMonate(.alle), heute: heute)
        }
        guard !jahre.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: [TimelineAsset].self) { gruppe in
            for j in jahre {
                gruppe.addTask { try await self.fotosZuWeihnachten(j) }
            }
            var alle: [TimelineAsset] = []
            for try await teil in gruppe { alle += teil }
            return alle.sorted { ($0.erstellt ?? .distantPast) > ($1.erstellt ?? .distantPast) }
        }
    }

    /// Je früherem Weihnachten eine Karte (für die Sammlungen).
    public func weihnachtsJahreMitBild(heute: Date = .now) async throws -> [WeihnachtsJahr] {
        Self.gruppiereNachJahr(try await weihnachtsFotos(heute: heute)).map { jahr, fotos in
            // Titelbild: lieber ein Foto als ein Video, sonst das erste.
            let titel = fotos.first(where: \.istBild) ?? fotos[0]
            return WeihnachtsJahr(jahr: jahr, anzahl: fotos.count, titelBildId: titel.id)
        }
    }

    /// Fotos nach Aufnahmejahr gruppiert, neuestes Jahr zuerst; die Reihenfolge innerhalb bleibt.
    public static func gruppiereNachJahr(_ fotos: [TimelineAsset], kalender: Calendar = .current) -> [(jahr: Int, fotos: [TimelineAsset])] {
        var jeJahr: [Int: [TimelineAsset]] = [:]
        for f in fotos {
            guard let d = f.erstellt else { continue }
            jeJahr[kalender.component(.year, from: d), default: []].append(f)
        }
        return jeJahr.keys.sorted(by: >).map { ($0, jeJahr[$0]!) }
    }

    private func fotosZuWeihnachten(_ jahr: Int) async throws -> [TimelineAsset] {
        let kalender = Calendar.current
        guard let von = kalender.date(from: DateComponents(year: jahr, month: 12, day: 24)),
              let bis = kalender.date(from: DateComponents(year: jahr, month: 12, day: 27)) else { return [] }
        let output: Operations.SearchAssets.Output
        do {
            output = try await client.searchAssets(body: .json(.init(
                size: 1000, takenAfter: von, takenBefore: bis, visibility: .timeline)))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.assets.items
                .filter { !$0.isTrashed }
                .map(Self.timelineAsset)
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }
}
