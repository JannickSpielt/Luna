import Foundation
import ImmichAPI
import OpenAPIRuntime

/// Medienarten in den Sammlungen. Videos und Live Photos kennt Immich direkt,
/// Selfies, Bildschirmfotos und RAW erkennt Luna an Objektiv- und Dateinamen.
public enum Medienart: String, Hashable, Sendable, CaseIterable {
    case videos, livePhotos, selfies, bildschirmfotos, raw

    public var titel: String {
        switch self {
        case .videos: "Videos"
        case .livePhotos: "Live Photos"
        case .selfies: "Selfies"
        case .bildschirmfotos: "Bildschirmfotos"
        case .raw: "RAW"
        }
    }

    public var symbol: String {
        switch self {
        case .videos: "video"
        case .livePhotos: "livephoto"
        case .selfies: "person.crop.square"
        case .bildschirmfotos: "camera.viewfinder"
        case .raw: "r.square"
        }
    }
}

/// Eine Person, die Immich auf Fotos erkannt hat.
public struct Person: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id; self.name = name
    }
}

extension ImmichClient {
    /// Fotos einer Medienart, neueste zuerst.
    /// Nutzt die einfachen Suchfelder (laufen auf allen Immich-Versionen). Was mehrere Abfragen braucht
    /// (mehrere Objektive, mehrere Dateiendungen), wird zusammengeführt.
    public func medien(_ art: Medienart, hoechstens: Int = 5000) async throws -> [TimelineAsset] {
        typealias S = Components.Schemas
        var abfragen: [S.MetadataSearchDto] = []
        func neu(_ setze: (inout S.MetadataSearchDto) -> Void) {
            var a = S.MetadataSearchDto()
            a.visibility = .timeline
            setze(&a)
            abfragen.append(a)
        }
        switch art {
        case .videos:
            neu { $0._type = .video }
        case .livePhotos:
            neu { $0.isMotion = true }
        case .selfies:
            // iPhones schreiben „front camera“ in den Objektivnamen. Welche es gibt, sagt der Server.
            for objektiv in try await objektive() where objektiv.localizedCaseInsensitiveContains("front") {
                neu { $0.lensModel = objektiv }
            }
        case .bildschirmfotos:
            // Bildschirmfotos speichert iOS als PNG. Der Dateiname wird als Teil gesucht.
            neu { $0._type = .image; $0.originalFileName = ".png" }
        case .raw:
            for endung in ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "srw"] {
                neu { $0.originalFileName = ".\(endung)" }
            }
        }
        var gesehen = Set<String>()
        var treffer: [S.AssetResponseDto] = []
        for var anfrage in abfragen {
            var seite = 1
            while treffer.count < hoechstens {
                anfrage.page = seite
                anfrage.size = 1000
                let output: Operations.SearchAssets.Output
                do { output = try await client.searchAssets(body: .json(anfrage)) } catch { throw Self.uebersetze(error) }
                switch output {
                case .ok(let ok):
                    let antwort = try await rufe { try ok.body.json }.assets
                    for d in antwort.items where !d.isTrashed && gesehen.insert(d.id).inserted {
                        // Teilsuche im Dateinamen: nur echte Endungen behalten (nicht „.png“ mitten im Namen).
                        if let gesucht = anfrage.originalFileName,
                           !d.originalFileName.lowercased().hasSuffix(gesucht.lowercased()) { continue }
                        treffer.append(d)
                    }
                    guard antwort.nextPage != nil, !antwort.items.isEmpty else { break }
                    seite += 1
                    continue
                case .undocumented(let code, _): throw Self.fehler(code)
                }
                break
            }
        }
        return treffer.sorted { $0.fileCreatedAt > $1.fileCreatedAt }.map(Self.timelineAsset)
    }

    /// Alle Objektivnamen der Bibliothek (für die Selfie-Erkennung).
    func objektive() async throws -> [String] {
        let output: Operations.GetSearchSuggestions.Output
        do { output = try await client.getSearchSuggestions(query: .init(_type: .cameraLensModel)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok): return try await rufe { try ok.body.json }
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Erkannte Personen, benannte zuerst (wie in Immich sortiert), ohne ausgeblendete.
    public func personen(anzahl: Int = 100) async throws -> [Person] {
        let output: Operations.GetAllPeople.Output
        do { output = try await client.getAllPeople(query: .init(size: anzahl, withHidden: false)) } catch { throw Self.uebersetze(error) }
        switch output {
        case .ok(let ok):
            return try await rufe { try ok.body.json }.people
                .filter { !$0.isHidden }
                .map { Person(id: $0.id, name: $0.name) }
        case .undocumented(let code, _): throw Self.fehler(code)
        }
    }

    /// Gesichtsbild einer Person, inklusive Anmeldung.
    public func personBildAnfrage(_ id: String) -> URLRequest {
        anfrage(["people", id, "thumbnail"])
    }
}
