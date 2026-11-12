import Foundation
import GRDB

/// Ein Foto oder Video aus der Mediathek des Geräts und was Lilith darüber weiß.
/// So muss die Prüfsumme nur einmal berechnet werden, und der Stand übersteht einen Neustart.
public struct LokalesFoto: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    public enum Zustand: String, Codable, Sendable, CaseIterable {
        /// Neu oder geändert: Prüfsumme fehlt oder ist noch nicht beim Server nachgefragt.
        case neu
        /// Der Server hat es nicht: muss hochgeladen werden.
        case bereit
        /// Liegt als Upload-Auftrag in der Warteschlange.
        case eingereiht
        /// Ist auf dem Server.
        case gesichert
        /// Hochladen ist gescheitert (Grund in `grund`).
        case fehler
        /// Wird bewusst nicht gesichert, z. B. weil das Original nur in iCloud liegt.
        case uebersprungen
    }

    public static let databaseTableName = "lokales_foto"

    public var konto: String
    public var lokaleId: String
    public var erstellt: Date
    public var geaendert: Date
    public var istVideo: Bool
    public var pruefsumme: String?
    public var zustand: Zustand
    public var remoteId: String?
    public var grund: String?

    enum CodingKeys: String, CodingKey {
        case konto, lokaleId = "lokale_id", erstellt, geaendert, istVideo = "ist_video"
        case pruefsumme, zustand, remoteId = "remote_id", grund
    }

    public init(konto: String, lokaleId: String, erstellt: Date, geaendert: Date, istVideo: Bool) {
        self.konto = konto; self.lokaleId = lokaleId; self.erstellt = erstellt; self.geaendert = geaendert
        self.istVideo = istVideo; self.zustand = .neu
    }
}

/// Was die Mediathek über ein Foto meldet (ohne Daten).
public struct MediumKopf: Sendable, Hashable {
    public var id: String
    public var erstellt: Date
    public var geaendert: Date
    public var istVideo: Bool

    public init(id: String, erstellt: Date, geaendert: Date, istVideo: Bool) {
        self.id = id; self.erstellt = erstellt; self.geaendert = geaendert; self.istVideo = istVideo
    }
}

extension Datenbank {
    /// Gleicht die Liste der Mediathek mit der Datenbank ab: Neues aufnehmen, Geändertes neu prüfen,
    /// Gelöschtes entfernen. Was gerade in der Warteschlange liegt, bleibt unangetastet.
    public func gleicheAb(konto: String, medien: [MediumKopf]) throws {
        try pool.write { db in
            var bekannt: [String: LokalesFoto] = [:]
            for f in try LokalesFoto.filter(Column("konto") == konto).fetchAll(db) { bekannt[f.lokaleId] = f }
            for m in medien {
                if var f = bekannt.removeValue(forKey: m.id) {
                    // Bearbeitet (z. B. zugeschnitten): neue Prüfsumme, neu sichern.
                    if m.geaendert.timeIntervalSince(f.geaendert) > 1, f.zustand != .eingereiht {
                        f.geaendert = m.geaendert
                        f.pruefsumme = nil
                        f.remoteId = nil
                        f.grund = nil
                        f.zustand = .neu
                        try f.update(db)
                    }
                } else {
                    try LokalesFoto(konto: konto, lokaleId: m.id, erstellt: m.erstellt, geaendert: m.geaendert,
                                    istVideo: m.istVideo).insert(db)
                }
            }
            // Nicht mehr in der Mediathek (gelöscht oder Zugriff entzogen).
            for f in bekannt.values where f.zustand != .eingereiht {
                try f.delete(db)
            }
        }
    }

    /// Fotos eines Zustands, die neuesten zuerst (damit frische Fotos schnell gesichert sind).
    public func lokaleFotos(konto: String, zustand: LokalesFoto.Zustand, hoechstens: Int = .max) throws -> [LokalesFoto] {
        try pool.read { db in
            try LokalesFoto.filter(Column("konto") == konto && Column("zustand") == zustand.rawValue)
                .order(Column("erstellt").desc)
                .limit(hoechstens)
                .fetchAll(db)
        }
    }

    public func aktualisiere(_ fotos: [LokalesFoto]) throws {
        try pool.write { db in
            for f in fotos { try f.update(db) }
        }
    }

    /// Setzt den Zustand eines Fotos der Mediathek (z. B. nach dem Upload).
    public func setzeLokal(konto: String, lokaleId: String, zustand: LokalesFoto.Zustand,
                           remoteId: String? = nil, grund: String? = nil) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE lokales_foto SET zustand = ?, remote_id = COALESCE(?, remote_id), grund = ?
                WHERE konto = ? AND lokale_id = ?
                """, arguments: [zustand.rawValue, remoteId, grund, konto, lokaleId])
        }
    }

    /// Server-IDs der gesicherten Fotos aus einer Menge lokaler Kennungen.
    public func remoteIds(konto: String, lokaleIds: Set<String>) throws -> [String] {
        try pool.read { db in
            try LokalesFoto.filter(Column("konto") == konto && Column("zustand") == LokalesFoto.Zustand.gesichert.rawValue)
                .fetchAll(db)
                .filter { lokaleIds.contains($0.lokaleId) }
                .compactMap(\.remoteId)
        }
    }

    /// Übersprungene Fotos mit diesem Grund neu prüfen (z. B. wenn iCloud-Originale jetzt erlaubt sind).
    public func pruefeErneut(konto: String, grund: String) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE lokales_foto SET zustand = 'neu', grund = NULL WHERE konto = ? AND zustand = 'uebersprungen' AND grund = ?",
                           arguments: [konto, grund])
        }
    }

    /// Anzahl der Fotos je Zustand.
    public func zaehleLokal(konto: String) throws -> [LokalesFoto.Zustand: Int] {
        try pool.read { db in
            var ergebnis: [LokalesFoto.Zustand: Int] = [:]
            let zeilen = try Row.fetchAll(db, sql: "SELECT zustand, COUNT(*) AS n FROM lokales_foto WHERE konto = ? GROUP BY zustand",
                                          arguments: [konto])
            for z in zeilen {
                if let zustand = LokalesFoto.Zustand(rawValue: z["zustand"]) { ergebnis[zustand] = z["n"] }
            }
            return ergebnis
        }
    }

    /// Nach einem Absturz: „eingereiht“ ohne offenen Auftrag zurück auf „bereit“, damit es nicht hängen bleibt.
    public func raeumeLokalAuf(konto: String) throws {
        try pool.write { db in
            try db.execute(sql: """
                UPDATE lokales_foto SET zustand = 'bereit'
                WHERE konto = ? AND zustand = 'eingereiht' AND lokale_id NOT IN (
                    SELECT lokale_id FROM upload_auftrag
                    WHERE konto = ? AND lokale_id IS NOT NULL AND zustand IN ('wartet', 'laeuft', 'fehler'))
                """, arguments: [konto, konto])
        }
    }
}
