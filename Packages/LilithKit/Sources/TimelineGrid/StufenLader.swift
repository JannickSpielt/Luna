import Foundation
import Nuke
#if canImport(UIKit)
import UIKit
public typealias PlattformBild = UIImage
#else
import AppKit
public typealias PlattformBild = NSImage
#endif

/// Lädt ein Bild in Stufen: erst klein und schnell, dann scharf.
/// Kommt eine schärfere Stufe zuerst an, wird die kleinere ignoriert.
@MainActor
final class StufenLader {
    private var aufgaben: [ImageTask] = []
    private var besteStufe = -1
    private var kennung = 0

    func lade(_ anfragen: [ImageRequest], zeige: @escaping (PlattformBild, _ sofort: Bool) -> Void) {
        abbrechen()
        let meine = kennung
        for (stufe, anfrage) in anfragen.enumerated() {
            // Schon im Speicher? Dann sofort zeigen, ohne Netz.
            if let bild = ImagePipeline.shared.cache.cachedImage(for: anfrage)?.image {
                if stufe > besteStufe { besteStufe = stufe; zeige(bild, true) }
                continue
            }
            let aufgabe = ImagePipeline.shared.loadImage(with: anfrage) { [weak self] ergebnis in
                MainActor.assumeIsolated {
                    guard let self, self.kennung == meine, case .success(let antwort) = ergebnis,
                          stufe > self.besteStufe else { return }
                    self.besteStufe = stufe
                    zeige(antwort.image, false)
                }
            }
            aufgaben.append(aufgabe)
        }
    }

    func abbrechen() {
        aufgaben.forEach { $0.cancel() }
        aufgaben = []
        besteStufe = -1
        kennung &+= 1
    }
}
