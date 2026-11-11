#if os(macOS)
import AppKit

/// Timeline-Grid für den Mac auf Basis von `NSCollectionView`.
@MainActor
public final class TimelineGridController: NSViewController, NSCollectionViewDataSource {
    public var model: GridModel { didSet { collectionView?.reloadData() } }
    public private(set) var zoom: GridZoom
    public var onZoomChange: ((GridZoom) -> Void)?

    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var lupeSchonGestuft = false

    public init(model: GridModel, zoom: GridZoom) {
        self.model = model
        self.zoom = zoom
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    public override func loadView() {
        collectionView = NSCollectionView()
        let layout = NSCollectionViewCompositionalLayout { [weak self] _, umgebung in
            self?.section(breite: umgebung.container.effectiveContentSize.width)
        }
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(GridItemView.self, forItemWithIdentifier: GridItemView.id)
        collectionView.register(MonatsKopfView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: MonatsKopfView.id)

        scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true
        view = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(gescrollt(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        let lupe = NSMagnificationGestureRecognizer(target: self, action: #selector(lupe(_:)))
        collectionView.addGestureRecognizer(lupe)
    }

    var letzterSprung: UUID?
    /// Scroll-Position von 0 (neuester Monat) bis 1 (ältester Monat).
    public var onScroll: ((Double) -> Void)?

    @objc private func gescrollt(_ notification: Notification) {
        let clip = scrollView.contentView
        let max = collectionView.frame.height - clip.bounds.height
        onScroll?(max > 0 ? Double(clip.bounds.minY / max) : 0)
    }

    /// Springt ohne Animation an den Anfang eines Monats.
    public func springe(zuSection section: Int) {
        guard section < model.sections.count, model.sections[section].anzahl > 0 else { return }
        collectionView.layoutSubtreeIfNeeded()
        if let kopf = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: NSCollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) {
            let clip = scrollView.contentView
            let maxY = max(0, collectionView.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: min(kopf.frame.minY, maxY)))
            scrollView.reflectScrolledClipView(clip)
            gescrollt(Notification(name: NSView.boundsDidChangeNotification))
        }
    }

    public func setZoom(_ neu: GridZoom, animiert: Bool = true) {
        guard neu != zoom else { return }
        wechsleZoom(zu: neu, anker: nil)
    }

    private func section(breite: CGFloat) -> NSCollectionLayoutSection {
        let spalten = CGFloat(zoom.spalten)
        let abstand: CGFloat = 3
        let kante = ((breite - abstand * (spalten - 1)) / spalten).rounded(.down)
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(kante), heightDimension: .absolute(kante)))
        let gruppe = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(kante)),
            subitem: item, count: zoom.spalten)
        gruppe.interItemSpacing = .fixed(abstand)
        let section = NSCollectionLayoutSection(group: gruppe)
        section.interGroupSpacing = abstand
        section.contentInsets = .init(top: 0, leading: 0, bottom: 20, trailing: 0)
        let kopf = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)),
            elementKind: NSCollectionView.elementKindSectionHeader, alignment: .top)
        kopf.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [kopf]
        return section
    }

    // MARK: - Daten

    public func numberOfSections(in collectionView: NSCollectionView) -> Int { model.sections.count }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        model.sections[section].anzahl
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: GridItemView.id, for: indexPath) as! GridItemView
        item.zeige(model[indexPath.section, indexPath.item])
        return item
    }

    public func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                               at indexPath: IndexPath) -> NSView {
        let kopf = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: MonatsKopfView.id, for: indexPath) as! MonatsKopfView
        kopf.zeige(model.sections[indexPath.section])
        return kopf
    }

    // MARK: - Zoom (Trackpad und ⌘+ / ⌘−)

    @objc private func lupe(_ geste: NSMagnificationGestureRecognizer) {
        switch geste.state {
        case .began:
            lupeSchonGestuft = false
        case .changed where !lupeSchonGestuft:
            var neu = zoom
            let geaendert = geste.magnification > 0.25 ? neu.groesser() : (geste.magnification < -0.2 ? neu.kleiner() : false)
            guard geaendert else { return }
            lupeSchonGestuft = true
            let punkt = geste.location(in: collectionView)
            wechsleZoom(zu: neu, anker: collectionView.indexPathForItem(at: punkt))
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        default:
            break
        }
    }

    private func wechsleZoom(zu neu: GridZoom, anker: IndexPath?) {
        let sichtbar = collectionView.indexPathsForVisibleItems().sorted()
        let anker = anker ?? sichtbar.dropFirst(sichtbar.count / 2).first
        let clip = scrollView.contentView
        let ankerY = anker.flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame.midY }.map { $0 - clip.bounds.minY }
        zoom = neu
        onZoomChange?(neu)
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        if let anker, let ankerY, let rahmen = collectionView.layoutAttributesForItem(at: anker)?.frame {
            let maxY = max(0, collectionView.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: min(max(rahmen.midY - ankerY, 0), maxY)))
            scrollView.reflectScrolledClipView(clip)
        }
    }
}

// MARK: - Zellen

final class GridItemView: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("GridItemView")
    private let badge = NSTextField(labelWithString: "")
    private let herz = NSImageView(image: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Favorit")!)

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        herz.contentTintColor = .white
        for sub in [badge, herz] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.shadow = { let s = NSShadow(); s.shadowBlurRadius = 2; s.shadowColor = .black.withAlphaComponent(0.6); return s }()
            v.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -5),
            badge.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            herz.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 5),
            herz.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -5),
            herz.widthAnchor.constraint(equalToConstant: 12), herz.heightAnchor.constraint(equalToConstant: 12),
        ])
        view = v
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 3 : 0
            view.layer?.borderColor = NSColor(srgbRed: 0.894, green: 0.416, blue: 0.549, alpha: 1).cgColor
        }
    }

    func zeige(_ item: GridItem) {
        let c = GridPalette.rgb(item.farbe)
        view.layer?.backgroundColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).cgColor
        let klein = view.bounds.width < 50
        badge.isHidden = item.art != .video || klein
        if item.art == .video { badge.stringValue = String(format: "%d:%02d", item.dauer / 60, item.dauer % 60) }
        herz.isHidden = !item.favorit || klein
        view.setAccessibilityLabel(item.art == .video ? "Video" : "Foto")
    }
}

final class MonatsKopfView: NSVisualEffectView, NSCollectionViewElement {
    static let id = NSUserInterfaceItemIdentifier("MonatsKopfView")
    private let titel = NSTextField(labelWithString: "")
    private let untertitel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .headerView
        blendingMode = .withinWindow
        let serif = NSFont.systemFont(ofSize: 20, weight: .semibold).fontDescriptor.withDesign(.serif)
        titel.font = serif.flatMap { NSFont(descriptor: $0, size: 20) } ?? .systemFont(ofSize: 20, weight: .semibold)
        untertitel.font = .systemFont(ofSize: 12)
        untertitel.textColor = .secondaryLabelColor
        let stapel = NSStackView(views: [titel, NSView(), untertitel])
        stapel.alignment = .firstBaseline
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stapel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func zeige(_ section: GridSection) {
        titel.stringValue = section.titel
        untertitel.stringValue = section.untertitel
    }
}
#endif
