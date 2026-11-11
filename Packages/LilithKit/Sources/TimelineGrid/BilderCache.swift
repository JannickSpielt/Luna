import Foundation
import Nuke

/// Gemeinsamer Bilder-Cache: Arbeitsspeicher plus bis zu 1 GB auf der Festplatte.
/// Einmal beim App-Start einrichten.
public enum BilderCache {
    public static let speicherLimitMB = 1024

    @MainActor
    public static func einrichten() {
        var konfiguration = ImagePipeline.Configuration.withDataCache(
            name: "app.lilith.vorschau", sizeLimit: speicherLimitMB * 1024 * 1024)
        konfiguration.isProgressiveDecodingEnabled = false
        konfiguration.dataLoadingQueue.maxConcurrentOperationCount = 8
        ImagePipeline.shared = ImagePipeline(configuration: konfiguration)
    }

    /// Anfrage für eine Kachel mit passender Größe (spart Speicher beim Dekodieren).
    static func anfrage(_ urlRequest: URLRequest, pixel: CGFloat) -> ImageRequest {
        ImageRequest(urlRequest: urlRequest,
                     processors: [.resize(size: CGSize(width: pixel, height: pixel), contentMode: .aspectFill, crop: true)])
    }
}
