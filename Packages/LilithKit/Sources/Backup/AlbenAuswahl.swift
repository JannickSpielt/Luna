import Foundation

/// Welche Alben der Mediathek gesichert werden. Wie in der Immich-App:
/// Ein Foto wird gesichert, wenn es in mindestens einem gewählten und in keinem ausgeschlossenen Album liegt.
public struct AlbenAuswahl: Codable, Sendable, Equatable {
    /// Kennung für „Alle Fotos“.
    public static let alle = "alle"

    public enum Zustand: Sendable { case neutral, gewaehlt, ausgeschlossen }

    public var gewaehlt: Set<String> = [AlbenAuswahl.alle]
    public var ausgeschlossen: Set<String> = []

    public init(gewaehlt: Set<String> = [AlbenAuswahl.alle], ausgeschlossen: Set<String> = []) {
        self.gewaehlt = gewaehlt
        self.ausgeschlossen = ausgeschlossen
    }

    public func zustand(_ id: String) -> Zustand {
        if gewaehlt.contains(id) { return .gewaehlt }
        if ausgeschlossen.contains(id) { return .ausgeschlossen }
        return .neutral
    }

    /// Antippen: neutral → gewählt → ausgeschlossen → neutral.
    public mutating func weiter(_ id: String) {
        switch zustand(id) {
        case .neutral: gewaehlt.insert(id)
        case .gewaehlt:
            gewaehlt.remove(id)
            ausgeschlossen.insert(id)
        case .ausgeschlossen: ausgeschlossen.remove(id)
        }
    }

    /// Ist überhaupt etwas zum Sichern gewählt?
    public var leer: Bool { gewaehlt.isEmpty }
}
