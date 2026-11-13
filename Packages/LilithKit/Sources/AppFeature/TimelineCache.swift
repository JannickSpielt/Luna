import Foundation
import Networking

/// Gespeicherter Stand der Timeline für einen Sofortstart: Monatsliste und die neuesten Monate.
/// Beim Start sofort zeigen, danach im Hintergrund mit dem Server abgleichen.
struct TimelineSchnappschuss: Codable, Sendable {
    var monate: [TimelineMonat]
    /// Inhalt je Monatsschlüssel (nur die neuesten paar Monate).
    var inhalte: [String: [TimelineAsset]]
}

enum TimelineCache {
    /// So viele der neuesten Monate werden mit Inhalt gespeichert.
    static let monateMitInhalt = 3

    private static var ordner: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Luna-Timeline")
    }

    private static func datei(_ server: ServerAddress) -> URL {
        // Dateiname aus der Serveradresse, ohne Sonderzeichen.
        let name = server.description.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return ordner.appending(path: "\(name).json")
    }

    static func lies(_ server: ServerAddress) async -> TimelineSchnappschuss? {
        let url = datei(server)
        return await Task.detached(priority: .userInitiated) {
            guard let daten = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(TimelineSchnappschuss.self, from: daten)
        }.value
    }

    static func schreibe(_ s: TimelineSchnappschuss, _ server: ServerAddress) {
        let url = datei(server)
        let ordner = self.ordner
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            guard let daten = try? JSONEncoder().encode(s) else { return }
            try? daten.write(to: url, options: .atomic)
        }
    }

    /// Beim Abmelden: Nichts vom alten Konto soll beim nächsten Start auftauchen.
    static func loescheAlles() {
        try? FileManager.default.removeItem(at: ordner)
    }
}

/// Gespeicherte Sammlungen (Alben, Kürzlich, Personen, Orte): sofort zeigen, im Hintergrund auffrischen.
struct SammlungenDaten: Codable, Sendable {
    var alben: [Album]
    var tage: [HochladeTag]
    var personen: [Person]
    var orte: [Ort]
}

enum SammlungenSpeicher {
    private static func datei(_ server: ServerAddress) -> URL {
        let name = server.description.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Luna-Timeline").appending(path: "\(name)-sammlungen.json")
    }

    static func lies(_ server: ServerAddress) async -> SammlungenDaten? {
        let url = datei(server)
        return await Task.detached(priority: .userInitiated) {
            guard let daten = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SammlungenDaten.self, from: daten)
        }.value
    }

    static func schreibe(_ s: SammlungenDaten, _ server: ServerAddress) {
        let url = datei(server)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let daten = try? JSONEncoder().encode(s) else { return }
            try? daten.write(to: url, options: .atomic)
        }
    }
}
