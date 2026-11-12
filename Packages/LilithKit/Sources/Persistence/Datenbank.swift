import Foundation
import GRDB

/// Die lokale Datenbank von Lilith (SQLite über GRDB).
public final class Datenbank: Sendable {
    public let pool: any DatabaseWriter

    /// Datenbank im App-Ordner („Application Support/Lilith“).
    public static func standard() throws -> Datenbank {
        let ordner = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appending(path: "Lilith", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return try Datenbank(pool: DatabasePool(path: ordner.appending(path: "lilith.sqlite").path))
    }

    /// Datenbank nur im Arbeitsspeicher, für Tests.
    public static func imSpeicher() throws -> Datenbank {
        try Datenbank(pool: DatabaseQueue())
    }

    init(pool: any DatabaseWriter) throws {
        self.pool = pool
        try Self.migrator.migrate(pool)
    }

    /// Alle Änderungen am Aufbau, in Reihenfolge. Nie bestehende Schritte ändern, nur neue anhängen.
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1-upload-auftraege") { db in
            try db.create(table: "upload_auftrag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("konto", .text).notNull()
                t.column("quelle", .text).notNull()
                t.column("datei", .text).notNull()
                t.column("dateiname", .text).notNull()
                t.column("erstellt", .datetime).notNull()
                t.column("geaendert", .datetime).notNull()
                t.column("dauer_ms", .integer)
                t.column("ist_video", .boolean).notNull().defaults(to: false)
                t.column("album_id", .text)
                t.column("pruefsumme", .text)
                t.column("zustand", .text).notNull()
                t.column("versuche", .integer).notNull().defaults(to: 0)
                t.column("fehler", .text)
                t.column("remote_id", .text)
                t.column("angelegt", .datetime).notNull()
            }
            try db.create(index: "upload_auftrag_zustand", on: "upload_auftrag", columns: ["konto", "zustand"])
        }
        m.registerMigration("v2-mediathek") { db in
            // Welches Foto der Mediathek zu welchem Auftrag gehört, und das Video eines Live Photos.
            try db.alter(table: "upload_auftrag") { t in
                t.add(column: "lokale_id", .text)
                t.add(column: "live_video_datei", .text)
            }
            // Ein Eintrag pro Foto oder Video der Mediathek: was Lilith darüber weiß.
            try db.create(table: "lokales_foto") { t in
                t.column("konto", .text).notNull()
                t.column("lokale_id", .text).notNull()
                t.column("erstellt", .datetime).notNull()
                t.column("geaendert", .datetime).notNull()
                t.column("ist_video", .boolean).notNull().defaults(to: false)
                t.column("pruefsumme", .text)
                t.column("zustand", .text).notNull()
                t.column("remote_id", .text)
                t.column("grund", .text)
                t.primaryKey(["konto", "lokale_id"])
            }
            try db.create(index: "lokales_foto_zustand", on: "lokales_foto", columns: ["konto", "zustand"])
        }
        return m
    }
}
