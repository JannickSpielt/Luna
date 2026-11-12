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
    /// Kennung des Fotos in der Mediathek (automatisches Backup), sonst `nil`.
    public var lokaleId: String?
    /// Bei Live Photos: das zugehörige Video. Es wird zuerst (versteckt) hochgeladen.
    public var liveVideoDatei: String?

    enum CodingKeys: String, CodingKey {
        case id, konto, quelle, datei, dateiname, erstellt, geaendert
        case dauerMs = "dauer_ms", istVideo = "ist_video", albumId = "album_id"
        case pruefsumme, zustand, versuche, fehler
        case remoteId = "remote_id", angelegt
        case lokaleId = "lokale_id", liveVideoDatei = "live_video_datei"
    }

    public init(konto: String, quelle: String, datei: String, dateiname: String, erstellt: Date, geaendert: Date,
                dauerMs: Int? = nil, istVideo: Bool = false, albumId: String? = nil,
                lokaleId: String? = nil, liveVideoDatei: String? = nil) {
        self.konto = konto; self.quelle = quelle; self.datei = datei; self.dateiname = dateiname
        self.erstellt = erstellt; self.geaendert = geaendert; self.dauerMs = dauerMs; self.istVideo = istVideo
        self.albumId = albumId; self.zustand = .wartet; self.versuche = 0; self.angelegt = Date()
        self.lokaleId = lokaleId; self.liveVideoDatei = liveVideoDatei
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
    /// Ausgenommen sind Aufträge, die iOS noch im Hintergrund hochlädt.
    public func setzeLaufendeZurueck(konto: String, ausser: Set<Int64> = []) throws {
        try pool.write { db in
            let laufend = try UploadAuftrag.filter(Column("konto") == konto && Column("zustand") == UploadAuftrag.Zustand.laeuft.rawValue)
                .fetchAll(db)
            for var a in laufend where !ausser.contains(a.id ?? -1) {
                a.zustand = .wartet
                try a.update(db)
            }
        }
    }

    public func auftrag(id: Int64) throws -> UploadAuftrag? {
        try pool.read { db in try UploadAuftrag.fetchOne(db, key: id) }
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
