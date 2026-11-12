import CoreGraphics
import Foundation
import Persistence

/// Zugriff auf die Fotomediathek des Geräts.
public enum MediathekZugriff: Sendable, Equatable {
    /// Noch nie gefragt.
    case unbekannt
    case voll
    /// Nur eine Auswahl ist freigegeben.
    case eingeschraenkt
    /// Abgelehnt oder durch Bildschirmzeit gesperrt.
    case verweigert
}

/// Ein Foto, fertig als Datei für den Upload.
public struct ExportiertesMedium: Sendable {
    public var datei: URL
    public var dateiname: String
    public var dauerMs: Int?
    /// Bei Live Photos das zugehörige Video.
    public var liveVideo: URL?

    public init(datei: URL, dateiname: String, dauerMs: Int? = nil, liveVideo: URL? = nil) {
        self.datei = datei; self.dateiname = dateiname; self.dauerMs = dauerMs; self.liveVideo = liveVideo
    }
}

public enum MediathekFehler: Error, Equatable, LocalizedError {
    /// Das Original liegt nur in iCloud („Speicher optimieren“).
    case nurInICloud
    /// Das Foto gibt es nicht mehr.
    case nichtGefunden
    /// Diese Art von Foto wird noch nicht unterstützt.
    case nichtUnterstuetzt

    public var errorDescription: String? {
        switch self {
        case .nurInICloud: "Das Original liegt nur in iCloud."
        case .nichtGefunden: "Das Foto ist nicht mehr in der Mediathek."
        case .nichtUnterstuetzt: "Diese Art von Foto wird noch nicht unterstützt."
        }
    }
}

/// Ein Album der Mediathek (eigenes Album oder von iOS, z. B. „Screenshots“).
public struct MediathekAlbum: Sendable, Hashable, Identifiable {
    public var id: String
    public var titel: String
    public var anzahl: Int
    /// Von iOS angelegt (Screenshots, Selfies, Videos …).
    public var vonIOS: Bool
    /// Foto für die Vorschau.
    public var titelBildId: String?

    public init(id: String, titel: String, anzahl: Int, vonIOS: Bool = false, titelBildId: String? = nil) {
        self.id = id; self.titel = titel; self.anzahl = anzahl; self.vonIOS = vonIOS; self.titelBildId = titelBildId
    }
}

/// Die Mediathek, austauschbar für Tests.
public protocol Mediathek: Sendable {
    func zugriff() -> MediathekZugriff
    /// Fragt nach Zugriff (zeigt den Systemdialog, falls noch nicht gefragt).
    func frageZugriff() async -> MediathekZugriff
    /// Alle Fotos und Videos (nur Kopfdaten, ohne Inhalt).
    func alleMedien() async throws -> [MediumKopf]
    /// SHA1 (Base64) der aktuellen Version, stückweise berechnet.
    /// - Parameter iCloud: Original bei Bedarf aus iCloud laden.
    func pruefsumme(_ id: String, iCloud: Bool) async throws -> String
    /// Schreibt das Foto (und bei Live Photos das Video) in den Ordner.
    func exportiere(_ id: String, nach ordner: URL, iCloud: Bool) async throws -> ExportiertesMedium
    /// Alle Alben (eigene und von iOS), ohne leere.
    func alben() async -> [MediathekAlbum]
    /// Kennungen der Fotos in einem Album.
    func medienIds(inAlbum id: String) async -> Set<String>
    /// Kleines Vorschaubild vom Gerät.
    func vorschau(_ id: String, kante: CGFloat) async -> CGImage?
}
