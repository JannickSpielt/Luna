import AVKit
import SwiftUI
import DesignSystem
import Networking
import TimelineGrid

/// Ton für Videos: Sie spielen auch im Stummmodus (wie in Apples Fotos-App).
/// Live Photos bleiben dabei stumm, weil sie die Kategorie nicht umstellen.
/// Andere Apps (Musik) werden erst beim Abspielen unterbrochen und laufen danach weiter.
@MainActor
enum VideoTon {
    static func an() {
        #if os(iOS)
        let sitzung = AVAudioSession.sharedInstance()
        try? sitzung.setCategory(.playback, mode: .moviePlayback)
        try? sitzung.setActive(true)
        #endif
    }

    static func aus() {
        #if os(iOS)
        let sitzung = AVAudioSession.sharedInstance()
        try? sitzung.setActive(false, options: .notifyOthersOnDeactivation)
        try? sitzung.setCategory(.soloAmbient)
        #endif
    }
}

/// Stelle eines Fotos in der Timeline: Monat und Position darin.
struct DetailPosition: Hashable, Sendable {
    var section: Int
    var index: Int
}

extension Image {
    init(plattform bild: PlattformBild) {
        #if canImport(UIKit)
        self.init(uiImage: bild)
        #else
        self.init(nsImage: bild)
        #endif
    }
}

/// Eine Seite der Detailansicht: ein Foto, Live Photo oder Video.
struct DetailSeite: View {
    let position: DetailPosition
    let quelle: TimelineQuelle
    let store: TimelineStore?
    let istAktuell: Bool
    @Binding var gezoomt: Bool
    var zeigeBedienung = true
    var verberge: () -> Void = {}
    let onTap: () -> Void

    @State private var item: Kachel?

    var body: some View {
        Group {
            if let item {
                if item.lokal != nil {
                    // Nur auf dem Gerät: Bild aus der Mediathek (auch bei Videos nur das Standbild).
                    let quelle = self.quelle
                    FotoSeite(item: item, client: nil, istAktuell: istAktuell, gezoomt: $gezoomt, onTap: onTap,
                              lokalesBild: { await quelle.lokalesBild(fuer: item, pixel: 2048) })
                } else if item.art == .video, let client = store?.client {
                    VideoSeite(item: item, client: client, istAktuell: istAktuell,
                               zeigeBedienung: zeigeBedienung, onTap: onTap, verberge: verberge)
                } else {
                    FotoSeite(item: item, client: store?.client, istAktuell: istAktuell, gezoomt: $gezoomt, onTap: onTap)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: position) {
            // Der Monat ist vielleicht noch nicht geladen: anstoßen und warten.
            while !Task.isCancelled {
                if let gefunden = quelle.item(section: position.section, index: position.index) {
                    item = gefunden
                    return
                }
                store?.ladeMonat(position.section, erzwingen: true)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
}

/// Foto mit Zoom (Pinch, Doppeltipp) und Verschieben. Live Photos lassen sich abspielen.
struct FotoSeite: View {
    let item: Kachel
    let client: ImmichClient?
    let istAktuell: Bool
    @Binding var gezoomt: Bool
    let onTap: () -> Void
    /// Für Fotos, die nur auf dem Gerät liegen.
    var lokalesBild: (() async -> CGImage?)?

    @State private var bild: PlattformBild?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var versatz: CGSize = .zero
    @State private var versatzStart: CGSize = .zero
    @State private var livePlayer: AVPlayer?
    /// Punkt des Fotos (unvergrößert, relativ zur Mitte), der beim Pinch unter den Fingern liegt.
    @State private var pinchPunkt: CGPoint = .zero
    @State private var pinchLaeuft = false
    @State private var letzterZug: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let bild {
                    Image(plattform: bild)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(item.art == .livePhoto ? "Live Photo" : "Foto")
                } else if client == nil && lokalesBild == nil {
                    // Demo ohne Server: Platzhalterfarbe.
                    let c = item.rgb
                    Rectangle()
                        .fill(Color(red: c.r, green: c.g, blue: c.b))
                        .aspectRatio(4 / 3, contentMode: .fit)
                } else {
                    // Bis das Bild da ist: Ladeanzeige statt eines halben Bildes.
                    LadeMond()
                }
                if let livePlayer {
                    PlayerFlaeche(player: livePlayer)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(zoom)
            .offset(versatz)
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(.rect)
            #if os(iOS)
            // UIKit-Pinch: liefert laufend die Fingerposition. So wächst das Foto dort, wo die Finger sind,
            // und lässt sich beim Zoomen gleichzeitig verschieben (wie in Apples Fotos-App).
            .gesture(PinchGeste { zustand, skala, ort in pinch(zustand, skala: skala, ort: ort, groesse: geo.size) })
            #else
            .gesture(
                MagnifyGesture()
                    .onChanged { wert in
                        let start = CGPoint(x: wert.startLocation.x, y: wert.startLocation.y)
                        if !pinchLaeuft { pinch(.began, skala: 1, ort: start, groesse: geo.size) }
                        pinch(.changed, skala: wert.magnification, ort: start, groesse: geo.size)
                    }
                    .onEnded { _ in pinch(.ended, skala: 1, ort: .zero, groesse: geo.size) }
            )
            #endif
            .simultaneousGesture(zoom > 1.01 ? verschieben(in: geo.size) : nil)
            .gesture(SpatialTapGesture(count: 2).onEnded { wert in doppeltipp(bei: wert.location, groesse: geo.size) })
            .onTapGesture(perform: onTap)
        }
        .overlay(alignment: .topLeading) {
            if item.liveVideoId != nil, client != nil, zoom <= 1.01 {
                Button {
                    spieleLive()
                } label: {
                    Label("Live", systemImage: "livephoto")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .lilithGlas(in: .capsule, klar: true)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 112)
                .accessibilityLabel("Live Photo abspielen")
            }
        }
        .task(id: item.id) {
            if let lokalesBild {
                if let cg = await lokalesBild() {
                    #if os(iOS)
                    bild = UIImage(cgImage: cg)
                    #else
                    bild = NSImage(cgImage: cg, size: .zero)
                    #endif
                }
                return
            }
            guard let client else { return }
            // Erst das kleine Bild (meist schon im Cache), dann die scharfe Vorschau.
            if bild == nil, let klein = try? await BilderCache.lade(client.vorschauAnfrage(assetId: item.id, groesse: .thumbnail)) {
                withAnimation(.easeOut(duration: 0.2)) { bild = klein }
            }
            if let gross = try? await BilderCache.lade(client.vorschauAnfrage(assetId: item.id, groesse: .preview)) {
                bild = gross
            }
        }
        .onChange(of: istAktuell) { _, aktuell in
            if !aktuell {
                zoom = 1; zoomStart = 1; versatz = .zero; versatzStart = .zero
                stoppeLive()
            }
        }
        .onChange(of: zoom > 1.01) { _, neu in if istAktuell { gezoomt = neu } }
        .onDisappear { stoppeLive() }
    }

    /// Bildschirmpunkt relativ zur Mitte der Seite.
    private func relativ(_ ort: CGPoint, _ groesse: CGSize) -> CGPoint {
        CGPoint(x: ort.x - groesse.width / 2, y: ort.y - groesse.height / 2)
    }

    /// Zoom um die Finger: Der Fotopunkt unter den Fingern bleibt unter den Fingern, auch wenn sie wandern.
    private func pinch(_ zustand: PinchZustand, skala: CGFloat, ort: CGPoint, groesse: CGSize) {
        switch zustand {
        case .began:
            let c = relativ(ort, groesse)
            pinchPunkt = CGPoint(x: (c.x - versatz.width) / zoom, y: (c.y - versatz.height) / zoom)
            zoomStart = zoom
            pinchLaeuft = true
        case .changed:
            guard pinchLaeuft else { return }
            // Etwas unter 1 erlaubt (federt zurück), nach oben bis 6.
            zoom = min(max(zoomStart * skala, 0.8), 6)
            let c = relativ(ort, groesse)
            versatz = CGSize(width: c.x - pinchPunkt.x * zoom, height: c.y - pinchPunkt.y * zoom)
        case .ended:
            pinchLaeuft = false
            beendeZoom(in: groesse)
        }
    }

    /// Doppeltippen: auf die angetippte Stelle zoomen, oder zurück auf ganz.
    private func doppeltipp(bei ort: CGPoint, groesse: CGSize) {
        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            if zoom > 1.01 {
                zoom = 1
                versatz = .zero
            } else {
                let c = relativ(ort, groesse)
                let ziel: CGFloat = 2.5
                // Die angetippte Stelle rückt zur Mitte.
                versatz = begrenzt(CGSize(width: -(c.x - versatz.width) * ziel, height: -(c.y - versatz.height) * ziel),
                                   in: groesse, zoom: ziel)
                zoom = ziel
            }
        }
        zoomStart = zoom
        versatzStart = versatz
    }

    private func verschieben(in groesse: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { wert in
                // Schrittweise, damit es nach einem Pinch mitten im Ziehen nicht springt.
                let schritt = CGSize(width: wert.translation.width - letzterZug.width,
                                     height: wert.translation.height - letzterZug.height)
                letzterZug = wert.translation
                guard !pinchLaeuft else { return }
                versatz = CGSize(width: versatz.width + schritt.width, height: versatz.height + schritt.height)
            }
            .onEnded { _ in
                letzterZug = .zero
                guard !pinchLaeuft else { return }
                withAnimation(.spring(duration: 0.3, bounce: 0)) { versatz = begrenzt(versatz, in: groesse) }
                versatzStart = versatz
            }
    }

    private func beendeZoom(in groesse: CGSize) {
        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            if zoom <= 1.01 { zoom = 1; versatz = .zero }
            versatz = begrenzt(versatz, in: groesse)
        }
        zoomStart = zoom
        versatzStart = versatz
    }

    /// Das Bild darf nicht weiter verschoben werden, als es durch den Zoom übersteht.
    private func begrenzt(_ v: CGSize, in groesse: CGSize, zoom: CGFloat? = nil) -> CGSize {
        let z = zoom ?? self.zoom
        let maxX = groesse.width * max(z - 1, 0) / 2
        let maxY = groesse.height * max(z - 1, 0) / 2
        return CGSize(width: min(max(v.width, -maxX), maxX), height: min(max(v.height, -maxY), maxY))
    }

    private func spieleLive() {
        guard let client, let liveId = item.liveVideoId, livePlayer == nil else { return }
        let player = AVPlayer(playerItem: AVPlayerItem(asset: videoAsset(client.videoAnfrage(assetId: liveId), client: client)))
        withAnimation { livePlayer = player }
        player.play()
        Task {
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem) {
                break
            }
            stoppeLive()
        }
    }

    private func stoppeLive() {
        livePlayer?.pause()
        withAnimation { livePlayer = nil }
    }
}

/// Video mit eigener Bedienung (iOS) bzw. dem System-Player (Mac). Startet, sobald die Seite vorne ist.
struct VideoSeite: View {
    let item: Kachel
    let client: ImmichClient
    let istAktuell: Bool
    var zeigeBedienung = true
    var onTap: () -> Void = {}
    /// Bedienung ausblenden (nach ein paar Sekunden Abspielen).
    var verberge: () -> Void = {}

    #if os(iOS)
    @State private var modell: PlayerModell?
    #else
    @State private var player: AVPlayer?
    #endif
    @State private var vorschau: PlattformBild?

    var body: some View {
        ZStack {
            if let vorschau {
                // Bleibt hinter dem Video sichtbar, bis das erste Bild des Videos da ist.
                Image(plattform: vorschau).resizable().scaledToFit()
            }
            #if os(iOS)
            if let modell {
                VideoFlaeche(modell: modell)
            } else if vorschau == nil {
                LadeMond()
            }
            #else
            if let player {
                VideoPlayer(player: player)
            } else if vorschau == nil {
                LadeMond()
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        #if os(iOS)
        .overlay(alignment: .bottom) {
            if let modell, zeigeBedienung {
                // Über der Leiste mit Teilen, Favorit und Info.
                VideoBedienung(modell: modell)
                    .padding(.horizontal, 16)
                    .padding(.bottom, VideoSeite.fensterRand().bottom + 72)
                    .transition(.opacity)
            }
        }
        .task(id: (zeigeBedienung && modell?.spielt == true && modell?.zieht == false) ? 1 : 0) {
            // Läuft das Video, verschwindet die Bedienung nach 3 Sekunden.
            guard zeigeBedienung, modell?.spielt == true, modell?.zieht == false else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, modell?.spielt == true, modell?.zieht == false else { return }
            verberge()
        }
        #endif
        .accessibilityLabel("Video, \(item.dauerText)")
        .task(id: item.id) {
            vorschau = try? await BilderCache.lade(client.vorschauAnfrage(assetId: item.id, groesse: .preview))
        }
        .onChange(of: istAktuell, initial: true) { _, aktuell in
            if aktuell { starte() } else { stoppe() }
        }
        .onDisappear { stoppe() }
    }

    private func starte() {
        let neu = AVPlayer(playerItem: AVPlayerItem(asset: videoAsset(client.videoAnfrage(assetId: item.id), client: client)))
        VideoTon.an()
        #if os(iOS)
        let m = PlayerModell(player: neu)
        modell = m
        m.umschalten()
        #else
        player = neu
        neu.play()
        #endif
    }

    private func stoppe() {
        #if os(iOS)
        // Läuft das Video gerade als Bild-in-Bild weiter, nicht anhalten.
        if modell?.pip?.isPictureInPictureActive == true { return }
        modell?.aufraeumen()
        modell = nil
        #else
        player?.pause()
        player = nil
        #endif
        VideoTon.aus()
    }

    #if os(iOS)
    /// Abstände zu Notch und Home-Leiste des Fensters (die Detailansicht selbst nutzt den ganzen Bildschirm).
    static func fensterRand() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }
    #endif
}

/// Ladeanzeige: ein Mond, der zu- und abnimmt. Erscheint erst nach kurzer Zeit, damit sie nicht aufblitzt.
struct LadeMond: View {
    @State private var sichtbar = false
    @State private var phase = 0.25
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    var body: some View {
        VStack(spacing: 14) {
            MondSymbol(phase: phase)
                .frame(width: 44, height: 44)
            Text("Lädt …")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .opacity(sichtbar ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wird geladen")
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.25)) { sichtbar = true }
            guard !wenigBewegung else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { phase = 0.85 }
        }
    }
}

/// Video-Quelle mit Anmelde-Headern.
func videoAsset(_ anfrage: URLRequest, client: ImmichClient) -> AVURLAsset {
    AVURLAsset(url: anfrage.url!, options: ["AVURLAssetHTTPHeaderFieldsKey": client.anmeldeHeader])
}

/// Reine Videofläche ohne Bedienelemente (für Live Photos).
#if canImport(UIKit)
struct PlayerFlaeche: UIViewRepresentable {
    let player: AVPlayer

    final class Ansicht: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    }

    func makeUIView(context: Context) -> Ansicht {
        let v = Ansicht()
        v.isUserInteractionEnabled = false
        (v.layer as? AVPlayerLayer)?.player = player
        (v.layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ v: Ansicht, context: Context) {
        (v.layer as? AVPlayerLayer)?.player = player
    }
}
#else
struct PlayerFlaeche: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let ebene = AVPlayerLayer(player: player)
        ebene.videoGravity = .resizeAspect
        v.layer = ebene
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        (v.layer as? AVPlayerLayer)?.player = player
    }
}
#endif

/// Eintrag aus dem Grid. Eigener Name, weil SwiftUI auch einen Typ „Kachel“ hat.
typealias Kachel = TimelineGrid.GridItem

enum PinchZustand { case began, changed, ended }

#if os(iOS)
/// Pinch von UIKit, weil SwiftUIs `MagnifyGesture` nur den Startpunkt kennt, nicht wo die Finger gerade sind.
struct PinchGeste: UIGestureRecognizerRepresentable {
    let aktion: (PinchZustand, CGFloat, CGPoint) -> Void

    init(_ aktion: @escaping (PinchZustand, CGFloat, CGPoint) -> Void) { self.aktion = aktion }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer { UIPinchGestureRecognizer() }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let ort = context.converter.localLocation
        switch recognizer.state {
        case .began: aktion(.began, 1, ort)
        case .changed:
            // Hebt man einen Finger, springt der Mittelpunkt: dann den Startpunkt neu setzen.
            if recognizer.numberOfTouches < 2 { return }
            aktion(.changed, recognizer.scale, ort)
        case .ended, .cancelled, .failed: aktion(.ended, 1, ort)
        default: break
        }
    }
}
#endif
