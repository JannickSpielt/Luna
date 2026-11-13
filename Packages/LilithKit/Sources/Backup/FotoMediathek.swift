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

    public func pruefsumme(_ id: String, iCloud: Bool) async throws -> String {
        let (_, quelle, _) = try Self.ressourcen(id)
        let rechner = Rechner()
        let optionen = PHAssetResourceRequestOptions()
        // Liegt das Original nur in iCloud, wird es (falls erlaubt) dafür geladen.
        optionen.isNetworkAccessAllowed = iCloud
        try await withCheckedThrowingContinuation { (fortsetzen: CheckedContinuation<Void, any Error>) in
            PHAssetResourceManager.default().requestData(for: quelle, options: optionen) { daten in
                rechner.fuege(daten)
            } completionHandler: { fehler in
                if let fehler { fortsetzen.resume(throwing: Self.uebersetze(fehler)) } else { fortsetzen.resume() }
            }
        }
        return rechner.ergebnis()
    }

    public func exportiere(_ id: String, nach ordner: URL, iCloud: Bool) async throws -> ExportiertesMedium {
        let (asset, quelle, live) = try Self.ressourcen(id)
        let optionen = PHAssetResourceRequestOptions()
        optionen.isNetworkAccessAllowed = iCloud
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

    // MARK: - Alben

    public func alben() async -> [MediathekAlbum] {
        var ergebnis: [MediathekAlbum] = []
        // Von iOS: nur sinnvolle Sammlungen, keine „Zuletzt gelöscht“ oder „Ausgeblendet“.
        let vonIOS: [PHAssetCollectionSubtype] = [.smartAlbumFavorites, .smartAlbumScreenshots, .smartAlbumSelfPortraits,
                                                  .smartAlbumVideos, .smartAlbumLivePhotos, .smartAlbumPanoramas,
                                                  .smartAlbumBursts, .smartAlbumSlomoVideos, .smartAlbumTimelapses,
                                                  .smartAlbumDepthEffect, .smartAlbumRAW]
        for typ in vonIOS {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: typ, options: nil).enumerateObjects { c, _, _ in
                if let a = Self.album(c, vonIOS: true) { ergebnis.append(a) }
            }
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { c, _, _ in
            if let a = Self.album(c, vonIOS: false) { ergebnis.append(a) }
        }
        return ergebnis
    }

    static func album(_ c: PHAssetCollection, vonIOS: Bool) -> MediathekAlbum? {
        let inhalt = PHAsset.fetchAssets(in: c, options: Self.nurMedien())
        guard inhalt.count > 0 else { return nil }
        return MediathekAlbum(id: c.localIdentifier, titel: c.localizedTitle ?? "Album", anzahl: inhalt.count,
                              vonIOS: vonIOS, titelBildId: inhalt.lastObject?.localIdentifier)
    }

    public func medienIds(inAlbum id: String) async -> Set<String> {
        guard let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
        var ids = Set<String>()
        PHAsset.fetchAssets(in: c, options: Self.nurMedien()).enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
        return ids
    }

    public func loesche(_ ids: [String]) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    public func vorschau(_ id: String, kante: CGFloat) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let optionen = PHImageRequestOptions()
        optionen.deliveryMode = .highQualityFormat
        optionen.resizeMode = .fast
        optionen.isNetworkAccessAllowed = true
        let groesse = CGSize(width: kante, height: kante)
        return await withCheckedContinuation { fortsetzen in
            PHImageManager.default().requestImage(for: asset, targetSize: groesse, contentMode: .aspectFill,
                                                  options: optionen) { bild, _ in
                #if os(iOS)
                fortsetzen.resume(returning: bild?.cgImage)
                #else
                // Auf dem Mac gibt es kein automatisches Backup.
                _ = bild
                fortsetzen.resume(returning: nil)
                #endif
            }
        }
    }

    static func nurMedien() -> PHFetchOptions {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                  PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return o
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
