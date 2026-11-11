import Foundation

/// Fehler, die beim Sprechen mit dem Immich-Server auftreten können.
/// Die Texte sind für Menschen gedacht und schlagen eine Lösung vor.
public enum ImmichError: Error, Equatable, Sendable, LocalizedError {
    case ungueltigeAdresse
    case nichtErreichbar(String)
    case keinImmichServer
    case versionZuAlt(ServerVersion)
    case passwortLoginAus
    case falscheZugangsdaten
    case sitzungAbgelaufen
    case unerwarteteAntwort(Int)

    public var errorDescription: String? {
        switch self {
        case .ungueltigeAdresse:
            "Das sieht nicht wie eine Serveradresse aus. Beispiel: fotos.example.de"
        case .nichtErreichbar(let grund):
            "Server nicht erreichbar. Prüfe die Adresse und deine Verbindung. (\(grund))"
        case .keinImmichServer:
            "Unter dieser Adresse antwortet kein Immich-Server."
        case .versionZuAlt(let v):
            "Dein Server läuft mit Immich \(v). Lilith braucht mindestens \(ServerVersion.minimum)."
        case .passwortLoginAus:
            "Auf diesem Server ist die Anmeldung mit Passwort ausgeschaltet. Nutze einen API-Key."
        case .falscheZugangsdaten:
            "E-Mail, Passwort oder API-Key stimmen nicht."
        case .sitzungAbgelaufen:
            "Deine Anmeldung ist abgelaufen. Bitte melde dich neu an."
        case .unerwarteteAntwort(let code):
            "Der Server hat unerwartet geantwortet (Status \(code))."
        }
    }
}
