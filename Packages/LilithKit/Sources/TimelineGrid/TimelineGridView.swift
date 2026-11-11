import SwiftUI

/// Auftrag, zu einem Monat zu springen (z. B. vom Scrubber).
public struct SprungAnfrage: Equatable, Sendable {
    public let id = UUID()
    public let section: Int
    public init(section: Int) { self.section = section }
}

/// Natives Timeline-Grid (UICollectionView bzw. NSCollectionView) für SwiftUI.
public struct TimelineGridView {
    let quelle: TimelineQuelle
    @Binding var zoom: GridZoom
    let sprung: SprungAnfrage?
    let onScroll: ((Double) -> Void)?
    let onTap: ((Int, Int, CGRect) -> Void)?
    let auswahlModus: Bool
    let auswahlStand: Int
    let onAuswahl: (([String]) -> Void)?

    /// - Parameter auswahlStand: Ändert sich der Wert, wird die Auswahl geleert.
    public init(quelle: TimelineQuelle, zoom: Binding<GridZoom>, sprung: SprungAnfrage? = nil,
                auswahlModus: Bool = false, auswahlStand: Int = 0, onAuswahl: (([String]) -> Void)? = nil,
                onTap: ((Int, Int, CGRect) -> Void)? = nil, onScroll: ((Double) -> Void)? = nil) {
        self.onTap = onTap
        self.auswahlModus = auswahlModus
        self.auswahlStand = auswahlStand
        self.onAuswahl = onAuswahl
        self.quelle = quelle
        self._zoom = zoom
        self.sprung = sprung
        self.onScroll = onScroll
    }

    @MainActor
    func macheController() -> TimelineGridController {
        let controller = TimelineGridController(quelle: quelle, zoom: zoom)
        controller.onScroll = onScroll
        controller.onTap = onTap
        controller.onAuswahl = onAuswahl
        controller.auswahlModus = auswahlModus
        controller.auswahlStand = auswahlStand
        let binding = $zoom
        controller.onZoomChange = { neu in
            if binding.wrappedValue != neu { binding.wrappedValue = neu }
        }
        return controller
    }

    @MainActor
    func aktualisiere(_ controller: TimelineGridController) {
        if controller.quelle !== quelle { controller.quelle = quelle }
        controller.onScroll = onScroll
        controller.onTap = onTap
        controller.onAuswahl = onAuswahl
        controller.auswahlModus = auswahlModus
        if controller.auswahlStand != auswahlStand {
            controller.auswahlStand = auswahlStand
            controller.leereAuswahl()
        }
        controller.setZoom(zoom)
        if let sprung, sprung.id != controller.letzterSprung {
            controller.letzterSprung = sprung.id
            controller.springe(zuSection: sprung.section)
        }
    }
}

#if canImport(UIKit)
extension TimelineGridView: UIViewControllerRepresentable {
    public func makeUIViewController(context: Context) -> TimelineGridController { macheController() }
    public func updateUIViewController(_ controller: TimelineGridController, context: Context) { aktualisiere(controller) }
}
#elseif os(macOS)
extension TimelineGridView: NSViewControllerRepresentable {
    public func makeNSViewController(context: Context) -> TimelineGridController { macheController() }
    public func updateNSViewController(_ controller: TimelineGridController, context: Context) { aktualisiere(controller) }
}
#endif
