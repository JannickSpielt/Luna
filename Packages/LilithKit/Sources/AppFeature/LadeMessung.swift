import Foundation
import os

/// Zeitmessung fürs Laden: Signposts für Instruments und eine Zeile im Log („Luna Laden“),
/// damit man vorher und nachher vergleichen kann.
enum LadeMessung {
    static let signposter = OSSignposter(subsystem: "app.lilith", category: "Laden")
    static let log = Logger(subsystem: "app.lilith", category: "Laden")

    /// Misst einen Abschnitt und schreibt die Dauer ins Log.
    @MainActor
    static func miss<T>(_ name: StaticString, _ detail: String = "", _ arbeit: () async throws -> T) async rethrows -> T {
        let id = signposter.makeSignpostID()
        let zustand = signposter.beginInterval(name, id: id)
        let start = ContinuousClock.now
        defer {
            signposter.endInterval(name, zustand)
            let ms = (ContinuousClock.now - start).components.attoseconds / 1_000_000_000_000_000
                + (ContinuousClock.now - start).components.seconds * 1000
            log.info("\(name, privacy: .public) \(detail, privacy: .public): \(ms) ms")
        }
        return try await arbeit()
    }

    static func ereignis(_ text: String) {
        signposter.emitEvent("Ereignis")
        log.info("\(text, privacy: .public)")
    }
}
