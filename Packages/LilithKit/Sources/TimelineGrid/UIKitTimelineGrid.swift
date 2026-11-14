#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import Nuke
import DesignSystem

/// Timeline-Grid für iPhone und iPad auf Basis von `UICollectionView`.
/// Bewusst ohne Diffable Data Source: Die Anzahl pro Monat ist vorab bekannt
/// (Immich-Buckets), die Zellen fragen ihre Daten erst beim Anzeigen ab.
@MainActor
public final class TimelineGridController: UIViewController, UICollectionViewDataSource,
    UICollectionViewDataSourcePrefetching, UICollectionViewDelegate, UICollectionViewDragDelegate {
    public var quelle: TimelineQuelle {
        didSet { verbindeQuelle(); collectionView?.reloadData() }
    }
    public private(set) var zoom: GridZoom
    /// Meldet geänderte Spaltenzahl (z. B. nach Pinch) an SwiftUI zurück.
    public var onZoomChange: ((GridZoom) -> Void)?
    /// Scroll-Position von 0 (neuester Monat) bis 1 (ältester Monat).
    public var onScroll: ((Double) -> Void)?
    var letzterSprung: UUID?
    /// Ein Foto wurde angetippt: Monat, Position und Rahmen der Kachel im Fenster.
    public var onTap: ((Int, Int, CGRect) -> Void)?
    /// Meldet den Monat, der gerade oben unter der Leiste steht (für das Monats-Etikett aus Glas).
    public var onMonat: ((Int) -> Void)?
    /// Meldet, ob man ganz am Ende (bei den neuesten Fotos) steht.
    public var onEnde: ((Bool) -> Void)?
    /// Meldet das Aufnahmedatum des Fotos, das gerade oben (bzw. umgekehrt unten) steht.
    public var onDatum: ((Date?) -> Void)?
    /// `true`: Tab-Leiste zeigen. Weg beim Scrollen, zurück nach kurzem Stillstand.
    public var onLeiste: ((Bool) -> Void)?
    private var leisteSichtbar = true
    private var letzterOffset: CGFloat = 0
    private var letzterTag: DateComponents?
    private var amEnde: Bool?
    /// Wie in Apples Fotos-App: das Neueste unten rechts, ältere Fotos weiter oben.
    /// Umgesetzt durch Drehen der Sammlung um 180° (und der Zellen zurück), die Daten bleiben gleich.
    public var umgekehrt = false {
        didSet {
            guard umgekehrt != oldValue, let collectionView else { return }
            wendeRichtungAn()
            collectionView.reloadData()
        }
    }
    private var insetGesetzt = false
    /// Solange niemand selbst gescrollt hat, bleibt die Ansicht ganz unten bei den neuesten Fotos.
    private var nutzerHatGescrollt = false

    /// Ganz ans Ende (die neuesten Fotos), sofern umgekehrt und noch nicht selbst gescrollt.
    private func zumNeuesten() {
        guard !nutzerHatGescrollt, let collectionView else { return }
        if !umgekehrt {
            // Neuestes steht oben: an den Anfang, unter die Leiste.
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        meldeSichtbare()
        meldeMonat()
    }
    private var letzterMonat = -1
    /// Oberkante des sichtbaren Bereichs unter Statusleiste und Leiste. Die Fotos laufen darunter durch.
    private var oben: CGFloat { (view.window?.safeAreaInsets.top ?? 0) + 56 }

    /// Mehrfachauswahl: Antippen markiert Fotos, statt sie zu öffnen.
    public var auswahlModus = false {
        didSet {
            guard auswahlModus != oldValue, let collectionView else { return }
            collectionView.allowsMultipleSelection = auswahlModus
            collectionView.allowsMultipleSelectionDuringEditing = auswahlModus
            // Im Bearbeiten-Modus erlaubt UIKit das Auswählen per Wischen (wie in Fotos).
            collectionView.isEditing = auswahlModus
            if !auswahlModus { leereAuswahl() }
        }
    }
    /// Meldet die IDs der markierten Fotos.
    public var onAuswahl: (([String]) -> Void)?
    var auswahlStand = 0

    public func leereAuswahl() {
        guard let collectionView else { return }
        for pfad in collectionView.indexPathsForSelectedItems ?? [] { collectionView.deselectItem(at: pfad, animated: false) }
        onAuswahl?([])
    }

    private func meldeAuswahl() {
        let ids = (collectionView.indexPathsForSelectedItems ?? []).compactMap { quelle.item(section: $0.section, index: $0.item)?.id }
        onAuswahl?(ids)
    }

    // MARK: Fotos herausziehen (iPad: in andere Apps, Dateien, Mail)

    public func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession,
                               at indexPath: IndexPath) -> [UIDragItem] {
        guard let item = quelle.item(section: indexPath.section, index: indexPath.item), item.lokal == nil else { return [] }
        let anbieter = NSItemProvider()
        anbieter.suggestedName = "Luna-\(item.id.prefix(8))"
        let typ = item.art == .video ? UTType.movie : UTType.image
        let quelle = UnsicherGesendet(quelle)
        anbieter.registerFileRepresentation(for: typ, visibility: .all, openInPlace: false) { fertig in
            // Der Aufruf kommt von einem beliebigen Thread. Die Quelle lebt auf dem Main Actor.
            let antwort = UnsicherGesendet(fertig)
            Task { @MainActor in
                do { antwort.wert(try await quelle.wert.ladeOriginal(item), false, nil) } catch { antwort.wert(nil, false, error) }
            }
            return nil
        }
        let ziehen = UIDragItem(itemProvider: anbieter)
        ziehen.localObject = item.id
        return [ziehen]
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = quelle.item(section: indexPath.section, index: indexPath.item) else { return false }
        // Fotos nur auf dem Gerät können noch nicht favorisiert, archiviert oder gelöscht werden.
        return !(auswahlModus && item.lokal != nil)
    }

    // MARK: Auswählen per Wischen

    /// Im Auswahl-Modus: Foto antippen, nach rechts und dann nach unten wischen – alles dazwischen wird markiert.
    public func collectionView(_ collectionView: UICollectionView,
                               shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        auswahlModus
    }

    public func collectionView(_ collectionView: UICollectionView,
                               didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {}

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if auswahlModus { meldeAuswahl() }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if auswahlModus {
            meldeAuswahl()
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        collectionView.deselectItem(at: indexPath, animated: false)
        guard quelle.item(section: indexPath.section, index: indexPath.item) != nil,
              let zelle = collectionView.cellForItem(at: indexPath) else { return }
        onTap?(indexPath.section, indexPath.item, zelle.convert(zelle.bounds, to: nil))
    }

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
        // Die Monate laufen ohne Umbruch ineinander, wie in Apples Fotos-App.
        let layout = FliessLayout(spalten: zoom.spalten)
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        // Die Fotos laufen bis ganz nach oben unter Statusleiste und Leiste (Liquid Glass liegt darüber).
        collectionView.contentInsetAdjustmentBehavior = .never
        // Der Scrubber ersetzt die Scroll-Leiste.
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.register(GridZelle.self, forCellWithReuseIdentifier: GridZelle.id)
        collectionView.register(MonatsKopf.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MonatsKopf.id)
        view.addSubview(collectionView)
        wendeRichtungAn()
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        verbindeQuelle()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Unten Platz für die Tab-Leiste, oben keiner: Die erste Reihe liegt unter dem Glas.
        let unten = (view.window?.safeAreaInsets.bottom ?? 0) + 64
        // Umgekehrt liegt die sichtbare Unterkante am Anfang der Sammlung.
        // Von oben nach unten (Sammlungen, Alben): Die erste Reihe beginnt unter der Leiste, scrollt aber darunter.
        let neu = umgekehrt ? UIEdgeInsets(top: unten, left: 0, bottom: 0, right: 0)
                            : UIEdgeInsets(top: oben, left: 0, bottom: unten, right: 0)
        if collectionView.contentInset != neu {
            collectionView.contentInset = neu
            // Beim ersten Mal ganz ans Ende (die neuesten Fotos), nicht unter die Tab-Leiste.
            insetGesetzt = true
            zumNeuesten()
        }
    }

    private func wendeRichtungAn() {
        collectionView.transform = umgekehrt ? CGAffineTransform(rotationAngle: .pi) : .identity
        // Der Kanten-Effekt von iOS 26 (Weichzeichnen unter den Leisten) rechnet nicht mit der Drehung
        // und legt sich sonst als weißer Schleier über alles. Unter den Leisten liegt ohnehin Glas.
        if #available(iOS 26, *) {
            collectionView.topEdgeEffect.isHidden = umgekehrt
            collectionView.bottomEdgeEffect.isHidden = umgekehrt
        }
    }

    private func verbindeQuelle() {
        quelle.onMonatGeladen = { [weak self] section, anzahlGeaendert in
            self?.monatGeladen(section, anzahlGeaendert: anzahlGeaendert)
        }
        quelle.onAllesNeu = { [weak self] in
            guard let self, let collectionView = self.collectionView else { return }
            self.letzteSichtbare = []
            collectionView.reloadData()
            self.zumNeuesten()
            self.onAuswahl?([])
        }
    }

    private func monatGeladen(_ section: Int, anzahlGeaendert: Bool) {
        guard let collectionView, section < collectionView.numberOfSections else { return }
        #if DEBUG
        if let start = messStart, section == messZiel, messMonatMs == nil {
            messMonatMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        #endif
        // Ort und Anzahl sind jetzt bekannt: das Monats-Etikett auffrischen.
        if section == max(letzterMonat, 0) {
            onMonat?(section)
            // Daten sind jetzt da: das Datum oben links neu bestimmen.
            letzterTag = nil
            meldeMonat()
        }
        if anzahlGeaendert {
            UIView.performWithoutAnimation { collectionView.reloadSections([section]) }
        } else {
            // Alle Kacheln des Monats, auch die schon vorbereiteten, die noch nicht sichtbar sind.
            let anzahl = collectionView.numberOfItems(inSection: section)
            if anzahl > 0 { collectionView.reconfigureItems(at: (0..<anzahl).map { IndexPath(item: $0, section: section) }) }
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
        if umgekehrt, section == 0 {
            // Der neueste Monat steht unten: ganz ans Ende, nicht an seinen Anfang.
            vorlader.stopPrefetching()
            collectionView.layoutIfNeeded()
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
            collectionView.layoutIfNeeded()
            meldeSichtbare()
            meldeMonat()
        } else if umgekehrt, let letztes = collectionView.layoutAttributesForItem(
            at: IndexPath(item: quelle.sections[section].anzahl - 1, section: section)) {
            // Umgekehrt steht der Anfang des Monats (das älteste Foto) oben: das letzte Element der Section.
            vorlader.stopPrefetching()
            let minY = -collectionView.adjustedContentInset.top
            let maxY = max(minY, collectionView.contentSize.height - collectionView.bounds.height)
            collectionView.contentOffset.y = min(max(letztes.frame.maxY - collectionView.bounds.height + oben, minY), maxY)
            collectionView.layoutIfNeeded()
            meldeSichtbare()
        } else if let erstes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: section)) {
            let maxY = max(-collectionView.adjustedContentInset.top,
                           collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
            // Vorladen für die alte Position abbrechen: Die Bilder dort werden nicht mehr gebraucht.
            vorlader.stopPrefetching()
            // Der Monat beginnt direkt unter der Leiste, nicht unter dem Glas.
            collectionView.contentOffset.y = max(0, min(erstes.frame.minY - oben, maxY))
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

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        nutzerHatGescrollt = true
        quelle.scrollt(true)
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        meldeSichtbare()
        let max = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            + scrollView.adjustedContentInset.top
        onScroll?(max > 0 ? Double((scrollView.contentOffset.y + scrollView.adjustedContentInset.top) / max) : 0)
        meldeMonat()
        meldeLeiste(scrollView)
        // Weihnachtszeit: Scrollen wirbelt den Schnee auf der Tab-Leiste auf.
        if scrollView.isTracking || scrollView.isDecelerating { scrollTempo.melde(scrollView.contentOffset.y) }
    }

    private let scrollTempo = ScrollTempo()

    /// Beim Scrollen (egal in welche Richtung) verschwindet die Tab-Leiste.
    /// Bleibt man stehen, kommt sie nach `leistePause` Sekunden wieder.
    private let leistePause: TimeInterval = 3
    private var leisteZurueck: DispatchWorkItem?

    private func meldeLeiste(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        defer { letzterOffset = y }
        guard scrollView.isTracking || scrollView.isDecelerating, abs(y - letzterOffset) > 2 else { return }
        if leisteSichtbar {
            leisteSichtbar = false
            onLeiste?(false)
        }
        planeLeisteZurueck()
    }

    private func planeLeisteZurueck() {
        leisteZurueck?.cancel()
        let zurueck = DispatchWorkItem { [weak self] in
            guard let self, let cv = self.collectionView else { return }
            // Noch in Bewegung oder Finger liegt noch drauf: später nochmal schauen.
            if cv.isTracking || cv.isDecelerating { self.planeLeisteZurueck(); return }
            self.leisteSichtbar = true
            self.onLeiste?(true)
        }
        leisteZurueck = zurueck
        DispatchQueue.main.asyncAfter(deadline: .now() + leistePause, execute: zurueck)
    }

    /// Welcher Monat steht oben unter der Leiste?
    private func meldeMonat() {
        let punkt = umgekehrt
            ? CGPoint(x: collectionView.bounds.width - 4, y: collectionView.contentOffset.y + collectionView.bounds.height - oben - 2)
            : CGPoint(x: 4, y: collectionView.contentOffset.y + oben + 2)
        let ende = umgekehrt && collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 24
        if ende != amEnde {
            amEnde = ende
            onEnde?(ende)
        }
        let stelle = collectionView.indexPathForItem(at: punkt)
        let monat = stelle?.section
            ?? collectionView.indexPathsForVisibleItems.map(\.section).min() ?? 0
        if let stelle {
            let datum = quelle.datum(section: stelle.section, index: stelle.item)
            let tag = datum.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
            if tag != letzterTag {
                letzterTag = tag
                onDatum?(datum)
            }
        }
        if monat != letzterMonat {
            letzterMonat = monat
            onMonat?(monat)
        }
    }

    // MARK: - Layout

    private var kantePixel: CGFloat {
        let breite = collectionView?.bounds.width ?? view.bounds.width
        return (breite / CGFloat(zoom.spalten)) * (view.window?.screen.scale ?? 3)
    }

    // MARK: - Daten

    public func numberOfSections(in collectionView: UICollectionView) -> Int { quelle.sections.count }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        quelle.sections[section].anzahl
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let zelle = collectionView.dequeueReusableCell(withReuseIdentifier: GridZelle.id, for: indexPath) as! GridZelle
        konfiguriere(zelle, at: indexPath)
        return zelle
    }

    private func konfiguriere(_ zelle: GridZelle, at indexPath: IndexPath) {
        zelle.contentView.transform = umgekehrt ? CGAffineTransform(rotationAngle: .pi) : .identity
        if let item = quelle.item(section: indexPath.section, index: indexPath.item) {
            let pixel = kantePixel
            zelle.zeige(item, anfragen: quelle.bildAnfragen(fuer: item, pixel: pixel).map { BilderCache.anfrage($0, pixel: pixel) })
            if item.lokal != nil {
                // Foto nur auf dem Gerät: Vorschau kommt aus der Mediathek, nicht vom Server.
                let quelle = self.quelle
                zelle.ladeLokal { await quelle.lokalesBild(fuer: item, pixel: pixel) }
            }
        } else {
            zelle.zeigePlatzhalter()
            quelle.ladeMonat(indexPath.section)
        }
    }

    /// iOS baut Kacheln, bevor sie ins Bild kommen. Wurde der Monat inzwischen geladen,
    /// trägt eine vorbereitete Kachel noch den Platzhalter: hier nachholen, sonst bleiben Lücken.
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                               forItemAt indexPath: IndexPath) {
        guard let zelle = cell as? GridZelle, zelle.zeigtPlatzhalter else { return }
        konfiguriere(zelle, at: indexPath)
    }

    /// Beim Stehenbleiben: Monate, deren Laden beim schnellen Überfliegen abgebrochen wurde, jetzt laden.
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        quelle.scrollt(false)
        ladeFehlende()
    }
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            quelle.scrollt(false)
            ladeFehlende()
        }
    }

    private func ladeFehlende() {
        for pfad in collectionView.indexPathsForVisibleItems where quelle.item(section: pfad.section, index: pfad.item) == nil {
            quelle.ladeMonat(pfad.section)
        }
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

    /// Laufender Zoom mit den Fingern: Die Kacheln wachsen und schrumpfen live mit (wie in Apples Fotos-App).
    private struct ZoomLauf {
        let ziel: GridZoom
        let uebergang: UICollectionViewTransitionLayout
        let neu: FliessLayout
        let alt: FliessLayout
        let anker: IndexPath
        /// Abstand der Ankerkachel-Mitte zur Oberkante des Sichtbaren, bleibt konstant.
        let ankerAbstand: CGFloat
        /// Wie stark man pinchen muss, bis der neue Zoom ganz erreicht ist.
        let verhaeltnis: CGFloat
        let groesser: Bool
    }
    private var zoomLauf: ZoomLauf?

    @objc private func pinch(_ geste: UIPinchGestureRecognizer) {
        switch geste.state {
        case .began:
            pinchSchonGestuft = false
        case .changed:
            if zoomLauf == nil, !pinchSchonGestuft, abs(geste.scale - 1) > 0.03 {
                starteZoomLauf(groesser: geste.scale > 1, ort: geste.location(in: collectionView))
            }
            guard let lauf = zoomLauf else { return }
            let s = lauf.groesser ? geste.scale : 1 / max(geste.scale, 0.01)
            let fortschritt = min(max((s - 1) / (lauf.verhaeltnis - 1), 0), 1)
            lauf.uebergang.transitionProgress = fortschritt
            halteAnker(lauf, in: lauf.uebergang)
        case .ended, .cancelled, .failed:
            guard let lauf = zoomLauf else { return }
            // Weit genug gezogen oder in Zielrichtung losgelassen: fertig zoomen, sonst zurück.
            let tempo = lauf.groesser ? geste.velocity : -geste.velocity
            let fertig = geste.state == .ended && (lauf.uebergang.transitionProgress > 0.4 || tempo > 0.5)
            let ziel = fertig ? lauf.neu : lauf.alt
            ziel.zielOffset = ankerOffset(lauf, rahmen: ziel.rahmen(fuer: lauf.anker), layout: ziel)
            if fertig {
                collectionView.finishInteractiveTransition()
            } else {
                collectionView.cancelInteractiveTransition()
            }
        default:
            break
        }
    }

    private func starteZoomLauf(groesser: Bool, ort: CGPoint) {
        var ziel = zoom
        guard groesser ? ziel.groesser() : ziel.kleiner() else { return }
        guard let alt = collectionView.collectionViewLayout as? FliessLayout else { return }
        let anker = collectionView.indexPathForItem(at: ort)
            ?? collectionView.indexPathsForVisibleItems.sorted().dropFirst(collectionView.indexPathsForVisibleItems.count / 2).first
        guard let anker, let rahmen = alt.rahmen(fuer: anker) else { return }
        pinchSchonGestuft = true
        vorlader.stopPrefetching()
        let neu = FliessLayout(spalten: ziel.spalten)
        let altSpalten = CGFloat(zoom.spalten), neuSpalten = CGFloat(ziel.spalten)
        // Erster Wert: Übergang abgeschlossen (nicht abgebrochen), zweiter: Animation zu Ende.
        let uebergang = collectionView.startInteractiveTransition(to: neu) { [weak self] fertig, _ in
            guard let self else { return }
            let lauf = self.zoomLauf
            self.zoomLauf = nil
            alt.zielOffset = nil
            neu.zielOffset = nil
            guard fertig, let lauf else { return }
            let alteSpalten = self.zoom.spalten
            self.zoom = lauf.ziel
            self.onZoomChange?(lauf.ziel)
            UISelectionFeedbackGenerator().selectionChanged()
            // Größere Kacheln brauchen schärfere Bilder (erst nach der Bewegung).
            if lauf.ziel.spalten < alteSpalten {
                self.collectionView.reconfigureItems(at: self.collectionView.indexPathsForVisibleItems)
            }
        }
        zoomLauf = ZoomLauf(ziel: ziel, uebergang: uebergang, neu: neu, alt: alt, anker: anker,
                            ankerAbstand: rahmen.midY - collectionView.contentOffset.y,
                            verhaeltnis: max(groesser ? altSpalten / neuSpalten : neuSpalten / altSpalten, 1.05),
                            groesser: groesser)
    }

    /// Scrollt so, dass die Ankerkachel an derselben Stelle auf dem Bildschirm bleibt.
    private func halteAnker(_ lauf: ZoomLauf, in layout: UICollectionViewLayout) {
        guard let rahmen = layout.layoutAttributesForItem(at: lauf.anker)?.frame,
              let y = ankerOffset(lauf, rahmen: rahmen, layout: layout)?.y else { return }
        collectionView.contentOffset.y = y
    }

    private func ankerOffset(_ lauf: ZoomLauf, rahmen: CGRect?, layout: UICollectionViewLayout) -> CGPoint? {
        guard let rahmen else { return nil }
        let hoehe = layout.collectionViewContentSize.height
        let unten = max(hoehe, rahmen.maxY) - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
        let y = min(max(rahmen.midY - lauf.ankerAbstand, -collectionView.adjustedContentInset.top),
                    max(unten, -collectionView.adjustedContentInset.top))
        return CGPoint(x: 0, y: y)
    }

    /// Ändert die Spaltenzahl ohne Finger (Menü, Tastatur) und hält die Mitte an ihrem Platz.
    private func wechsleZoom(zu neu: GridZoom, anker: IndexPath?, animiert: Bool) {
        let sichtbar = collectionView.indexPathsForVisibleItems.sorted()
        let anker = anker ?? sichtbar.dropFirst(sichtbar.count / 2).first
        let ankerY = anker.flatMap { collectionView.layoutAttributesForItem(at: $0)?.frame.midY }
            .map { $0 - collectionView.contentOffset.y }
        let alteSpalten = zoom.spalten
        zoom = neu
        onZoomChange?(neu)
        let layout = FliessLayout(spalten: neu.spalten)
        let aenderung = {
            self.collectionView.setCollectionViewLayout(layout, animated: false)
            self.collectionView.layoutIfNeeded()
            if let anker, let ankerY, let rahmen = layout.rahmen(fuer: anker) {
                let oben = -self.collectionView.adjustedContentInset.top
                let maxY = max(oben, self.collectionView.contentSize.height - self.collectionView.bounds.height
                               + self.collectionView.adjustedContentInset.bottom)
                self.collectionView.contentOffset.y = min(max(rahmen.midY - ankerY, oben), maxY)
            }
        }
        if animiert {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: aenderung)
        } else {
            aenderung()
        }
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
    private let haken = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let schleier = UIView()

    override var isSelected: Bool {
        didSet {
            haken.isHidden = !isSelected
            schleier.isHidden = !isSelected
            if isSelected { accessibilityTraits.insert(.selected) } else { accessibilityTraits.remove(.selected) }
        }
    }
    private let live = UIImageView(image: UIImage(systemName: "livephoto"))
    /// Symbol für Fotos, die nur auf dem Gerät liegen.
    private let lokalSymbol = UIImageView()
    private var lokalAufgabe: Task<Void, Never>?
    private let lader = StufenLader()
    private(set) var hatBild = false
    /// Zeigt noch den grauen Platzhalter (Monat nicht geladen).
    private(set) var zeigtPlatzhalter = false
    private var aktuelleId: String?

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
        for v in [badge, herz, live, lokalSymbol] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.6
            v.layer.shadowRadius = 2
            v.layer.shadowOffset = .zero
            contentView.addSubview(v)
        }
        herz.tintColor = .white
        live.tintColor = .white
        lokalSymbol.tintColor = .white
        lokalSymbol.contentMode = .scaleAspectFit
        lokalSymbol.isHidden = true
        schleier.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        schleier.frame = contentView.bounds
        schleier.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        schleier.isHidden = true
        contentView.insertSubview(schleier, aboveSubview: bild)
        haken.preferredSymbolConfiguration = UIImage.SymbolConfiguration(paletteColors: [
            .white, UIColor(red: 0.69, green: 0.19, blue: 0.35, alpha: 1)])
        haken.translatesAutoresizingMaskIntoConstraints = false
        haken.isHidden = true
        contentView.addSubview(haken)
        NSLayoutConstraint.activate([
            haken.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            haken.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            haken.widthAnchor.constraint(equalToConstant: 24), haken.heightAnchor.constraint(equalToConstant: 24),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            herz.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            herz.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            herz.widthAnchor.constraint(equalToConstant: 12), herz.heightAnchor.constraint(equalToConstant: 12),
            live.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            live.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            live.widthAnchor.constraint(equalToConstant: 14), live.heightAnchor.constraint(equalToConstant: 14),
            lokalSymbol.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            lokalSymbol.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            lokalSymbol.widthAnchor.constraint(equalToConstant: 16), lokalSymbol.heightAnchor.constraint(equalToConstant: 16),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        lader.abbrechen()
        lokalAufgabe?.cancel()
        lokalAufgabe = nil
        bild.image = nil
        hatBild = false
        aktuelleId = nil
    }

    /// Vorschau vom Gerät laden (für Fotos, die noch nicht auf dem Server sind).
    func ladeLokal(_ laden: @escaping @MainActor () async -> CGImage?) {
        lokalAufgabe?.cancel()
        lokalAufgabe = Task { [weak self] in
            guard let cg = await laden(), !Task.isCancelled, let self else { return }
            self.bild.image = UIImage(cgImage: cg)
            self.hatBild = true
        }
    }

    func zeigePlatzhalter() {
        lader.abbrechen()
        lokalAufgabe?.cancel()
        bild.image = nil
        aktuelleId = nil
        lokalSymbol.isHidden = true
        // Deckend und hell genug, damit es auf Schwarz nicht wie ein Loch aussieht.
        contentView.backgroundColor = UIColor.systemGray5
        zeigtPlatzhalter = true
        badge.isHidden = true
        herz.isHidden = true
        live.isHidden = true
        accessibilityLabel = "Wird geladen"
    }

    func zeige(_ item: GridItem, anfragen: [ImageRequest]) {
        zeigtPlatzhalter = false
        let c = item.rgb
        contentView.backgroundColor = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        // Dasselbe Foto (z. B. nach einem Zoom): altes Bild stehen lassen, bis das schärfere da ist.
        if item.id != aktuelleId {
            bild.image = nil
            hatBild = false
        }
        aktuelleId = item.id
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
        badge.isHidden = item.art != .video || klein || (item.lokal != nil && item.dauer == 0)
        if item.art == .video { badge.text = item.dauerText }
        switch item.lokal {
        case .nurHier: lokalSymbol.image = UIImage(systemName: "icloud.slash")
        case .laedtHoch: lokalSymbol.image = UIImage(systemName: "arrow.up.circle")
        case .fehler: lokalSymbol.image = UIImage(systemName: "exclamationmark.circle")
        case nil: lokalSymbol.image = nil
        }
        lokalSymbol.isHidden = item.lokal == nil || klein
        herz.isHidden = !item.favorit || klein
        live.isHidden = item.art != .livePhoto || klein
        let lokalText: String? = switch item.lokal {
        case .nurHier: "nur auf diesem Gerät"
        case .laedtHoch: "wird hochgeladen"
        case .fehler: "Hochladen gescheitert"
        case nil: nil
        }
        accessibilityLabel = [item.art == .video ? "Video, \(item.dauerText)" : (item.art == .livePhoto ? "Live Photo" : "Foto"),
                              item.favorit ? "Favorit" : nil, lokalText].compactMap { $0 }.joined(separator: ", ")
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
        let fett = basis.withSymbolicTraits(.traitBold) ?? basis
        titel.font = UIFont(descriptor: fett, size: 0)
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
/// Reicht einen Wert über Thread-Grenzen weiter, wenn klar ist, dass er nur auf einer Seite benutzt wird.
struct UnsicherGesendet<Wert>: @unchecked Sendable {
    let wert: Wert
    init(_ wert: Wert) { self.wert = wert }
}
#endif
