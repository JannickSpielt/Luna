#if canImport(Photos)
import CryptoKit
import Foundation
import Persistence
import Photos

/// Die echte Fotomediathek über PhotoKit.
public struct FotoMediathek: Mediathek {
    public init() {}

    public func zugriff() -> MediathekZugriff {
        Self.uebersetze(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func frageZugriff() async -> MediathekZugriff {
        Self.uebersetze(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    static func uebersetze(_ status: PHAuthorizationStatus) -> MediathekZugriff {
        switch status {
        case .authorized: .voll
        case .limited: .eingeschraenkt
        case .notDetermined: .unbekannt
        default: .verweigert
        }
    }

    public func alleMedien() async throws -> [MediumKopf] {
        let optionen = PHFetchOptions()
        // Nur die eigene Mediathek, keine geteilten Alben.
        optionen.includeAssetSourceTypes = [.typeUserLibrary]
        optionen.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                         PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let ergebnis = PHAsset.fetchAssets(with: optionen)
        var medien: [MediumKopf] = []
        medien.reserveCapacity(ergebnis.count)
        ergebnis.enumerateObjects { asset, _, _ in
            let erstellt = asset.creationDate ?? .distantPast
            medien.append(MediumKopf(id: asset.localIdentifier, erstellt: erstellt,
                                     geaendert: asset.modificationDate ?? erstellt,
                                     istVideo: asset.mediaType == .video))
        }
        return medien
    }

    public func pruefsumme(_ id: String) async throws -> String {
        let (_, quelle, _) = try Self.ressourcen(id)
        let rechner = Rechner()
        let optionen = PHAssetResourceRequestOptions()
        // Originale nur in iCloud werden in dieser Etappe nicht geladen.
        optionen.isNetworkAccessAllowed = false
        try await withCheckedThrowingContinuation { (fortsetzen: CheckedContinuation<Void, any Error>) in
            PHAssetResourceManager.default().requestData(for: quelle, options: optionen) { daten in
                rechner.fuege(daten)
            } completionHandler: { fehler in
                if let fehler { fortsetzen.resume(throwing: Self.uebersetze(fehler)) } else { fortsetzen.resume() }
            }
        }
        return rechner.ergebnis()
    }

    public func exportiere(_ id: String, nach ordner: URL) async throws -> ExportiertesMedium {
        let (asset, quelle, live) = try Self.ressourcen(id)
        let optionen = PHAssetResourceRequestOptions()
        optionen.isNetworkAccessAllowed = false
        let name = Self.dateiname(asset: asset, quelle: quelle)
        let datei = ordner.appending(path: name)
        do {
            try await PHAssetResourceManager.default().writeData(for: quelle, toFile: datei, options: optionen)
            var video: URL?
            if let live {
                let ziel = ordner.appending(path: (name as NSString).deletingPathExtension + "_live." +
                                            ((live.originalFilename as NSString).pathExtension.isEmpty ? "mov" : (live.originalFilename as NSString).pathExtension))
                try await PHAssetResourceManager.default().writeData(for: live, toFile: ziel, options: optionen)
                video = ziel
            }
            let dauer = asset.mediaType == .video ? Int((asset.duration * 1000).rounded()) : nil
            return ExportiertesMedium(datei: datei, dateiname: name, dauerMs: dauer, liveVideo: video)
        } catch {
            throw Self.uebersetze(error)
        }
    }

    // MARK: - Hilfen

    /// Das Foto, die Datei der aktuellen Version und bei Live Photos das Video.
    static func ressourcen(_ id: String) throws -> (PHAsset, PHAssetResource, PHAssetResource?) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw MediathekFehler.nichtGefunden
        }
        let alle = PHAssetResource.assetResources(for: asset)
        func erste(_ typen: [PHAssetResourceType]) -> PHAssetResource? {
            for typ in typen { if let r = alle.first(where: { $0.type == typ }) { return r } }
            return nil
        }
        let quelle: PHAssetResource?
        var live: PHAssetResource?
        switch asset.mediaType {
        case .video:
            quelle = erste([.fullSizeVideo, .video])
        case .image:
            quelle = erste([.fullSizePhoto, .photo])
            if asset.mediaSubtypes.contains(.photoLive) {
                live = erste([.fullSizePairedVideo, .pairedVideo])
            }
        default:
            quelle = nil
        }
        guard let quelle else { throw MediathekFehler.nichtUnterstuetzt }
        return (asset, quelle, live)
    }

    /// Originaler Dateiname, bei bearbeiteten Fotos mit der Endung der bearbeiteten Datei
    /// (statt „FullSizeRender.jpg“).
    static func dateiname(asset: PHAsset, quelle: PHAssetResource) -> String {
        let original = PHAssetResource.assetResources(for: asset)
            .first { $0.type == .photo || $0.type == .video }?.originalFilename ?? quelle.originalFilename
        let endung = (quelle.originalFilename as NSString).pathExtension
        let basis = (original as NSString).deletingPathExtension
        return endung.isEmpty ? original : "\(basis).\(endung)"
    }

    static func uebersetze(_ fehler: any Error) -> any Error {
        let ns = fehler as NSError
        if ns.domain == PHPhotosErrorDomain, ns.code == PHPhotosError.Code.networkAccessRequired.rawValue {
            return MediathekFehler.nurInICloud
        }
        return fehler
    }

    /// SHA1 stückweise, aus PhotoKits Rückruf-Thread.
    private final class Rechner: @unchecked Sendable {
        private var sha = Insecure.SHA1()
        private let sperre = NSLock()
        func fuege(_ daten: Data) { sperre.withLock { sha.update(data: daten) } }
        func ergebnis() -> String { sperre.withLock { Data(sha.finalize()).base64EncodedString() } }
    }
}
#endif
