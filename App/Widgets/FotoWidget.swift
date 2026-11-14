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
    /// Zuletzt geladenes Foto, weil der Server gerade nicht antwortet.
    var ausSpeicher = false
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
        // Nichts Neues geladen (Server weg, nicht angemeldet): in einer halben Stunde noch einmal versuchen.
        let frisch = liste.contains { $0.bild != nil && !$0.ausSpeicher }
        let naechstes = Date.now.addingTimeInterval(frisch ? Double(liste.count) * Self.abstand : 1800)
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
            // Lieber das letzte Foto weiter zeigen als eine Meldung.
            return [Self.gemerkt() ?? FotoEintrag(date: .now, foto: nil, bild: nil, hinweis: "Server nicht erreichbar")]
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
        if let erstes = ergebnis.first(where: { $0.bild != nil }) { Self.merke(erstes) }
        return ergebnis
    }

    // MARK: Letztes Foto (für Zeiten ohne Server)

    private static var ordner: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "luna-widget", directoryHint: .isDirectory)
    }

    private static func merke(_ eintrag: FotoEintrag) {
        guard let foto = eintrag.foto, let daten = eintrag.bild?.jpegData(compressionQuality: 0.85),
              let info = try? JSONEncoder().encode(foto) else { return }
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try? daten.write(to: ordner.appending(path: "bild.jpg"), options: .atomic)
        try? info.write(to: ordner.appending(path: "foto.json"), options: .atomic)
    }

    private static func gemerkt() -> FotoEintrag? {
        guard let daten = try? Data(contentsOf: ordner.appending(path: "foto.json")),
              let foto = try? JSONDecoder().decode(WidgetFoto.self, from: daten),
              let bild = UIImage(contentsOfFile: ordner.appending(path: "bild.jpg").path()) else { return nil }
        return FotoEintrag(date: .now, foto: foto, bild: bild, ausSpeicher: true)
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
                // Ohne Foto: kleiner Mond oben links, Hinweis klein unten links – nichts groß in der Mitte.
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "moon.fill").font(.callout).foregroundStyle(Self.mondlicht)
                    Spacer(minLength: 0)
                    if let hinweis = eintrag.hinweis {
                        Text(hinweis)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }
            if let foto = eintrag.foto, eintrag.bild != nil {
                // Datum klein unten links auf einem sanften Verlauf, damit es auf hellen Fotos lesbar bleibt.
                HStack(spacing: 4) {
                    Text(foto.aufgenommen.formatted(.dateTime.day().month(groesse == .systemSmall ? .abbreviated : .wide).year()))
                        .font(.caption2.weight(.semibold))
                    if let stadt = foto.stadt, groesse != .systemSmall {
                        Text("· \(stadt)").font(.caption2).lineLimit(1)
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            }
        }
        // Ganze Fläche des Widgets nutzen, damit das Datum wirklich unten links sitzt (nicht mittig).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
