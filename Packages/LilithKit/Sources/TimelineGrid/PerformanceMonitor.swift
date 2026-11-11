import Foundation
import Observation
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Misst Bildrate, Ruckler und Speicher. Nur für Prototyp und Debug-Builds gedacht.
@MainActor
@Observable
public final class PerformanceMonitor {
    /// Bilder pro Sekunde in der letzten Sekunde.
    public private(set) var fps = 0
    /// Ruckler (Bilder, die mehr als doppelt so lange brauchten wie vorgesehen) seit dem Zurücksetzen.
    public private(set) var ruckler = 0
    /// Längstes Bild seit dem Zurücksetzen in Millisekunden.
    public private(set) var laengstesBildMs = 0.0
    /// Speicherverbrauch der App in MB.
    public private(set) var speicherMB = 0.0

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var proxy: Proxy?
    @ObservationIgnored private var letzterZeitpunkt: CFTimeInterval = 0
    @ObservationIgnored private var bilder = 0
    @ObservationIgnored private var sekundenStart: CFTimeInterval = 0

    public init() {}

    public func start() {
        guard link == nil else { return }
        let proxy = Proxy(monitor: self)
        #if canImport(UIKit)
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        #else
        guard let link = NSScreen.main?.displayLink(target: proxy, selector: #selector(Proxy.tick(_:))) else { return }
        #endif
        link.add(to: .main, forMode: .common)
        self.link = link
        self.proxy = proxy
    }

    public func stop() {
        link?.invalidate()
        link = nil
        proxy = nil
        letzterZeitpunkt = 0
    }

    public func zuruecksetzen() {
        ruckler = 0
        laengstesBildMs = 0
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let jetzt = link.timestamp
        let soll = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
        if letzterZeitpunkt > 0 {
            let dauer = jetzt - letzterZeitpunkt
            if dauer > soll * 2.0 { ruckler += 1 }
            laengstesBildMs = max(laengstesBildMs, dauer * 1000)
        }
        letzterZeitpunkt = jetzt
        bilder += 1
        if sekundenStart == 0 { sekundenStart = jetzt }
        if jetzt - sekundenStart >= 1 {
            fps = Int((Double(bilder) / (jetzt - sekundenStart)).rounded())
            bilder = 0
            sekundenStart = jetzt
            speicherMB = Self.speicher()
        }
    }

    static func speicher() -> Double {
        var info = task_vm_info_data_t()
        var anzahl = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let ergebnis = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(anzahl)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &anzahl)
            }
        }
        return ergebnis == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private final class Proxy: NSObject {
        weak var monitor: PerformanceMonitor?
        init(monitor: PerformanceMonitor) { self.monitor = monitor }
        @MainActor @objc func tick(_ link: CADisplayLink) { monitor?.tick(link) }
    }
}
