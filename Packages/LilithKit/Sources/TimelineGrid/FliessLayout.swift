#if canImport(UIKit)
import UIKit

/// Quadratische Kacheln, die über die Monate hinweg ohne Umbruch durchlaufen (wie in Apples Fotos-App).
/// Die Monate bleiben Sections (für Laden und Sprünge), beginnen aber keine neue Reihe.
/// So entstehen keine halb leeren Reihen am Monatsende.
@MainActor
final class FliessLayout: UICollectionViewLayout {
    let spalten: Int
    /// Wohin am Ende eines Zoom-Übergangs gescrollt wird (damit das Foto unter den Fingern bleibt).
    var zielOffset: CGPoint?

    private var anfaenge: [Int] = []   // globaler Index des ersten Elements je Section
    private var gesamt = 0
    private var kante: CGFloat = 0
    private var abstand: CGFloat = 2
    private var breite: CGFloat = 0

    init(spalten: Int) {
        self.spalten = spalten
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) wird nicht unterstützt") }

    private var n: Int { max(spalten, 1) }
    private var schritt: CGFloat { kante + abstand }

    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        breite = cv.bounds.width
        abstand = n == 1 ? 8 : 2
        kante = max(((breite - abstand * CGFloat(n - 1)) / CGFloat(n)).rounded(.down), 1)
        anfaenge.removeAll(keepingCapacity: true)
        var summe = 0
        for s in 0..<cv.numberOfSections {
            anfaenge.append(summe)
            summe += cv.numberOfItems(inSection: s)
        }
        gesamt = summe
    }

    override var collectionViewContentSize: CGSize {
        let reihen = (gesamt + n - 1) / n
        return CGSize(width: breite, height: reihen == 0 ? 0 : CGFloat(reihen) * schritt - abstand)
    }

    private func rahmen(global g: Int) -> CGRect {
        CGRect(x: CGFloat(g % n) * schritt, y: CGFloat(g / n) * schritt, width: kante, height: kante)
    }

    /// Globaler Index → Section und Position (binäre Suche über die Monatsanfänge).
    private func pfad(global g: Int) -> IndexPath {
        var lo = 0, hi = anfaenge.count - 1
        while lo < hi {
            let mitte = (lo + hi + 1) / 2
            if anfaenge[mitte] <= g { lo = mitte } else { hi = mitte - 1 }
        }
        return IndexPath(item: g - anfaenge[lo], section: lo)
    }

    private func attribute(global g: Int) -> UICollectionViewLayoutAttributes {
        let a = UICollectionViewLayoutAttributes(forCellWith: pfad(global: g))
        a.frame = rahmen(global: g)
        return a
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard gesamt > 0, schritt > 0 else { return [] }
        let ersteReihe = max(Int(floor(rect.minY / schritt)), 0)
        let letzteReihe = Int(floor(rect.maxY / schritt))
        let von = ersteReihe * n
        let bis = min((letzteReihe + 1) * n, gesamt)
        guard von < bis else { return [] }
        return (von..<bis).map(attribute(global:))
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section < anfaenge.count else { return nil }
        let g = anfaenge[indexPath.section] + indexPath.item
        guard g < gesamt else { return nil }
        return attribute(global: g)
    }

    override func targetContentOffset(forProposedContentOffset vorschlag: CGPoint) -> CGPoint {
        zielOffset ?? vorschlag
    }

    /// Rahmen eines Elements, ohne Attribute anzulegen (für die Zoom-Berechnung).
    func rahmen(fuer pfad: IndexPath) -> CGRect? {
        if anfaenge.isEmpty { prepare() }
        guard pfad.section < anfaenge.count else { return nil }
        let g = anfaenge[pfad.section] + pfad.item
        return g < gesamt ? rahmen(global: g) : nil
    }

    override func shouldInvalidateLayout(forBoundsChange neu: CGRect) -> Bool {
        neu.width != breite
    }
}
#endif
