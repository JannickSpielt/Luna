import AppIntents
import ImageIO
import OSLog
import SwiftUI
import UIKit
import WidgetKit
import Networking

// MARK: - Einstellungen (beim Bearbeiten des Widgets)

/// Woher die Fotos kommen.
enum FotoQuelleWahl: String, AppEnum {
    case alle, favoriten, heuteFrueher, album

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Fotos"
    static let caseDisplayRepresentations: [FotoQuelleWahl: DisplayRepresentation] = [
        .alle: "Zufällig aus allen",
        .favoriten: "Favoriten",
        .heuteFrueher: "Heute in früheren Jahren",
        .album: "Album",
    ]
}

/// Ein Album zur Auswahl im Widget.
struct AlbumEintrag: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Album"
    static let defaultQuery = AlbumAbfrage()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AlbumAbfrage: EntityQuery {
    func entities(for identifiers: [AlbumEintrag.ID]) async throws -> [AlbumEintrag] {
        try await alleAlben().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AlbumEintrag] {
        try await alleAlben()
    }

    private func alleAlben() async throws -> [AlbumEintrag] {
        guard let (konto, zugang) = GeteiltesKonto.lade() else { return [] }
        let client = ImmichClient(address: konto.server.address, credential: zugang)
        return try await client.alben()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { AlbumEintrag(id: $0.id, name: $0.name) }
    }
}

struct FotoWidgetEinstellung: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Foto"
    static let description = IntentDescription("Zeigt Fotos aus deiner Luna-Bibliothek.")

    @Parameter(title: "Fotos", default: .alle)
    var quelle: FotoQuelleWahl

    @Parameter(title: "Album")
    var album: AlbumEintrag?

    static var parameterSummary: some ParameterSummary {
        When(\.$quelle, .equalTo, .album) {
            Summary("\(\.$quelle): \(\.$album)")
        } otherwise: {
            Summary("\(\.$quelle)")
        }
    }

    var zufallsQuelle: ZufallsQuelle {
        switch quelle {
        case .alle: .alle
        case .favoriten: .favoriten
        case .heuteFrueher: .heuteFrueher
        case .album: album.map { .album($0.id) } ?? .alle
        }
    }
}

// MARK: - Zeitleiste

struct FotoEintrag: TimelineEntry {
    let date: Date
    let foto: WidgetFoto?
    let bild: UIImage?
    /// Statt eines Fotos ein kurzer Hinweis (z. B. „In Luna anmelden“).
    var hinweis: String?
}

struct FotoAnbieter: AppIntentTimelineProvider {
    static let log = Logger(subsystem: "app.lilith", category: "Widget")
    /// Fotos pro Ladevorgang; jedes bleibt etwa drei Stunden stehen.
    private static let anzahl = 4
    private static let abstand: TimeInterval = 3 * 3600

    func placeholder(in context: Context) -> FotoEintrag {
        FotoEintrag(date: .now, foto: nil, bild: nil)
    }

    func snapshot(for configuration: FotoWidgetEinstellung, in context: Context) async -> FotoEintrag {
        if context.isPreview { return placeholder(in: context) }
        return await eintraege(configuration, kante: context.displaySize, hoechstens: 1).first ?? placeholder(in: context)
    }

    func timeline(for configuration: FotoWidgetEinstellung, in context: Context) async -> Timeline<FotoEintrag> {
        let liste = await eintraege(configuration, kante: context.displaySize, hoechstens: Self.anzahl)
        let naechstes = Date.now.addingTimeInterval(Double(max(liste.count, 1)) * Self.abstand)
        return Timeline(entries: liste, policy: .after(naechstes))
    }

    private func eintraege(_ einstellung: FotoWidgetEinstellung, kante: CGSize, hoechstens: Int) async -> [FotoEintrag] {
        guard let (konto, zugang) = GeteiltesKonto.lade() else {
            return [FotoEintrag(date: .now, foto: nil, bild: nil, hinweis: "In Luna anmelden")]
        }
        let client = ImmichClient(address: konto.server.address, credential: zugang)
        let fotos: [WidgetFoto]
        do {
            fotos = try await client.zufaelligeFotos(einstellung.zufallsQuelle, anzahl: hoechstens)
        } catch {
            Self.log.error("Fotos laden: \(String(describing: error), privacy: .public)")
            return [FotoEintrag(date: .now, foto: nil, bild: nil, hinweis: "Server nicht erreichbar")]
        }
        guard !fotos.isEmpty else {
            return [FotoEintrag(date: .now, foto: nil, bild: nil, hinweis: "Keine Fotos gefunden")]
        }
        // Pixel für die größte Seite des Widgets (Widgets haben wenig Speicher, darum verkleinern).
        let pixel = max(kante.width, kante.height) * 3
        var ergebnis: [FotoEintrag] = []
        for (i, foto) in fotos.prefix(hoechstens).enumerated() {
            let bild = await Self.ladeBild(client.vorschauAnfrage(assetId: foto.id, groesse: .preview), pixel: pixel)
            ergebnis.append(FotoEintrag(date: .now.addingTimeInterval(Double(i) * Self.abstand), foto: foto, bild: bild))
        }
        return ergebnis
    }

    private static func ladeBild(_ anfrage: URLRequest, pixel: CGFloat) async -> UIImage? {
        guard let (daten, _) = try? await URLSession.shared.data(for: anfrage),
              let quelle = CGImageSourceCreateWithData(daten as CFData, nil) else { return nil }
        let optionen: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixel, 300),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Ansicht

struct FotoWidgetAnsicht: View {
    let eintrag: FotoEintrag
    @Environment(\.widgetFamily) private var groesse

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if eintrag.bild == nil {
                VStack(spacing: 6) {
                    Image(systemName: "moon.fill").font(.title2).foregroundStyle(Self.mondlicht)
                    if let hinweis = eintrag.hinweis {
                        Text(hinweis).font(.caption).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let foto = eintrag.foto, eintrag.bild != nil {
                VStack(alignment: .leading, spacing: 1) {
                    Text(foto.aufgenommen.formatted(.dateTime.day().month(groesse == .systemSmall ? .abbreviated : .wide).year()))
                        .font(.caption.weight(.semibold))
                    if let stadt = foto.stadt, groesse != .systemSmall {
                        Text(stadt).font(.caption2)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .padding(12)
            }
        }
        .containerBackground(for: .widget) {
            if let bild = eintrag.bild {
                Image(uiImage: bild).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.10, green: 0.07, blue: 0.16), Color(red: 0.03, green: 0.03, blue: 0.06)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .widgetURL(eintrag.foto.map(FotoLink.url))
    }

    private static let mondlicht = Color(red: 0.92, green: 0.85, blue: 0.71)
}

struct FotoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LunaFoto", intent: FotoWidgetEinstellung.self, provider: FotoAnbieter()) { eintrag in
            FotoWidgetAnsicht(eintrag: eintrag)
        }
        .configurationDisplayName("Foto")
        .description("Ein Foto aus deiner Bibliothek, das mehrmals am Tag wechselt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
