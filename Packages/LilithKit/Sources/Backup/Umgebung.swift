import Foundation
import Network
#if os(iOS)
import UIKit
#endif

/// Was das automatische Backup über das Gerät wissen muss: Netz, Strom, Speicher.
@MainActor
public protocol Umgebung: AnyObject {
    /// WLAN oder Kabel, kein Mobilfunk und kein Datensparmodus.
    var imWLAN: Bool { get }
    /// Am Ladekabel (oder voll geladen und eingesteckt).
    var amStrom: Bool { get }
    /// Freier Speicher in Bytes.
    var freierSpeicher: Int64 { get }
}

/// Die echte Umgebung des Geräts.
@MainActor
public final class GeraeteUmgebung: Umgebung {
    public static let geteilt = GeraeteUmgebung()

    private let monitor = NWPathMonitor()
    private var pfadIstWLAN = false

    private init() {
        monitor.pathUpdateHandler = { pfad in
            let wlan = pfad.status == .satisfied && !pfad.isExpensive && !pfad.isConstrained
            Task { @MainActor in GeraeteUmgebung.geteilt.pfadIstWLAN = wlan }
        }
        monitor.start(queue: DispatchQueue(label: "app.lilith.netz"))
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
    }

    /// Einmal früh aufrufen, damit der Netzstatus bekannt ist, wenn er gebraucht wird.
    public static func starte() { _ = geteilt }

    public var imWLAN: Bool { pfadIstWLAN || (monitor.currentPath.status == .satisfied && !monitor.currentPath.isExpensive
                                              && !monitor.currentPath.isConstrained) }

    public var amStrom: Bool {
        #if os(iOS)
        switch UIDevice.current.batteryState {
        case .charging, .full: return true
        // Im Simulator unbekannt: dann nicht blockieren.
        case .unknown: return true
        default: return false
        }
        #else
        return true
        #endif
    }

    public var freierSpeicher: Int64 {
        let werte = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return werte?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}

/// Einstellungen des automatischen Backups.
public struct BackupEinstellungen: Codable, Equatable, Sendable {
    /// Nur über WLAN hochladen.
    public var nurWLAN = true
    /// Nur sichern, wenn das Gerät lädt.
    public var nurBeimLaden = false
    /// Videos mitsichern.
    public var videos = true
    /// Originale aus iCloud laden, wenn sie nicht auf dem Gerät liegen („Speicher optimieren“).
    public var iCloud = true

    public init() {}
}
