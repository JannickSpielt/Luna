#if os(macOS)
import AppKit
import Nuke

/// Timeline-Grid für den Mac auf Basis von `NSCollectionView`.
@MainActor
public final class TimelineGridController: NSViewController, NSCollectionViewDataSource, NSCollectionViewPrefetching,
    NSCollectionViewDelegate {
    public var quelle: TimelineQuelle {
        didSet { verbindeQuelle(); collectionView?.reloadData() }
    }
    public private(set) var zoom: GridZoom
    public var onZoomChange: ((GridZoom) -> Void)?
    /// Scroll-Position von 0 (neuester Monat) bis 1 (ältester Monat).
    public var onScroll: ((Double) -> Void)?
    var letzterSprung: UUID?
    /// Ein Foto wurde doppelt angeklickt: Monat, Position und Rahmen der Kachel im Fenster (Ursprung oben links).
    public var onTap: ((Int, Int, CGRect) -> Void)?

    /// Auf dem Mac ist die Auswahl immer möglich (Klick, ⌘-Klick, ⇧-Klick). Der Schalter existiert nur für iOS.
    public var auswahlModus = false
    /// Meldet die IDs der markierten Fotos.
    public var onAuswahl: (([String]) -> Void)?
    var auswahlStand = 0

    public func leereAuswahl() {
        collectionView?.deselectAll(nil)
        onAuswahl?([])
    }

    private func meldeAuswahl() {
        let ids = collectionView.selectionIndexPaths.sorted().compactMap { quelle.item(section: $0.section, index: $0.item)?.id }
        onAuswahl?(ids)
    }

    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { meldeAuswahl() }
    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { meldeAuswahl() }

    @objc private func doppelklick(_ geste: NSClickGestureRecognizer) {
        guard let pfad = collectionView.indexPathForItem(at: geste.location(in: collectionView)),
              quelle.item(section: pfad.section, index: pfad.item) != nil,
              let ansicht = collectionView.item(at: pfad)?.view else { return }
        var rahmen = ansicht.convert(ansicht.bounds, to: nil)
        if let hoehe = view.window?.contentView?.bounds.height { rahmen.origin.y = hoehe - rahmen.maxY }
        onTap?(pfad.section, pfad.item, rahmen)
    }

    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var lupeSchonGestuft = false
    private let vorlader = ImagePrefetcher(pipeline: .shared, destination: .memoryCache, maxConcurrentRequestCount: 4)

    public init(quelle: TimelineQuelle, zoom: GridZoom) {
        self.quelle = quelle
        self.zoom = zoom
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    public override func loadView() {
        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = NSCollectionViewCompositionalLayout { [weak self] _, umgebung in
            self?.section(breite: umgebung.container.effectiveContentSize.width)
        }
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        view = scrollView

        NotificationCenter.default.addObserver(self, selector: #selector(gescrollt),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        collectionView.addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(lupe(_:))))
        let klick = NSClickGestureRecognizer(target: self, action: #selector(doppelklick(_:)))
        klick.numberOfClicksRequired = 2
        klick.delaysPrimaryMouseButtonEvents = false
        collectionView.addGestureRecognizer(klick)
        verbindeQuelle()
    }

    private func verbindeQuelle() {
        quelle.onMonatGeladen = { [weak self] section, anzahlGeaendert in
            self?.monatGeladen(section, anzahlGeaendert: anzahlGeaendert)
        }
        quelle.onAllesNeu = { [weak self] in
            guard let self, let collectionView = self.collectionView else { return }
            self.letzteSichtbare = []
            collectionView.reloadData()
            self.onAuswahl?([])
        }
    }

    private func monatGeladen(_ section: Int, anzahlGeaendert: Bool) {
        guard let collectionView, section < collectionView.numberOfSections else { return }
        if anzahlGeaendert {
            collectionView.reloadSections([section])
        } else {
            let sichtbar = collectionView.indexPathsForVisibleItems().filter { $0.section == section }
            for pfad in sichtbar {
                if let ansicht = collectionView.item(at: pfad) as? GridItemView,
                   let item = quelle.item(section: pfad.section, index: pfad.item) {
                    ansicht.zeige(item, anfragen: anfragen(fuer: item))
                }
            }
            if let kopf = collectionView.supplementaryView(forElementKind: NSCollectionView.elementKindSectionHeader,
                                                          at: IndexPath(item: 0, section: section)) as? MonatsKopfView {
                kopf.zeige(quelle.sections[section])
            }
        }
    }

    private var letzteSichtbare: Set<Int> = []

    @objc private func gescrollt() {
        let jetzt = Set(collectionView.indexPathsForVisibleItems().map(\.section))
        if jetzt != letzteSichtbare {
            letzteSichtbare = jetzt
            quelle.sichtbar(jetzt)
        }
        let clip = scrollView.contentView
        let max = collectionView.frame.height - clip.bounds.height
        onScroll?(max > 0 ? Double(clip.bounds.minY / max) : 0)
    }

    /// Springt ohne Animation an den Anfang eines Monats.
    public func springe(zuSection section: Int) {
        guard section < quelle.sections.count, quelle.sections[section].anzahl > 0 else { return }
        collectionView.layoutSubtreeIfNeeded()
        if let kopf = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: NSCollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) {
            let clip = scrollView.contentView
            let maxY = max(0, collectionView.frame.height - clip.bounds.height)
            vorlader.stopPrefetching()
            clip.scroll(to: NSPoint(x: 0, y: min(kopf.frame.minY, maxY)))
            scrollView.reflectScrolledClipView(clip)
            gescrollt()
        }
    }

    public func setZoom(_ neu: GridZoom, animiert: Bool = true) {
        guard neu != zoom else { return }
        wechsleZoom(zu: neu, anker: nil)
    }

    private var kantePixel: CGFloat {
        (collectionView.bounds.width / CGFloat(zoom.spalten)) * (view.window?.backingScaleFactor ?? 2)
    }

    private func anfragen(fuer item: GridItem) -> [ImageRequest] {
        let pixel = kantePixel
        return quelle.bildAnfragen(fuer: item, pixel: pixel).map { BilderCache.anfrage($0, pixel: pixel) }
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

    public func numberOfSections(in collectionView: NSCollectionView) -> Int { quelle.sections.count }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        quelle.sections[section].anzahl
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let ansicht = collectionView.makeItem(withIdentifier: GridItemView.id, for: indexPath) as! GridItemView
        if let item = quelle.item(section: indexPath.section, index: indexPath.item) {
            ansicht.zeige(item, anfragen: anfragen(fuer: item))
        } else {
            ansicht.zeigePlatzhalter()
            quelle.ladeMonat(indexPath.section)
        }
        return ansicht
    }

    public func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                               at indexPath: IndexPath) -> NSView {
        let kopf = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: MonatsKopfView.id, for: indexPath) as! MonatsKopfView
        kopf.zeige(quelle.sections[indexPath.section])
        return kopf
    }

    public func collectionView(_ collectionView: NSCollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        var angefragt = Set<Int>()
        let vorzuladen = indexPaths.compactMap { pfad -> ImageRequest? in
            guard let item = quelle.item(section: pfad.section, index: pfad.item) else {
                if angefragt.insert(pfad.section).inserted { quelle.ladeMonat(pfad.section) }
                return nil
            }
            return anfragen(fuer: item).first
        }
        vorlader.startPrefetching(with: vorzuladen)
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
            wechsleZoom(zu: neu, anker: collectionView.indexPathForItem(at: geste.location(in: collectionView)))
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
        let alteSpalten = zoom.spalten
        zoom = neu
        onZoomChange?(neu)
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        if let anker, let ankerY, let rahmen = collectionView.layoutAttributesForItem(at: anker)?.frame {
            let maxY = max(0, collectionView.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: min(max(rahmen.midY - ankerY, 0), maxY)))
            scrollView.reflectScrolledClipView(clip)
        }
        if neu.spalten < alteSpalten {
            for pfad in collectionView.indexPathsForVisibleItems() {
                if let ansicht = collectionView.item(at: pfad) as? GridItemView,
                   let item = quelle.item(section: pfad.section, index: pfad.item) {
                    ansicht.zeige(item, anfragen: anfragen(fuer: item))
                }
            }
        }
    }
}

// MARK: - Zellen

final class GridItemView: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("GridItemView")
    private let bild = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let herz = NSImageView(image: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "Favorit")!)

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        bild.imageScaling = .scaleProportionallyUpOrDown
        bild.wantsLayer = true
        bild.layer?.contentsGravity = .resizeAspectFill
        bild.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(bild)
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        herz.contentTintColor = .white
        for sub in [badge, herz] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.shadow = { let s = NSShadow(); s.shadowBlurRadius = 2; s.shadowColor = .black.withAlphaComponent(0.6); return s }()
            v.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            bild.leadingAnchor.constraint(equalTo: v.leadingAnchor), bild.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            bild.topAnchor.constraint(equalTo: v.topAnchor), bild.bottomAnchor.constraint(equalTo: v.bottomAnchor),
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

    private let lader = StufenLader()

    override func prepareForReuse() {
        super.prepareForReuse()
        lader.abbrechen()
        bild.image = nil
    }

    func zeigePlatzhalter() {
        lader.abbrechen()
        bild.image = nil
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badge.isHidden = true
        herz.isHidden = true
    }

    func zeige(_ item: GridItem, anfragen: [ImageRequest]) {
        let c = item.rgb
        view.layer?.backgroundColor = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).cgColor
        bild.image = nil
        let ansicht = bild
        lader.lade(anfragen) { neu, _ in ansicht.image = neu }
        let klein = view.bounds.width < 50
        badge.isHidden = item.art != .video || klein
        if item.art == .video { badge.stringValue = item.dauerText }
        herz.isHidden = !item.favorit || klein
        view.setAccessibilityLabel(item.art == .video ? "Video, \(item.dauerText)" : "Foto")
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
