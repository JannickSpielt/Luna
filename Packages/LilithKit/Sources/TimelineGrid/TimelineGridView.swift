import SwiftUI

/// Auftrag, zu einem Monat zu springen (z. B. vom Scrubber).
public struct SprungAnfrage: Equatable, Sendable {
    public let id = UUID()
    public let section: Int
    public init(section: Int) { self.section = section }
}

/// Natives Timeline-Grid (UICollectionView bzw. NSCollectionView) für SwiftUI.
public struct TimelineGridView {
    let model: GridModel
    @Binding var zoom: GridZoom
    let sprung: SprungAnfrage?
    let onScroll: ((Double) -> Void)?

    public init(model: GridModel, zoom: Binding<GridZoom>, sprung: SprungAnfrage? = nil, onScroll: ((Double) -> Void)? = nil) {
        self.model = model
        self._zoom = zoom
        self.sprung = sprung
        self.onScroll = onScroll
    }

    @MainActor
    func macheController() -> TimelineGridController {
        let controller = TimelineGridController(model: model, zoom: zoom)
        controller.onScroll = onScroll
        let binding = $zoom
        controller.onZoomChange = { neu in
            if binding.wrappedValue != neu { binding.wrappedValue = neu }
        }
        return controller
    }

    @MainActor
    func aktualisiere(_ controller: TimelineGridController) {
        if controller.model.items.count != model.items.count { controller.model = model }
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

/// Vergleichsvariante in reinem SwiftUI. Nur für den Prototyp-Vergleich.
public struct SwiftUITimelineGrid: View {
    let model: GridModel
    let zoom: GridZoom
    let sprung: SprungAnfrage?
    let onScroll: ((Double) -> Void)?

    public init(model: GridModel, zoom: GridZoom, sprung: SprungAnfrage? = nil, onScroll: ((Double) -> Void)? = nil) {
        self.model = model
        self.zoom = zoom
        self.sprung = sprung
        self.onScroll = onScroll
    }

    public var body: some View {
        ScrollViewReader { proxy in
            inhalt
                .onScrollGeometryChange(for: Double.self) { geo in
                    let max = geo.contentSize.height - geo.containerSize.height
                    return max > 0 ? (geo.contentOffset.y + geo.contentInsets.top) / max : 0
                } action: { _, neu in
                    onScroll?(neu)
                }
                .onChange(of: sprung) { _, neu in
                    if let neu { proxy.scrollTo(neu.section, anchor: .top) }
                }
        }
    }

    private var inhalt: some View {
        let spalten = Array(repeating: SwiftUI.GridItem(.flexible(), spacing: 2), count: zoom.spalten)
        return ScrollView {
            LazyVGrid(columns: spalten, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.bereich, id: \.self) { index in
                            let item = model.items[index]
                            let c = GridPalette.rgb(item.farbe)
                            Rectangle()
                                .fill(Color(red: c.r, green: c.g, blue: c.b))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .bottomLeading) {
                                    if item.favorit {
                                        Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.white).padding(4)
                                    }
                                }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.titel).font(.system(.title3, design: .serif, weight: .semibold))
                            Spacer()
                            Text(section.untertitel).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(.bar)
                    }
                    .id(section.id)
                }
            }
        }
    }
}
