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
                if item.art == .video, let client = store?.client {
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
                } else {
                    // Ohne Server (Demo) oder bis das Bild da ist: Platzhalterfarbe.
                    let c = item.rgb
                    Rectangle()
                        .fill(Color(red: c.r, green: c.g, blue: c.b))
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .padding(client == nil ? 0 : 40)
                        .opacity(client == nil ? 1 : 0.5)
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
                        .background(.ultraThinMaterial, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 112)
                .accessibilityLabel("Live Photo abspielen")
            }
        }
        .task(id: item.id) {
            guard let client else { return }
            // Erst das kleine Bild (meist schon im Cache), dann die scharfe Vorschau.
            if bild == nil, let klein = try? await BilderCache.lade(client.vorschauAnfrage(assetId: item.id, groesse: .thumbnail)) {
                bild = klein
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
            if let vorschau, player == nil {
                Image(plattform: vorschau).resizable().scaledToFit()
            }
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
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
