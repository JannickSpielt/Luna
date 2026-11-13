import AVFoundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import DesignSystem
import Networking

/// „In Luna hochladen“: erscheint im Teilen-Menü jeder App bei Fotos und Videos.
final class TeilenController: UIViewController {
    private let modell = TeilenModell()

    override func viewDidLoad() {
        super.viewDidLoad()
        modell.schliessen = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        modell.abbrechen = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
        let anbieter = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        modell.starte(anbieter)

        let ansicht = UIHostingController(rootView: TeilenAnsicht(modell: modell))
        addChild(ansicht)
        ansicht.view.frame = view.bounds
        ansicht.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(ansicht.view)
        ansicht.didMove(toParent: self)
    }
}

/// Eine geteilte Datei, schon in den eigenen Arbeitsordner kopiert.
struct GeteilteDatei: Sendable {
    let url: URL
    let istVideo: Bool
}

@MainActor
@Observable
final class TeilenModell {
    enum Zustand: Equatable {
        case vorbereiten
        case keinKonto
        case bereit
        case laeuft(fertig: Int, gesamt: Int, anteil: Double)
        case fertig(neu: Int, schonDa: Int)
        case fehler(String)
    }

    var zustand: Zustand = .vorbereiten
    var dateien: [GeteilteDatei] = []
    var alben: [Album] = []
    var albumId: String?
    var schliessen: () -> Void = {}
    var abbrechen: () -> Void = {}

    private var client: ImmichClient?
    private let ordner = FileManager.default.temporaryDirectory.appending(path: "luna-teilen", directoryHint: .isDirectory)

    var anzahlText: String {
        let videos = dateien.filter(\.istVideo).count
        let fotos = dateien.count - videos
        var teile: [String] = []
        if fotos > 0 { teile.append(fotos == 1 ? "1 Foto" : "\(fotos) Fotos") }
        if videos > 0 { teile.append(videos == 1 ? "1 Video" : "\(videos) Videos") }
        return teile.isEmpty ? "Nichts zum Hochladen" : teile.joined(separator: " und ")
    }

    func starte(_ anbieter: [NSItemProvider]) {
        guard let (konto, zugang) = GeteiltesKonto.lade() else {
            zustand = .keinKonto
            return
        }
        let client = ImmichClient(address: konto.server.address, credential: zugang)
        self.client = client
        let ziel = ordner
        Task {
            try? FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
            var liste: [GeteilteDatei] = []
            for a in anbieter {
                if let d = await Self.kopiere(a, nach: ziel) { liste.append(d) }
            }
            dateien = liste
            zustand = liste.isEmpty ? .fehler("Diese Dateien kann Luna nicht hochladen.") : .bereit
        }
        Task {
            alben = ((try? await client.alben()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func hochladen() {
        guard let client, zustand == .bereit else { return }
        let liste = dateien
        let album = albumId
        let arbeitsordner = ordner.appending(path: "arbeit", directoryHint: .isDirectory)
        zustand = .laeuft(fertig: 0, gesamt: liste.count, anteil: 0)
        Task {
            var ids: [String] = []
            var schonDa = 0
            do {
                for (i, d) in liste.enumerated() {
                    let datei = try await Self.uploadDatei(d)
                    let gesamt = liste.count
                    let ergebnis = try await client.ladeHoch(datei, arbeitsordner: arbeitsordner) { anteil in
                        Task { @MainActor [weak self] in
                            self?.zustand = .laeuft(fertig: i, gesamt: gesamt, anteil: anteil)
                        }
                    }
                    ids.append(ergebnis.id)
                    if ergebnis.duplikat { schonDa += 1 }
                    zustand = .laeuft(fertig: i + 1, gesamt: liste.count, anteil: 0)
                }
                if let album, !ids.isEmpty { try await client.nachUpload(albumId: album, assetIds: ids) }
                zustand = .fertig(neu: ids.count - schonDa, schonDa: schonDa)
                aufraeumen()
                try? await Task.sleep(for: .seconds(1.4))
                schliessen()
            } catch {
                zustand = .fehler(Self.text(fuer: error, hochgeladen: ids.count))
            }
        }
    }

    func beenden() {
        aufraeumen()
        if case .fertig = zustand { schliessen() } else { abbrechen() }
    }

    private func aufraeumen() {
        try? FileManager.default.removeItem(at: ordner)
    }

    private static func text(fuer error: Error, hochgeladen: Int) -> String {
        let grund = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return hochgeladen > 0 ? "\(hochgeladen) wurden hochgeladen, dann ging es nicht weiter. \(grund)" : grund
    }

    // MARK: - Dateien

    /// Kopiert ein geteiltes Foto oder Video in den Arbeitsordner (das Original gehört der anderen App).
    private static func kopiere(_ a: NSItemProvider, nach ziel: URL) async -> GeteilteDatei? {
        let typ: UTType
        let video: Bool
        if a.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            typ = .movie; video = true
        } else if a.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            typ = .image; video = false
        } else {
            return nil
        }
        let url: URL? = await withCheckedContinuation { fortsetzung in
            _ = a.loadFileRepresentation(for: typ, openInPlace: false) { quelle, _, _ in
                guard let quelle else { fortsetzung.resume(returning: nil); return }
                let kopie = ziel.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                    .appending(path: quelle.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: kopie.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: quelle, to: kopie)
                    fortsetzung.resume(returning: kopie)
                } catch {
                    fortsetzung.resume(returning: nil)
                }
            }
        }
        if let url { return GeteilteDatei(url: url, istVideo: video) }
        // Manche Apps liefern nur Bilddaten (z. B. ein bearbeitetes Bildschirmfoto).
        guard !video, let daten: Data = await withCheckedContinuation({ fortsetzung in
            _ = a.loadDataRepresentation(for: .image) { d, _ in fortsetzung.resume(returning: d) }
        }) else { return nil }
        let endung = UIImage(data: daten) != nil ? (a.registeredContentTypes.first?.preferredFilenameExtension ?? "jpg") : "jpg"
        let kopie = ziel.appending(path: "Bild-\(UUID().uuidString.prefix(8)).\(endung)")
        do { try daten.write(to: kopie) } catch { return nil }
        return GeteilteDatei(url: kopie, istVideo: false)
    }

    /// Aufnahmedatum und Prüfsumme ermitteln. Ohne Datum in der Datei: jetzt.
    nonisolated private static func uploadDatei(_ d: GeteilteDatei) async throws -> UploadDatei {
        var datum: Date?
        var dauerMs: Int?
        if d.istVideo {
            let asset = AVURLAsset(url: d.url)
            if let item = try? await asset.load(.creationDate) { datum = try? await item.load(.dateValue) }
            if let dauer = try? await asset.load(.duration), dauer.isNumeric { dauerMs = Int(dauer.seconds * 1000) }
        } else {
            datum = exifDatum(d.url)
        }
        let werte = try? d.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let erstellt = datum ?? werte?.creationDate ?? .now
        return UploadDatei(datei: d.url, dateiname: d.url.lastPathComponent, erstellt: erstellt,
                           geaendert: werte?.contentModificationDate ?? erstellt, dauerMs: dauerMs,
                           pruefsumme: try? Pruefsumme.sha1Base64(datei: d.url))
    }

    nonisolated private static func exifDatum(_ url: URL) -> Date? {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
              let eigenschaften = CGImageSourceCopyPropertiesAtIndex(quelle, 0, nil) as? [CFString: Any],
              let exif = eigenschaften[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: text)
    }
}

// MARK: - Oberfläche

struct TeilenAnsicht: View {
    @Bindable var modell: TeilenModell

    var body: some View {
        NavigationStack {
            Form {
                switch modell.zustand {
                case .vorbereiten:
                    Section { HStack { ProgressView(); Text("Wird vorbereitet …").padding(.leading, 8) } }
                case .keinKonto:
                    Section {
                        Label("Bitte zuerst in Luna anmelden", systemImage: "person.crop.circle.badge.exclamationmark")
                    } footer: {
                        Text("Öffne Luna einmal und melde dich an. Danach kannst du von überall hochladen.")
                    }
                case .bereit:
                    Section { Label(modell.anzahlText, systemImage: "photo.on.rectangle") }
                    Section {
                        Picker("Album", selection: $modell.albumId) {
                            Text("Kein Album").tag(String?.none)
                            ForEach(modell.alben) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } footer: {
                        Text("Fotos, die schon auf dem Server sind, werden nicht doppelt gespeichert.")
                    }
                case .laeuft(let fertig, let gesamt, let anteil):
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(min(fertig + 1, gesamt)) von \(gesamt) wird hochgeladen …")
                            ProgressView(value: (Double(fertig) + anteil) / Double(max(gesamt, 1)))
                                .tint(LilithColor.nachtrose)
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text("Bitte dieses Fenster offen lassen, bis alles oben ist.")
                    }
                case .fertig(let neu, let schonDa):
                    Section {
                        Label(fertigText(neu: neu, schonDa: schonDa), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(LilithColor.nachtrose)
                    }
                case .fehler(let text):
                    Section {
                        Label(text, systemImage: "exclamationmark.triangle")
                    } header: {
                        Text("Das hat nicht geklappt")
                    }
                }
            }
            .navigationTitle("Luna")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(modell.zustand == .bereit || modell.zustand == .vorbereiten ? "Abbrechen" : "Schließen") {
                        modell.beenden()
                    }
                }
                if modell.zustand == .bereit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hochladen") { modell.hochladen() }
                    }
                }
            }
        }
        .tint(LilithColor.nachtrose)
    }

    private func fertigText(neu: Int, schonDa: Int) -> String {
        if neu == 0 { return schonDa == 1 ? "War schon auf dem Server" : "Alle waren schon auf dem Server" }
        let teil = neu == 1 ? "1 hochgeladen" : "\(neu) hochgeladen"
        return schonDa > 0 ? "\(teil), \(schonDa) waren schon da" : teil
    }
}
