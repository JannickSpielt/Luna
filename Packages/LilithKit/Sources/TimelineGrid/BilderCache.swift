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
        // Verkleinerte Kachelbilder auch auf der Festplatte speichern: Beim Zurückscrollen muss dann nichts
        // neu dekodiert und verkleinert werden. Bilder ohne Verkleinerung bleiben als Originaldaten liegen.
        konfiguration.dataCachePolicy = .automatic
        konfiguration.dataLoadingQueue.maxConcurrentOperationCount = 8
        ImagePipeline.shared = ImagePipeline(configuration: konfiguration)
    }

    /// Ein Bild aus allen Speichern entfernen (wenn sich hinter derselben Adresse ein neues Bild verbirgt).
    public static func vergiss(_ anfrage: URLRequest) {
        let r = ImageRequest(urlRequest: anfrage)
        ImagePipeline.shared.cache.removeCachedImage(for: r)
        ImagePipeline.shared.cache.removeCachedData(for: r)
    }

    /// Lädt ein Bild in voller Größe (über denselben Cache), z. B. für die Detailansicht.
    public static func lade(_ anfrage: URLRequest) async throws -> PlattformBild {
        try await ImagePipeline.shared.image(for: ImageRequest(urlRequest: anfrage))
    }

    /// Anfrage für eine Kachel mit passender Größe (spart Speicher beim Dekodieren).
    /// Die Größe wird auf feste Stufen aufgerundet: So treffen Kacheln nach einem Zoom oft noch den Cache.
    static func anfrage(_ urlRequest: URLRequest, pixel: CGFloat) -> ImageRequest {
        let stufe = groessenStufen.first { $0 >= pixel } ?? pixel
        return ImageRequest(urlRequest: urlRequest,
                            processors: [.resize(size: CGSize(width: stufe, height: stufe), contentMode: .aspectFill, crop: true)])
    }

    static let groessenStufen: [CGFloat] = [128, 256, 384, 512, 768, 1024, 1440, 2048]
}
