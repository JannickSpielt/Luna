import Foundation

/// Art eines Mediums im Grid.
public enum GridItemKind: UInt8, Sendable {
    case foto
    case video
    case livePhoto
}

/// Ein Eintrag im Grid. Bewusst klein gehalten (wenige Bytes),
/// damit auch 100.000+ Einträge kaum Speicher kosten.
public struct GridItem: Hashable, Sendable {
    public let id: Int32
    /// Index in die Platzhalter-Palette (später: Thumbhash-Durchschnittsfarbe).
    public let farbe: UInt8
    public let art: GridItemKind
    public let favorit: Bool
    /// Videodauer in Sekunden, sonst 0.
    public let dauer: UInt16

    public init(id: Int32, farbe: UInt8, art: GridItemKind, favorit: Bool, dauer: UInt16) {
        self.id = id
        self.farbe = farbe
        self.art = art
        self.favorit = favorit
        self.dauer = dauer
    }
}

/// Ein Monat in der Timeline. Entspricht einem Immich-Timeline-Bucket.
public struct GridSection: Hashable, Sendable, Identifiable {
    public let id: Int
    public let titel: String
    public let untertitel: String
    /// Bereich der Einträge dieses Monats in `GridModel.items`.
    public let bereich: Range<Int>

    public var anzahl: Int { bereich.count }
}

/// Daten für das Grid: Monate (neueste zuerst) und alle Einträge am Stück.
/// Die Aufteilung nach Anzahl pro Monat passt zu Immichs Timeline-Buckets,
/// bei denen die Anzahl vorab bekannt ist und Inhalte später nachgeladen werden.
public struct GridModel: Sendable {
    public let sections: [GridSection]
    public let items: [GridItem]

    public init(sections: [GridSection], items: [GridItem]) {
        self.sections = sections
        self.items = items
    }

    public subscript(section: Int, item: Int) -> GridItem {
        items[sections[section].bereich.lowerBound + item]
    }

    /// Erfundene Bibliothek zum Testen. Gleicher `seed` ergibt immer dieselben Daten.
    public static func beispiel(anzahl: Int = 100_000, seed: UInt64 = 42, bisJahr: Int = 2026, bisMonat: Int = 11) -> GridModel {
        var zufall = SplitMix64(seed: seed)
        let monatsnamen = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
                           "August", "September", "Oktober", "November", "Dezember"]
        let orte = ["Hamburg", "Lissabon", "Ostsee", "Berlin", "Zuhause", "Porto", "Alpen",
                    "Kopenhagen", "Garten", "Amsterdam", "Wien", "Sylt"]

        // Monatsgrößen schwanken stark wie im echten Leben (Urlaub, Feiern, ruhige Monate).
        var groessen: [Int] = []
        var rest = anzahl
        while rest > 0 {
            let basis = Int(zufall.next() % 600) + 80
            let spitze = zufall.next() % 7 == 0 ? Int(zufall.next() % 1800) : 0
            let n = min(rest, basis + spitze)
            groessen.append(n)
            rest -= n
        }

        var sections: [GridSection] = []
        var items: [GridItem] = []
        items.reserveCapacity(anzahl)
        var jahr = bisJahr
        var monat = bisMonat
        var start = 0
        for (index, n) in groessen.enumerated() {
            for _ in 0..<n {
                let r = zufall.next()
                let art: GridItemKind = r % 23 == 0 ? .video : (r % 17 == 0 ? .livePhoto : .foto)
                items.append(GridItem(
                    id: Int32(items.count),
                    farbe: UInt8((r >> 8) % UInt64(GridPalette.anzahl)),
                    art: art,
                    favorit: (r >> 16) % 29 == 0,
                    dauer: art == .video ? UInt16(5 + (r >> 24) % 300) : 0
                ))
            }
            let ort = orte[Int(zufall.next() % UInt64(orte.count))]
            sections.append(GridSection(
                id: index,
                titel: "\(monatsnamen[monat - 1]) \(jahr)",
                untertitel: "\(ort) · \(n.formatted()) Objekte",
                bereich: start..<(start + n)
            ))
            start += n
            monat -= 1
            if monat == 0 { monat = 12; jahr -= 1 }
        }
        return GridModel(sections: sections, items: items)
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

/// Gedämpfte Platzhalterfarben, wie Durchschnittsfarben echter Fotos.
public enum GridPalette {
    public static let farben: [UInt32] = [
        0x5B4A3F, 0x8A6B52, 0x3E4A52, 0xA7826A, 0x2F3B35, 0x6E5A6B,
        0xC29A74, 0x4C3A44, 0x7D8C8A, 0x9B5F4E, 0x35424F, 0xB79A7E,
    ]
    public static var anzahl: Int { farben.count }

    public static func rgb(_ index: UInt8) -> (r: Double, g: Double, b: Double) {
        let hex = farben[Int(index) % farben.count]
        return (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
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

    public static let iPhone = GridZoom(stufen: [1, 3, 5, 7, 11], start: 3)
    public static let iPad = GridZoom(stufen: [3, 5, 7, 10, 14], start: 7)
    public static let mac = GridZoom(stufen: [4, 6, 8, 12, 18], start: 8)
}
