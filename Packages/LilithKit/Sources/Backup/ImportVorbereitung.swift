import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Angaben zu einer Datei, die hochgeladen werden soll: Aufnahmezeit, Art, Videodauer.
public struct DateiAngaben: Sendable, Equatable {
    public var erstellt: Date
    public var geaendert: Date
    public var istVideo: Bool
    public var dauerMs: Int?
}

public enum ImportVorbereitung {
    /// Ob Immich mit der Datei etwas anfangen kann (Foto oder Video).
    public static func istMedium(_ url: URL) -> Bool {
        guard let typ = UTType(filenameExtension: url.pathExtension) else { return false }
        return typ.conforms(to: .image) || typ.conforms(to: .movie) || typ.conforms(to: .video)
    }

    /// Ordner werden durchsucht, Dateien, die keine Fotos oder Videos sind, fallen weg.
    public static func sammleMedien(_ urls: [URL]) -> [URL] {
        var ergebnis: [URL] = []
        for url in urls {
            var istOrdner: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &istOrdner) else { continue }
            if istOrdner.boolValue {
                let inhalt = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let datei = inhalt?.nextObject() as? URL {
                    if istMedium(datei) { ergebnis.append(datei) }
                }
            } else if istMedium(url) {
                ergebnis.append(url)
            }
        }
        return ergebnis
    }

    /// Liest Aufnahmezeit (EXIF bzw. Video-Metadaten) und Videodauer. Fällt auf die Dateidaten zurück.
    public static func angaben(fuer url: URL) async -> DateiAngaben {
        let attribute = try? FileManager.default.attributesOfItem(atPath: url.path)
        let geaendert = attribute?[.modificationDate] as? Date ?? Date()
        let dateiErstellt = attribute?[.creationDate] as? Date ?? geaendert
        let typ = UTType(filenameExtension: url.pathExtension)
        let istVideo = typ.map { $0.conforms(to: .movie) || $0.conforms(to: .video) } ?? false

        if istVideo {
            let asset = AVURLAsset(url: url)
            let dauer = try? await asset.load(.duration)
            var erstellt = dateiErstellt
            if let datum = try? await asset.load(.creationDate), let wert = try? await datum.load(.dateValue) {
                erstellt = wert
            }
            let ms = dauer.map { Int(($0.seconds.isFinite ? $0.seconds : 0) * 1000) }
            return DateiAngaben(erstellt: erstellt, geaendert: geaendert, istVideo: true, dauerMs: ms)
        }
        return DateiAngaben(erstellt: exifDatum(url) ?? dateiErstellt, geaendert: geaendert, istVideo: false, dauerMs: nil)
    }

    /// Aufnahmezeit aus den EXIF-Daten, mit Zeitzone falls vorhanden.
    static func exifDatum(_ url: URL) -> Date? {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(quelle, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let versatz = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        return exifDatum(text, versatz: versatz)
    }

    /// „2026:10:18 19:42:10“ plus optional „+01:00“. Ohne Zeitzone gilt die des Geräts.
    static func exifDatum(_ text: String, versatz: String?) -> Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        if let versatz, !versatz.isEmpty {
            format.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            return format.date(from: text + versatz)
        }
        format.dateFormat = "yyyy:MM:dd HH:mm:ss"
        format.timeZone = .current
        return format.date(from: text)
    }
}
