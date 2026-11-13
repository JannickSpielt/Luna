import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Ein Foto in einer Gruppe doppelter Fotos, mit dem, was beim Entscheiden hilft.
public struct DuplikatFoto: Identifiable, Hashable, Sendable {
    public let id: String
    public let dateiname: String
    public let bytes: Int?
    public let breite: Int?
    public let hoehe: Int?
    public let aufgenommen: Date
    public let istVideo: Bool

    public init(id: String, dateiname: String, bytes: Int?, breite: Int?, hoehe: Int?, aufgenommen: Date, istVideo: Bool) {
        self.id = id; self.dateiname = dateiname; self.bytes = bytes; self.breite = breite; self.hoehe = hoehe
        self.aufgenommen = aufgenommen; self.istVideo = istVideo
    }
}

/// Fotos, die Immich als (fast) gleich erkannt hat. `vorschlag`: welche Immich behalten würde.
public struct DuplikatGruppe: Identifiable, Hashable, Sendable {
    public let id: String
    public let fotos: [DuplikatFoto]
    public let vorschlag: Set<String>

    public init(id: String, fotos: [DuplikatFoto], vorschlag: Set<String>) {
        self.id = id; self.fotos = fotos; self.vorschlag = vorschlag
    }
}

extension ImmichClient {
    /// Alle Gruppen doppelter Fotos (Immich erkennt sie per Machine Learning).
    public func duplikate() async throws -> [DuplikatGruppe] {
        let output: Operations.GetAssetDuplicates.Output
        do { output = try await client.getAssetDuplicates() } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.map { g in
                DuplikatGruppe(
                    id: g.duplicateId,
                    fotos: g.assets.filter { !$0.isTrashed }.map {
                        DuplikatFoto(id: $0.id, dateiname: $0.originalFileName, bytes: $0.exifInfo?.fileSizeInByte,
                                     breite: $0.width, hoehe: $0.height, aufgenommen: $0.fileCreatedAt,
                                     istVideo: $0._type == .video)
                    },
                    vorschlag: Set(g.suggestedKeepAssetIds))
            }
            .filter { $0.fotos.count > 1 }
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Eine Gruppe auflösen: `behalten` bleiben, alle anderen kommen in den Papierkorb (wiederherstellbar).
    public func loeseDuplikat(_ gruppe: DuplikatGruppe, behalten: Set<String>) async throws {
        let weg = gruppe.fotos.map(\.id).filter { !behalten.contains($0) }
        let output: Operations.ResolveDuplicates.Output
        do {
            output = try await client.resolveDuplicates(body: .json(.init(groups: [
                .init(duplicateId: gruppe.id, keepAssetIds: Array(behalten), trashAssetIds: weg)
            ])))
        } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok: return
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Alle Ordner (Pfade auf dem Server), in denen Fotos liegen.
    public func ordnerPfade() async throws -> [String] {
        let output: Operations.GetUniqueOriginalPaths.Output
        do { output = try await client.getUniqueOriginalPaths() } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok): return try await rufe { try ok.body.json }.sorted()
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Fotos direkt in einem Ordner, neueste zuerst.
    public func fotos(imOrdner pfad: String) async throws -> [TimelineAsset] {
        let output: Operations.GetAssetsByOriginalPath.Output
        do { output = try await client.getAssetsByOriginalPath(query: .init(path: pfad)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }
                .filter { !$0.isTrashed }
                .sorted { $0.fileCreatedAt > $1.fileCreatedAt }
                .map(Self.timelineAsset)
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }
}

/// Baut aus flachen Ordnerpfaden eine Baumansicht.
public enum OrdnerBaum {
    /// Direkte Unterordner von `pfad` (`""` = oberste Ebene) mit der Anzahl ihrer Ordner darunter.
    public static func unterordner(von pfad: String, in alle: [String]) -> [(name: String, pfad: String)] {
        let praefix = pfad.isEmpty ? "" : (pfad.hasSuffix("/") ? pfad : pfad + "/")
        var namen: [String] = []
        var gesehen = Set<String>()
        for p in alle where p.hasPrefix(praefix) && p != pfad {
            let rest = p.dropFirst(praefix.count).drop { $0 == "/" }
            guard let name = rest.split(separator: "/").first.map(String.init), !name.isEmpty else { continue }
            if gesehen.insert(name).inserted { namen.append(name) }
        }
        let basis = pfad.isEmpty && alle.first?.hasPrefix("/") == true ? "/" : praefix
        return namen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { ($0, basis + $0) }
    }

    /// Längster gemeinsamer Ordner aller Pfade (z. B. „/usr/src/app/upload/library/admin“), damit die Ansicht
    /// nicht mit fünf leeren Ebenen beginnt.
    public static func gemeinsamerAnfang(_ alle: [String]) -> String {
        guard var teile = alle.first?.split(separator: "/", omittingEmptySubsequences: true).map(String.init) else { return "" }
        for p in alle.dropFirst() {
            let andere = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            var n = 0
            while n < min(teile.count, andere.count), teile[n] == andere[n] { n += 1 }
            teile = Array(teile.prefix(n))
        }
        // Liegen Fotos direkt im gemeinsamen Ordner, ist er selbst schon die richtige Ebene.
        let pfad = (alle.first?.hasPrefix("/") == true ? "/" : "") + teile.joined(separator: "/")
        return pfad == "/" ? "" : pfad
    }

    /// Liegen direkt in diesem Ordner Fotos?
    public static func hatFotos(_ pfad: String, in alle: [String]) -> Bool {
        alle.contains(pfad)
    }
}
