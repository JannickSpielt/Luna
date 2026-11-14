import SwiftUI
import Observation

/// Die Designs von Luna. Weihnachten gibt es nur in der Weihnachtszeit (1. Dezember bis 6. Januar).
public enum Design: String, CaseIterable, Identifiable, Sendable {
    case standard, schwarz, nacht, weihnachten

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .standard: "Standard"
        case .schwarz: "Schwarz"
        case .nacht: "Nacht"
        case .weihnachten: "Weihnachten"
        }
    }

    public var beschreibung: String {
        switch self {
        case .standard: "Hell oder dunkel wie dein Gerät, mit Kirschrot."
        case .schwarz: "Echtes Schwarz, auch am Tag. Fotos leuchten."
        case .nacht: "Der Nachthimmel von Luna, mit Mondgold."
        case .weihnachten: "Schnee in der App, nur bis 6. Januar."
        }
    }

    /// Erzwungenes Erscheinungsbild, `nil` folgt dem Gerät.
    public var schema: ColorScheme? {
        switch self {
        case .schwarz, .nacht: .dark
        case .standard, .weihnachten: nil
        }
    }

    public var palette: Palette {
        switch self {
        case .standard, .weihnachten: .standard
        case .schwarz: .schwarz
        case .nacht: .nacht
        }
    }

    /// Welche Designs heute zur Wahl stehen.
    public static func waehlbar(heute: Date = .now, kalender: Calendar = .current) -> [Design] {
        Weihnachten.zeitraum(heute, kalender: kalender) ? allCases : [.standard, .schwarz, .nacht]
    }
}

/// Die Farben eines Designs.
public struct Palette: Sendable {
    public let hintergrund: Color
    public let flaeche: Color
    /// Akzent als Schrift und Symbol.
    public let akzent: Color
    /// Akzent als Fläche mit weißer Schrift darauf.
    public let akzentFlaeche: Color

    static let standard = Palette(
        hintergrund: LilithColor.system(ui: "systemBackground", mac: "windowBackgroundColor"),
        flaeche: LilithColor.system(ui: "secondarySystemBackground", mac: "controlBackgroundColor"),
        akzent: .lilith(light: 0xC8102E, dark: 0xFF4D6A),
        akzentFlaeche: .lilith(light: 0xC8102E, dark: 0xC8102E))

    static let schwarz = Palette(
        hintergrund: .lilith(light: 0x000000, dark: 0x000000),
        flaeche: .lilith(light: 0x121212, dark: 0x121212),
        akzent: .lilith(light: 0xFF4D6A, dark: 0xFF4D6A),
        akzentFlaeche: .lilith(light: 0xC8102E, dark: 0xC8102E))

    /// Blauschwarz wie der Himmel hinter dem Mond, Mondgold statt Kirschrot.
    /// Gold als Schrift 12 : 1 auf dem Grund, als Fläche 5 : 1 zu weißer Schrift.
    static let nacht = Palette(
        hintergrund: .lilith(light: 0x0B0E1A, dark: 0x0B0E1A),
        flaeche: .lilith(light: 0x161B2E, dark: 0x161B2E),
        akzent: .lilith(light: 0xEBD9B4, dark: 0xEBD9B4),
        akzentFlaeche: .lilith(light: 0x8A6A30, dark: 0x8A6A30))
}

/// Was gespeichert ist: das gewählte Design und, für die Rückkehr nach Weihnachten, das davor.
public struct DesignStand: Equatable, Sendable {
    public var gewaehlt: Design
    /// Das Design vor dem automatischen Wechsel auf Weihnachten.
    public var vorher: Design?
    /// Für welche Weihnachtszeit (Jahr des Dezembers) schon automatisch gewechselt wurde.
    public var saison: Int?

    public init(gewaehlt: Design = .standard, vorher: Design? = nil, saison: Int? = nil) {
        self.gewaehlt = gewaehlt; self.vorher = vorher; self.saison = saison
    }

    /// Jahr des Dezembers der laufenden Weihnachtszeit, sonst `nil`.
    public static func saisonJahr(_ heute: Date, kalender: Calendar) -> Int? {
        let t = kalender.dateComponents([.year, .month, .day], from: heute)
        guard let jahr = t.year else { return nil }
        if t.month == 12 { return jahr }
        if t.month == 1, (t.day ?? 99) <= 6 { return jahr - 1 }
        return nil
    }

    /// Die Weihnachtsregel: Zu Beginn jeder Weihnachtszeit einmal automatisch auf Weihnachten,
    /// eine eigene Wahl in der Zeit bleibt, danach zurück zum vorherigen Design.
    public func geprueft(heute: Date, kalender: Calendar = .current) -> DesignStand {
        var neu = self
        if let jahr = Self.saisonJahr(heute, kalender: kalender) {
            if saison != jahr {
                if gewaehlt != .weihnachten { neu.vorher = gewaehlt }
                neu.gewaehlt = .weihnachten
                neu.saison = jahr
            }
        } else {
            if gewaehlt == .weihnachten { neu.gewaehlt = vorher ?? .standard }
            neu.vorher = nil
        }
        return neu
    }
}

/// Das gewählte Design der App. Farben aus `LilithColor` lesen es, darum zeichnen sich
/// alle Ansichten beim Wechsel von selbst neu.
@MainActor
@Observable
public final class DesignZustand {
    public static let shared = DesignZustand()

    public private(set) var stand: DesignStand
    public var design: Design { stand.gewaehlt }

    @ObservationIgnored private let speicher = UserDefaults.standard
    private static let schluessel = "luna.design"
    private static let schluesselVorher = "luna.design.vorher"
    private static let schluesselSaison = "luna.design.saison"

    private init() {
        let d = UserDefaults.standard
        stand = DesignStand(
            gewaehlt: d.string(forKey: Self.schluessel).flatMap(Design.init(rawValue:)) ?? .standard,
            vorher: d.string(forKey: Self.schluesselVorher).flatMap(Design.init(rawValue:)),
            saison: d.object(forKey: Self.schluesselSaison) as? Int)
        d.removeObject(forKey: "luna.weihnachten")  // alter Schalter, ersetzt durch die Auswahl
        pruefe()
    }

    private var testWeihnachten: Bool {
        #if DEBUG
        speicher.bool(forKey: "LilithWeihnachten")
        #else
        false
        #endif
    }

    /// Heute, zum Ansehen in der Entwickler-Version mit „-LilithWeihnachten YES“ ein Tag im Dezember.
    public var heute: Date {
        #if DEBUG
        if testWeihnachten {
            return Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 10, hour: 12)) ?? .now
        }
        #endif
        return .now
    }

    public var waehlbar: [Design] { Design.waehlbar(heute: heute) }

    /// Beim Start und wenn die App wieder nach vorn kommt: Weihnachtsregel anwenden.
    public func pruefe() {
        setze(stand.geprueft(heute: heute))
    }

    public func waehle(_ design: Design) {
        guard waehlbar.contains(design) else { return }
        var neu = stand
        neu.gewaehlt = design
        setze(neu)
    }

    private func setze(_ neu: DesignStand) {
        guard neu != stand else { return }
        stand = neu
        speicher.set(neu.gewaehlt.rawValue, forKey: Self.schluessel)
        speicher.set(neu.vorher?.rawValue, forKey: Self.schluesselVorher)
        // Der Testschalter merkt sich keine Weihnachtszeit, sonst bliebe der echte Wechsel am 1. Dezember aus.
        if let s = neu.saison, !testWeihnachten { speicher.set(s, forKey: Self.schluesselSaison) }
    }
}
