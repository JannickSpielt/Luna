#if canImport(UIKit)
import UIKit
import Nuke

/// Timeline-Grid für iPhone und iPad auf Basis von `UICollectionView`.
/// Bewusst ohne Diffable Data Source: Die Anzahl pro Monat ist vorab bekannt
/// (Immich-Buckets), die Zellen fragen ihre Daten erst beim Anzeigen ab.
@MainActor
public final class TimelineGridController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDataSourcePrefetching, UICollectionViewDelegate {
    public var quelle: TimelineQuelle {
        didSet { verbindeQuelle(); collectionView?.reloadData() }
    }
    public private(set) var zoom: GridZoom
    /// Meldet geänderte Spaltenzahl (z. B. nach Pinch) an SwiftUI zurück.
    public var onZoomChange: ((GridZoom) -> Void)?
    /// Scroll-Position von 0 (neuester Monat) bis 1 (ältester Monat).
    public var onScroll: ((Double) -> Void)?
    var letzterSprung: UUID?

    private var collectionView: UICollectionView!
    private var pinchSchonGestuft = false
    private let vorlader = ImagePrefetcher(pipeline: .shared, destination: .memoryCache, maxConcurrentRequestCount: 4)

    public init(quelle: TimelineQuelle, zoom: GridZoom) {
        self.quelle = quelle
        self.zoom = zoom
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewCompositionalLayout { [weak self] _, umgebung in
            self?.section(breite: umgebung.container.effectiveContentSize.width)
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        // Der Scrubber ersetzt die Scroll-Leiste.
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self
        collectionView.register(GridZelle.self, forCellWithReuseIdentifier: GridZelle.id)
        collectionView.register(MonatsKopf.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MonatsKopf.id)
        view.addSubview(collectionView)
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        verbindeQuelle()
    }

    private func verbindeQuelle() {
        quelle.onMonatGeladen = { [weak self] section, anzahlGeaendert in
            self?.monatGeladen(section, anzahlGeaendert: anzahlGeaendert)
        }
    }

    private func monatGeladen(_ section: Int, anzahlGeaendert: Bool) {
        guard let collectionView, section < collectionView.numberOfSections else { return }
        #if DEBUG
        if let start = messStart, section == messZiel, messMonatMs == nil {
            messMonatMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        #endif
        if anzahlGeaendert {
            UIView.performWithoutAnimation { collectionView.reloadSections([section]) }
        } else {
            let sichtbar = collectionView.indexPathsForVisibleItems.filter { $0.section == section }
            if !sichtbar.isEmpty { collectionView.reconfigureItems(at: sichtbar) }
            if let kopf = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader,
                                                          at: IndexPath(item: 0, section: section)) as? MonatsKopf {
                kopf.zeige(quelle.sections[section])
            }
        }
    }

    #if DEBUG
    // Messung (nur Debug): Zeit vom letzten Sprung bis Monat geladen und bis alle sichtbaren Kacheln ein Bild haben.
    private var messStart: Date?
    private var messZiel = -1
    private var messMonatMs: Int?
    private var messTimer: Timer?

    private func starteMessung(_ section: Int) {
        messStart = Date()
        messZiel = section
        messMonatMs = quelle.item(section: section, index: 0) != nil ? 0 : nil
        messTimer?.invalidate()
        messTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let start = self.messStart else { return }
                let zellen = self.collectionView.visibleCells.compactMap { $0 as? GridZelle }
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                if (!zellen.isEmpty && zellen.allSatisfy(\.hatBild)) || ms > 20_000 {
                    print("LILITH-MESSUNG sprung→monat=\(self.messMonatMs.map(String.init) ?? "?")ms sprung→bilder=\(ms)ms "
                          + "zellen=\(zellen.count) mitBild=\(zellen.filter(\.hatBild).count)")
                    fflush(stdout)
                    self.messTimer?.invalidate()
                    self.messStart = nil
                }
            }
        }
    }
    #endif

    /// Springt ohne Animation an den Anfang eines Monats.
    public func springe(zuSection section: Int) {
        guard section < quelle.sections.count, quelle.sections[section].anzahl > 0 else { return }
        #if DEBUG
        starteMessung(section)
        #endif
        collectionView.layoutIfNeeded()
        if let kopf = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) {
            let maxY = max(-collectionView.adjustedContentInset.top,
                           collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
            // Vorladen für die alte Position abbrechen: Die Bilder dort werden nicht mehr gebraucht.
            vorlader.stopPrefetching()
            collectionView.contentOffset.y = min(kopf.frame.minY - collectionView.adjustedContentInset.top, maxY)
            collectionView.layoutIfNeeded()
            meldeSichtbare()
        }
    }

    public func setZoom(_ neu: GridZoom, animiert: Bool = true) {
        guard neu != zoom else { return }
        wechsleZoom(zu: neu, anker: nil, animiert: animiert)
    }

    private var letzteSichtbare: Set<Int> = []

    private func meldeSichtbare() {
        let jetzt = Set(collectionView.indexPathsForVisibleItems.map(\.section))
        if jetzt != letzteSichtbare {
            letzteSichtbare = jetzt
            quelle.sichtbar(jetzt)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        meldeSichtbare()
        let max = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            + scrollView.adjustedContentInset.top
        onScroll?(max > 0 ? Double((scrollView.contentOffset.y + scrollView.adjustedContentInset.top) / max) : 0)
    }

    // MARK: - Layout

    private var kantePixel: CGFloat {
        let breite = collectionView?.bounds.width ?? view.bounds.width
        return (breite / CGFloat(zoom.spalten)) * (view.window?.screen.scale ?? 3)
    }

    private func section(breite: CGFloat) -> NSCollectionLayoutSection {
        let spalten = CGFloat(zoom.spalten)
        let abstand: CGFloat = zoom.spalten == 1 ? 8 : 2
        let kante = ((breite - abstand * (spalten - 1)) / spalten).rounded(.down)
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(kante), heightDimension: .absolute(kante)))
        let gruppe = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(kante)),
            repeatingSubitem: item, count: zoom.spalten)
        gruppe.interItemSpacing = .fixed(abstand)
        let section = NSCollectionLayoutSection(group: gruppe)
        section.interGroupSpacing = abstand
        section.contentInsets = .init(top: 0, leading: 0, bottom: 18, trailing: 0)
        let kopf = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(48)),
            elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        kopf.pinToVisibleBounds = true
        section.boundarySupplementaryItems = [kopf]
        return section
    }

    // MARK: - Daten

    public func numberOfSections(in collectionView: UICollectionView) -> Int { quelle.sections.count }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        quelle.sections[section].anzahl
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let zelle = collectionView.dequeueReusableCell(withReuseIdentifier: GridZelle.id, for: indexPath) as! GridZelle
        if let item = quelle.item(section: indexPath.section, index: indexPath.item) {
            let pixel = kantePixel
            zelle.zeige(item, anfragen: quelle.bildAnfragen(fuer: item, pixel: pixel).map { BilderCache.anfrage($0, pixel: pixel) })
        } else {
            zelle.zeigePlatzhalter()
            quelle.ladeMonat(indexPath.section)
        }
        return zelle
    }

    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                               at indexPath: IndexPath) -> UICollectionReusableView {
        let kopf = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MonatsKopf.id,
                                                                   for: indexPath) as! MonatsKopf
        kopf.zeige(quelle.sections[indexPath.section])
        return kopf
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        vorlader.startPrefetching(with: anfragen(fuer: indexPaths))
    }

    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        vorlader.stopPrefetching(with: anfragen(fuer: indexPaths))
    }

    /// Vorgeladen wird nur die kleine Stufe, um Datenvolumen zu sparen.
    private func anfragen(fuer indexPaths: [IndexPath]) -> [ImageRequest] {
        let pixel = kantePixel
        var angefragt = Set<Int>()
        return indexPaths.compactMap { pfad in
            guard let item = quelle.item(section: pfad.section, index: pfad.item) else {
                if angefragt.insert(pfad.section).inserted { quelle.ladeMonat(pfad.section) }
                return nil
            }
            return quelle.bildAnfragen(fuer: item, pixel: pixel).first.map { BilderCache.anfrage($0, pixel: pixel) }
        }
    }

    // MARK: - Pinch-Zoom

    @objc private func pinch(_ geste: UIPinchGestureRecognizer) {
        switch geste.state {
        case .began:
            pinchSchonGestuft = false
        case .changed where !pinchSchonGestuft:
            var neu = zoom
            let geaendert = geste.scale > 1.25 ? neu.groesser() : (geste.scale < 0.8 ? neu.kleiner() : false)
            guard geaendert else { return }
            pinchSchonGestuft = true
            let anker = collectionView.indexPathForItem(at: geste.location(in: collectionView))
            wechsleZoom(zu: neu, anker: anker, animiert: true)
            UISelectionFeedbackGenerator().selectionChanged()
        default:
            break
        }
    }

    /// Ändert die Spaltenzahl und hält das Foto unter den Fingern an seinem Platz.
    private func wechsleZoom(zu neu: GridZoom, anker: IndexPath?, animiert: Bool) {
        let sichtbar = collectionView.indexPathsForVisibleItems.sorted()
        let anker = anker ?? sichtbar.dropFirst(sichtbar.count / 2).first
        let ankerY = anker.flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame.midY }
            .map { $0 - collectionView.contentOffset.y }
        let alteSpalten = zoom.spalten
        zoom = neu
        onZoomChange?(neu)
        let aenderung = {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            if let anker, let ankerY, let rahmen = self.collectionView.layoutAttributesForItem(at: anker)?.frame {
                let maxY = max(0, self.collectionView.contentSize.height - self.collectionView.bounds.height
                               + self.collectionView.adjustedContentInset.bottom)
                self.collectionView.contentOffset.y = min(max(rahmen.midY - ankerY, -self.collectionView.adjustedContentInset.top), maxY)
            }
        }
        if animiert {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                           options: [.allowUserInteraction], animations: aenderung)
        } else {
            aenderung()
        }
        // Größere Kacheln brauchen schärfere Bilder.
        if neu.spalten < alteSpalten {
            collectionView.reconfigureItems(at: collectionView.indexPathsForVisibleItems)
        }
    }
}

// MARK: - Zellen

final class GridZelle: UICollectionViewCell {
    static let id = "GridZelle"
    private let bild = UIImageView()
    private let badge = UILabel()
    private let herz = UIImageView(image: UIImage(systemName: "heart.fill"))
    private let live = UIImageView(image: UIImage(systemName: "livephoto"))
    private let lader = StufenLader()
    private(set) var hatBild = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        bild.contentMode = .scaleAspectFill
        bild.clipsToBounds = true
        bild.frame = contentView.bounds
        bild.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(bild)
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        for v in [badge, herz, live] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.6
            v.layer.shadowRadius = 2
            v.layer.shadowOffset = .zero
            contentView.addSubview(v)
        }
        herz.tintColor = .white
        live.tintColor = .white
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            herz.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            herz.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            herz.widthAnchor.constraint(equalToConstant: 12), herz.heightAnchor.constraint(equalToConstant: 12),
            live.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            live.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            live.widthAnchor.constraint(equalToConstant: 14), live.heightAnchor.constraint(equalToConstant: 14),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        lader.abbrechen()
        bild.image = nil
        hatBild = false
    }

    func zeigePlatzhalter() {
        lader.abbrechen()
        bild.image = nil
        contentView.backgroundColor = UIColor.secondarySystemFill
        badge.isHidden = true
        herz.isHidden = true
        live.isHidden = true
        accessibilityLabel = "Wird geladen"
    }

    func zeige(_ item: GridItem, anfragen: [ImageRequest]) {
        let c = item.rgb
        contentView.backgroundColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        bild.image = nil
        hatBild = false
        let ansicht = bild
        lader.lade(anfragen) { [weak self] neu, sofort in
            self?.hatBild = true
            if sofort || ansicht.image != nil {
                ansicht.image = neu
            } else {
                UIView.transition(with: ansicht, duration: 0.15, options: .transitionCrossDissolve) { ansicht.image = neu }
            }
        }
        let klein = bounds.width < 50
        badge.isHidden = item.art != .video || klein
        if item.art == .video { badge.text = item.dauerText }
        herz.isHidden = !item.favorit || klein
        live.isHidden = item.art != .livePhoto || klein
        accessibilityLabel = [item.art == .video ? "Video, \(item.dauerText)" : (item.art == .livePhoto ? "Live Photo" : "Foto"),
                              item.favorit ? "Favorit" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

final class MonatsKopf: UICollectionReusableView {
    static let id = "MonatsKopf"
    private let titel = UILabel()
    private let untertitel = UILabel()
    private let hintergrund = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)
        hintergrund.frame = bounds
        hintergrund.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(hintergrund)
        let basis = UIFont.preferredFont(forTextStyle: .title3).fontDescriptor
        let serif = basis.withDesign(.serif)?.withSymbolicTraits(.traitBold) ?? basis
        titel.font = UIFont(descriptor: serif, size: 0)
        titel.adjustsFontForContentSizeCategory = true
        untertitel.font = .preferredFont(forTextStyle: .footnote)
        untertitel.adjustsFontForContentSizeCategory = true
        untertitel.textColor = .secondaryLabel
        let stapel = UIStackView(arrangedSubviews: [titel, UIView(), untertitel])
        stapel.alignment = .firstBaseline
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stapel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func zeige(_ section: GridSection) {
        titel.text = section.titel
        untertitel.text = section.untertitel
        accessibilityLabel = "\(section.titel), \(section.untertitel)"
    }
}
#endif
