import Foundation
import Nuke
#if canImport(UIKit)
import UIKit
public typealias PlattformBild = UIImage
#else
import AppKit
public typealias PlattformBild = NSImage
#endif

/// Lädt ein Bild in Stufen: erst klein und schnell (hohe Priorität), danach scharf (niedrige Priorität).
/// Die scharfe Stufe startet erst, wenn die kleine da ist. So blockieren große Bilder nie die kleinen.
@MainActor
final class StufenLader {
    private var aufgabe: ImageTask?
    private var kennung = 0

    func lade(_ anfragen: [ImageRequest], zeige: @escaping (PlattformBild, _ sofort: Bool) -> Void) {
        abbrechen()
        // Von der schärfsten Stufe abwärts: Was schon im Speicher liegt, wird sofort gezeigt.
        for (stufe, anfrage) in anfragen.enumerated().reversed() {
            if let bild = ImagePipeline.shared.cache.cachedImage(for: anfrage)?.image {
                zeige(bild, true)
                if stufe == anfragen.count - 1 { return }
                ladeStufe(stufe + 1, von: anfragen, kennung: kennung, zeige: zeige)
                return
            }
        }
        ladeStufe(0, von: anfragen, kennung: kennung, zeige: zeige)
    }

    private func ladeStufe(_ stufe: Int, von anfragen: [ImageRequest], kennung meine: Int,
                           zeige: @escaping (PlattformBild, Bool) -> Void) {
        guard stufe < anfragen.count else { return }
        var anfrage = anfragen[stufe]
        anfrage.priority = stufe == 0 ? .high : .low
        aufgabe = ImagePipeline.shared.loadImage(with: anfrage) { [weak self] ergebnis in
            MainActor.assumeIsolated {
                guard let self, self.kennung == meine else { return }
                if case .success(let antwort) = ergebnis { zeige(antwort.image, false) }
                self.ladeStufe(stufe + 1, von: anfragen, kennung: meine, zeige: zeige)
            }
        }
    }

    func abbrechen() {
        aufgabe?.cancel()
        aufgabe = nil
        kennung &+= 1
    }
}
