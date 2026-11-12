import Foundation
import GRDB

/// Ein Foto oder Video, das hochgeladen werden soll. Jeder Schritt wird gespeichert,
/// damit nach einem Abbruch an der richtigen Stelle weitergemacht wird.
public struct UploadAuftrag: Codable, Sendable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public enum Zustand: String, Codable, Sendable, CaseIterable {
        /// Wartet darauf, geprüft und hochgeladen zu werden.
        case wartet
        /// Wird gerade hochgeladen.
        case laeuft
        /// Fertig hochgeladen.
        case fertig
        /// War schon auf dem Server.
        case duplikat
        /// Endgültig gescheitert (nach mehreren Versuchen oder bei Fehlern, die sich nicht von selbst lösen).
        case fehler
    }

    public static let databaseTableName = "upload_auftrag"

    public var id: Int64?
    /// Kennung des Kontos (Server und Nutzer), damit Aufträge nie beim falschen Server landen.
    public var konto: String
    /// Woher die Datei kam, z. B. „auswahl“ (Foto-Auswahl) oder „datei“ (Mac).
    public var quelle: String
    /// Pfad der Kopie, die bis zum Ende des Uploads aufbewahrt wird.
    public var datei: String
    public var dateiname: String
    public var erstellt: Date
    public var geaendert: Date
    public var dauerMs: Int?
    public var istVideo: Bool
    /// Ziel-Album, falls aus einem Album heraus hochgeladen wurde.
    public var albumId: String?
    public var pruefsumme: String?
    public var zustand: Zustand
    public var versuche: Int
    public var fehler: String?
    public var remoteId: String?
    public var angelegt: Date

    enum CodingKeys: String, CodingKey {
        case id, konto, quelle, datei, dateiname, erstellt, geaendert
        case dauerMs = "dauer_ms", istVideo = "ist_video", albumId = "album_id"
        case pruefsumme, zustand, versuche, fehler
        case remoteId = "remote_id", angelegt
    }

    public init(konto: String, quelle: String, datei: String, dateiname: String, erstellt: Date, geaendert: Date,
                dauerMs: Int? = nil, istVideo: Bool = false, albumId: String? = nil) {
        self.konto = konto; self.quelle = quelle; self.datei = datei; self.dateiname = dateiname
        self.erstellt = erstellt; self.geaendert = geaendert; self.dauerMs = dauerMs; self.istVideo = istVideo
        self.albumId = albumId; self.zustand = .wartet; self.versuche = 0; self.angelegt = Date()
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Datenbank {
    public func speichere(_ auftraege: [UploadAuftrag]) throws -> [UploadAuftrag] {
        try pool.write { db in
            try auftraege.map { a in
                var neu = a
                try neu.insert(db)
                return neu
            }
        }
    }

    public func aktualisiere(_ auftrag: UploadAuftrag) throws {
        try pool.write { db in try auftrag.update(db) }
    }

    /// Offene Aufträge eines Kontos in Reihenfolge des Anlegens.
    public func offeneAuftraege(konto: String) throws -> [UploadAuftrag] {
        try pool.read { db in
            try UploadAuftrag
                .filter(Column("konto") == konto)
                .filter([UploadAuftrag.Zustand.wartet.rawValue, UploadAuftrag.Zustand.laeuft.rawValue].contains(Column("zustand")))
                .order(Column("id"))
                .fetchAll(db)
        }
    }

    public func auftraege(konto: String, zustand: UploadAuftrag.Zustand) throws -> [UploadAuftrag] {
        try pool.read { db in
            try UploadAuftrag.filter(Column("konto") == konto && Column("zustand") == zustand.rawValue)
                .order(Column("id")).fetchAll(db)
        }
    }

    /// Nach einem Absturz: Was als „läuft“ markiert ist, läuft nicht mehr – zurück auf „wartet“.
    public func setzeLaufendeZurueck(konto: String) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE upload_auftrag SET zustand = 'wartet' WHERE konto = ? AND zustand = 'laeuft'",
                           arguments: [konto])
        }
    }

    /// Erledigte Aufträge aufräumen (fertig, Duplikat), damit die Datenbank klein bleibt.
    public func entferneErledigte(konto: String) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM upload_auftrag WHERE konto = ? AND zustand IN ('fertig', 'duplikat')",
                           arguments: [konto])
        }
    }

    public func entferne(_ auftrag: UploadAuftrag) throws {
        _ = try pool.write { db in try auftrag.delete(db) }
    }
}
