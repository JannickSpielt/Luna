import AVKit
import SwiftUI
import DesignSystem
import Networking
import TimelineGrid

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
                    VideoSeite(item: item, client: client, istAktuell: istAktuell)
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
            .contentShape(.rect)
            .gesture(
                MagnifyGesture()
                    .onChanged { wert in zoom = min(max(zoomStart * wert.magnification, 1), 6) }
                    .onEnded { _ in beendeZoom(in: geo.size) }
            )
            .simultaneousGesture(zoom > 1.01 ? verschieben(in: geo.size) : nil)
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    zoom = zoom > 1.01 ? 1 : 2.5
                    versatz = .zero
                }
                beendeZoom(in: geo.size)
            }
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

    private func verschieben(in groesse: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { wert in
                versatz = CGSize(width: versatzStart.width + wert.translation.width,
                                 height: versatzStart.height + wert.translation.height)
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.3)) { versatz = begrenzt(versatz, in: groesse) }
                versatzStart = versatz
            }
    }

    private func beendeZoom(in groesse: CGSize) {
        withAnimation(.spring(duration: 0.3)) {
            if zoom <= 1.01 { zoom = 1; versatz = .zero }
            versatz = begrenzt(versatz, in: groesse)
        }
        zoomStart = zoom
        versatzStart = versatz
    }

    /// Das Bild darf nicht weiter verschoben werden, als es durch den Zoom übersteht.
    private func begrenzt(_ v: CGSize, in groesse: CGSize) -> CGSize {
        let maxX = groesse.width * (zoom - 1) / 2
        let maxY = groesse.height * (zoom - 1) / 2
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

/// Video mit den System-Bedienelementen. Startet, sobald die Seite vorne ist.
struct VideoSeite: View {
    let item: Kachel
    let client: ImmichClient
    let istAktuell: Bool

    @State private var player: AVPlayer?
    @State private var vorschau: PlattformBild?

    var body: some View {
        ZStack {
            if let vorschau {
                // Bleibt hinter dem Player sichtbar, bis das erste Bild des Videos da ist.
                Image(plattform: vorschau).resizable().scaledToFit()
            }
            if let player {
                #if os(iOS)
                // Apples voller Player (Vollbild, Bild-in-Bild, Geschwindigkeit). Er liegt zwischen den eigenen
                // Leisten oben und unten, damit sich die Bedienelemente nicht überdecken.
                let rand = VollerPlayer.fensterRand()
                VollerPlayer(player: player)
                    .padding(.top, rand.top + 64)
                    .padding(.bottom, rand.bottom + 76)
                #else
                VideoPlayer(player: player)
                #endif
            } else if vorschau == nil {
                LadeMond()
            }
        }
        .accessibilityLabel("Video, \(item.dauerText)")
        .task(id: item.id) {
            vorschau = try? await BilderCache.lade(client.vorschauAnfrage(assetId: item.id, groesse: .preview))
        }
        .onChange(of: istAktuell, initial: true) { _, aktuell in
            if aktuell {
                let neu = AVPlayer(playerItem: AVPlayerItem(asset: videoAsset(client.videoAnfrage(assetId: item.id), client: client)))
                player = neu
                neu.play()
            } else {
                player?.pause()
                player = nil
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

#if os(iOS)
/// `AVPlayerViewController` mit allen Bedienelementen.
struct VollerPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = false
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }

    /// Abstände zu Notch und Home-Leiste des Fensters (die Detailansicht selbst nutzt den ganzen Bildschirm).
    static func fensterRand() -> UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }
}
#endif

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
