#if canImport(UIKit)
import UIKit

/// Timeline-Grid für iPhone und iPad auf Basis von `UICollectionView`.
/// Bewusst ohne Diffable Data Source: Die Anzahl pro Monat ist vorab bekannt
/// (Immich-Buckets), die Zellen fragen ihre Daten erst beim Anzeigen ab.
@MainActor
public final class TimelineGridController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    public var model: GridModel { didSet { collectionView?.reloadData() } }
    public private(set) var zoom: GridZoom
    /// Meldet geänderte Spaltenzahl (z. B. nach Pinch) an SwiftUI zurück.
    public var onZoomChange: ((GridZoom) -> Void)?

    private var collectionView: UICollectionView!
    private var pinchSchonGestuft = false

    public init(model: GridModel, zoom: GridZoom) {
        self.model = model
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
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = true
        collectionView.register(GridZelle.self, forCellWithReuseIdentifier: GridZelle.id)
        collectionView.register(MonatsKopf.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MonatsKopf.id)
        view.addSubview(collectionView)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        collectionView.addGestureRecognizer(pinch)
    }

    var letzterSprung: UUID?
    /// Scroll-Position von 0 (neuester Monat) bis 1 (ältester Monat).
    public var onScroll: ((Double) -> Void)?

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let max = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        onScroll?(max > 0 ? Double((scrollView.contentOffset.y + scrollView.adjustedContentInset.top) / max) : 0)
    }

    /// Springt ohne Animation an den Anfang eines Monats.
    public func springe(zuSection section: Int) {
        guard section < model.sections.count, model.sections[section].anzahl > 0 else { return }
        collectionView.layoutIfNeeded()
        if let kopf = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: section)) {
            let maxY = max(0, collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
            collectionView.contentOffset.y = min(kopf.frame.minY - collectionView.adjustedContentInset.top, maxY)
        }
    }

    /// Spaltenzahl von außen setzen (z. B. Buttons).
    public func setZoom(_ neu: GridZoom, animiert: Bool = true) {
        guard neu != zoom else { return }
        wechsleZoom(zu: neu, anker: nil, animiert: animiert)
    }

    // MARK: - Layout

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

    public func numberOfSections(in collectionView: UICollectionView) -> Int { model.sections.count }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        model.sections[section].anzahl
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let zelle = collectionView.dequeueReusableCell(withReuseIdentifier: GridZelle.id, for: indexPath) as! GridZelle
        zelle.zeige(model[indexPath.section, indexPath.item])
        return zelle
    }

    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                               at indexPath: IndexPath) -> UICollectionReusableView {
        let kopf = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MonatsKopf.id,
                                                                   for: indexPath) as! MonatsKopf
        kopf.zeige(model.sections[indexPath.section])
        return kopf
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
        let anker = anker ?? collectionView.indexPathsForVisibleItems.sorted().dropFirst(collectionView.indexPathsForVisibleItems.count / 2).first
        let ankerY = anker.flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame.midY }
            .map { $0 - collectionView.contentOffset.y }
        zoom = neu
        onZoomChange?(neu)
        let aenderung = {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            if let anker, let ankerY, let rahmen = self.collectionView.layoutAttributesForItem(at: anker)?.frame {
                let maxY = max(0, self.collectionView.contentSize.height - self.collectionView.bounds.height
                               + self.collectionView.adjustedContentInset.bottom)
                let y = min(max(rahmen.midY - ankerY, -self.collectionView.adjustedContentInset.top), maxY)
                self.collectionView.contentOffset.y = y
            }
        }
        if animiert {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: aenderung)
        } else {
            aenderung()
        }
    }
}

// MARK: - Zellen

final class GridZelle: UICollectionViewCell {
    static let id = "GridZelle"
    private let badge = UILabel()
    private let herz = UIImageView(image: UIImage(systemName: "heart.fill"))
    private let live = UIImageView(image: UIImage(systemName: "livephoto"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.masksToBounds = true
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        for v in [badge, herz, live] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.5
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

    func zeige(_ item: GridItem) {
        let c = GridPalette.rgb(item.farbe)
        contentView.backgroundColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        let klein = bounds.width < 50
        badge.isHidden = item.art != .video || klein
        if item.art == .video { badge.text = String(format: "%d:%02d", item.dauer / 60, item.dauer % 60) }
        herz.isHidden = !item.favorit || klein
        live.isHidden = item.art != .livePhoto || klein
        accessibilityLabel = [item.art == .video ? "Video" : (item.art == .livePhoto ? "Live Photo" : "Foto"),
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
        let serif = UIFont.preferredFont(forTextStyle: .title3).fontDescriptor
            .withDesign(.serif)?.withSymbolicTraits(.traitBold) ?? UIFont.preferredFont(forTextStyle: .title3).fontDescriptor
        titel.font = UIFont(descriptor: serif, size: 0)
        titel.adjustsFontForContentSizeCategory = true
        untertitel.font = .preferredFont(forTextStyle: .footnote)
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
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func zeige(_ section: GridSection) {
        titel.text = section.titel
        untertitel.text = section.untertitel
        isAccessibilityElement = true
        accessibilityLabel = "\(section.titel), \(section.untertitel)"
    }
}
#endif
