import CoreGraphics
import Foundation

/// Art eines Mediums im Grid.
public enum GridItemKind: UInt8, Sendable {
    case foto
    case video
    case livePhoto
}

/// Fotos, die nur auf dem Gerät liegen (noch nicht auf dem Server).
public enum GridLokal: UInt8, Sendable {
    /// Nur auf diesem Gerät.
    case nurHier
    /// Wird gerade hochgeladen.
    case laedtHoch
    /// Hochladen ist gescheitert.
    case fehler
}

/// Ein Eintrag im Grid.
public struct GridItem: Hashable, Sendable {
    /// Immich-Asset-ID (bei Testdaten „demo-…“).
    public let id: String
    /// Platzhalterfarbe als 0xRRGGBB, z. B. die Durchschnittsfarbe aus dem Thumbhash.
    public let farbe: UInt32
    public let art: GridItemKind
    public let favorit: Bool
    /// Videodauer in Sekunden, sonst 0.
    public let dauer: Int
    /// Bei Live Photos: ID des zugehörigen kurzen Videos.
    public let liveVideoId: String?
    /// `nil` für Fotos vom Server. Sonst liegt das Foto nur auf dem Gerät, `id` ist dann „lokal:<Kennung>“.
    public let lokal: GridLokal?

    public init(id: String, farbe: UInt32, art: GridItemKind, favorit: Bool, dauer: Int, liveVideoId: String? = nil,
                lokal: GridLokal? = nil) {
        self.lokal = lokal
        self.id = id
        self.farbe = farbe
        self.art = art
        self.favorit = favorit
        self.dauer = dauer
        self.liveVideoId = liveVideoId
    }

    public func mit(favorit: Bool) -> GridItem {
        GridItem(id: id, farbe: farbe, art: art, favorit: favorit, dauer: dauer, liveVideoId: liveVideoId, lokal: lokal)
    }

    public var rgb: (r: Double, g: Double, b: Double) {
        (Double((farbe >> 16) & 0xFF) / 255, Double((farbe >> 8) & 0xFF) / 255, Double(farbe & 0xFF) / 255)
    }

    /// Präfix der IDs von Fotos, die nur auf dem Gerät liegen.
    public static let lokalPraefix = "lokal:"
    /// Kennung in der Mediathek bei lokalen Fotos.
    public var lokaleId: String? { lokal == nil ? nil : String(id.dropFirst(Self.lokalPraefix.count)) }

    public var dauerText: String { String(format: "%d:%02d", dauer / 60, dauer % 60) }
}

/// Ein Monat in der Timeline. Die Anzahl ist vorab bekannt, die Einträge kommen später.
public struct GridSection: Hashable, Sendable, Identifiable {
    public let id: String
    public let titel: String
    public var untertitel: String
    public var anzahl: Int

    public init(id: String, titel: String, untertitel: String, anzahl: Int) {
        self.id = id
        self.titel = titel
        self.untertitel = untertitel
        self.anzahl = anzahl
    }
}

/// Liefert dem Grid seine Daten. Monate werden erst geladen, wenn sie gebraucht werden.
@MainActor
public protocol TimelineQuelle: AnyObject {
    var sections: [GridSection] { get }
    /// Eintrag oder `nil`, solange der Monat noch nicht geladen ist.
    func item(section: Int, index: Int) -> GridItem?
    /// Bittet darum, einen Monat zu laden. Mehrfache Aufrufe sind unschädlich.
    func ladeMonat(_ section: Int)
    /// Welche Monate gerade auf dem Bildschirm sind. Monate, die nur überflogen wurden, muss die Quelle nicht laden.
    func sichtbar(_ sections: Set<Int>)
    /// Anfragen für das Vorschaubild, von klein und schnell bis scharf. `pixel` ist die Kantenlänge der Kachel in Pixeln.
    func bildAnfragen(fuer item: GridItem, pixel: CGFloat) -> [URLRequest]
    /// Wird aufgerufen, wenn ein Monat geladen ist. `anzahlGeaendert`: Die Anzahl stimmte nicht mit der Vorschau überein.
    var onMonatGeladen: ((_ section: Int, _ anzahlGeaendert: Bool) -> Void)? { get set }
    /// Wird aufgerufen, wenn die ganze Timeline neu geladen wurde (Monate und Anzahlen können anders sein).
    var onAllesNeu: (() -> Void)? { get set }
    /// Lädt die Originaldatei in einen temporären Ordner (mit echtem Dateinamen), z. B. zum Herausziehen per Drag & Drop.
    func ladeOriginal(_ item: GridItem) async throws -> URL
    /// Vorschaubild für Fotos, die nur auf dem Gerät liegen.
    func lokalesBild(fuer item: GridItem, pixel: CGFloat) async -> CGImage?
    /// Aufnahmedatum eines Eintrags, `nil` wenn unbekannt oder noch nicht geladen.
    func datum(section: Int, index: Int) -> Date?
    /// Das Grid meldet, ob gerade gescrollt wird. Nur dann lohnt kurzes Warten vor dem Laden eines Monats.
    func scrollt(_ jetzt: Bool)
}

extension TimelineQuelle {
    public func lokalesBild(fuer item: GridItem, pixel: CGFloat) async -> CGImage? { nil }
    public func datum(section: Int, index: Int) -> Date? { nil }
    public func scrollt(_ jetzt: Bool) {}
}

extension TimelineQuelle {
    /// Zuordnung von Scroll-Anteil (0…1) zu Monat, gewichtet nach Anzahl. Für den Scrubber.
    public func section(beiAnteil anteil: Double) -> Int? {
        let gesamt = sections.reduce(0) { $0 + $1.anzahl }
        guard gesamt > 0 else { return nil }
        let ziel = Int(min(max(anteil, 0), 1) * Double(gesamt))
        var summe = 0
        for (i, s) in sections.enumerated() {
            summe += s.anzahl
            if summe > ziel { return i }
        }
        return sections.count - 1
    }
}

/// Monatsnamen auf Deutsch.
public enum Monatsname {
    public static let namen = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                               "August", "September", "Oktober", "November", "Dezember"]
    public static let kurz = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
}

/// Erfundene Bibliothek zum Testen ohne Server. Gleicher `seed` ergibt immer dieselben Daten.
@MainActor
public final class BeispielQuelle: TimelineQuelle {
    public private(set) var sections: [GridSection] = []
    private var items: [[GridItem]] = []
    public var onMonatGeladen: ((Int, Bool) -> Void)?
    public var onAllesNeu: (() -> Void)?

    public init(anzahl: Int = 100_000, seed: UInt64 = 42, bisJahr: Int = 2026, bisMonat: Int = 11) {
        (sections, items) = Self.erzeuge(anzahl: anzahl, seed: seed, bisJahr: bisJahr, bisMonat: bisMonat)
    }

    public var gesamt: Int { items.reduce(0) { $0 + $1.count } }
    public func item(section: Int, index: Int) -> GridItem? { items[section][index] }
    public func ladeMonat(_ section: Int) {}
    public func sichtbar(_ sections: Set<Int>) {}
    public func bildAnfragen(fuer item: GridItem, pixel: CGFloat) -> [URLRequest] { [] }
    public func ladeOriginal(_ item: GridItem) async throws -> URL { throw CocoaError(.featureUnsupported) }

    nonisolated static func erzeuge(anzahl: Int, seed: UInt64, bisJahr: Int, bisMonat: Int) -> ([GridSection], [[GridItem]]) {
        var zufall = SplitMix64(seed: seed)
        let orte = ["Hamburg", "Lissabon", "Ostsee", "Berlin", "Zuhause", "Porto", "Alpen",
                    "Kopenhagen", "Garten", "Amsterdam", "Wien", "Sylt"]
        var sections: [GridSection] = []
        var items: [[GridItem]] = []
        var rest = anzahl
        var jahr = bisJahr
        var monat = bisMonat
        var laufend = 0
        while rest > 0 {
            let basis = Int(zufall.next() % 600) + 80
            let spitze = zufall.next() % 7 == 0 ? Int(zufall.next() % 1800) : 0
            let n = min(rest, basis + spitze)
            var monatItems: [GridItem] = []
            monatItems.reserveCapacity(n)
            for _ in 0..<n {
                let r = zufall.next()
                let art: GridItemKind = r % 23 == 0 ? .video : (r % 17 == 0 ? .livePhoto : .foto)
                monatItems.append(GridItem(
                    id: "demo-\(laufend)",
                    farbe: GridPalette.farben[Int((r >> 8) % UInt64(GridPalette.farben.count))],
                    art: art,
                    favorit: (r >> 16) % 29 == 0,
                    dauer: art == .video ? Int(5 + (r >> 24) % 300) : 0))
                laufend += 1
            }
            let ort = orte[Int(zufall.next() % UInt64(orte.count))]
            sections.append(GridSection(id: "\(jahr)-\(monat)", titel: "\(Monatsname.namen[monat - 1]) \(jahr)",
                                        untertitel: "\(ort) · \(n.formatted()) Objekte", anzahl: n))
            items.append(monatItems)
            rest -= n
            monat -= 1
            if monat == 0 { monat = 12; jahr -= 1 }
        }
        return (sections, items)
    }
}

/// Kleiner, schneller Zufallsgenerator mit festem Startwert.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Gedämpfte Platzhalterfarben für Testdaten und Fotos ohne Thumbhash.
public enum GridPalette {
    public static let farben: [UInt32] = [
        0x5B4A3F, 0x8A6B52, 0x3E4A52, 0xA7826A, 0x2F3B35, 0x6E5A6B,
        0xC29A74, 0x4C3A44, 0x7D8C8A, 0x9B5F4E, 0x35424F, 0xB79A7E,
    ]
}

/// Liest die Durchschnittsfarbe aus einem Thumbhash (Base64), ohne das ganze Bild zu dekodieren.
/// Verfahren nach der Thumbhash-Referenz von Evan Wallace.
public enum Thumbhash {
    public static func durchschnittsfarbe(_ base64: String) -> UInt32? {
        guard let daten = Data(base64Encoded: base64), daten.count >= 5 else { return nil }
        let b = [UInt8](daten)
        let kopf = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16
        let l = Double(kopf & 63) / 63
        let p = Double((kopf >> 6) & 63) / 31.5 - 1
        let q = Double((kopf >> 12) & 63) / 31.5 - 1
        let blau = l - 2.0 / 3.0 * p
        let rot = (3 * l - blau + q) / 2
        let gruen = rot - q
        func kanal(_ x: Double) -> UInt32 { UInt32((min(max(x, 0), 1) * 255).rounded()) }
        return kanal(rot) << 16 | kanal(gruen) << 8 | kanal(blau)
    }
}

/// Spaltenstufen für Pinch-Zoom und Tastatur.
public struct GridZoom: Sendable, Equatable {
    public let stufen: [Int]
    public private(set) var index: Int

    public init(stufen: [Int], start: Int) {
        precondition(!stufen.isEmpty)
        self.stufen = stufen
        self.index = stufen.firstIndex(of: start) ?? stufen.count / 2
    }

    public var spalten: Int { stufen[index] }

    /// Vergrößern = weniger Spalten. Gibt `false` zurück, wenn es nicht weitergeht.
    @discardableResult
    public mutating func groesser() -> Bool {
        guard index > 0 else { return false }
        index -= 1
        return true
    }

    /// Verkleinern = mehr Spalten.
    @discardableResult
    public mutating func kleiner() -> Bool {
        guard index < stufen.count - 1 else { return false }
        index += 1
        return true
    }

    public static let iPhone = GridZoom(stufen: [1, 3, 4, 5, 7, 11], start: 4)
    public static let iPad = GridZoom(stufen: [3, 5, 7, 10, 14], start: 7)
    public static let mac = GridZoom(stufen: [4, 6, 8, 12, 18], start: 8)
}
