#if os(iOS)
import AVFoundation
import AVKit
import SwiftUI
import DesignSystem

/// Einstellungen rund ums Video.
enum VideoEinstellung {
    static let schluesselBildInBild = "luna.video.automatischBildInBild"
    /// Läuft ein Video, geht es beim Verlassen der App automatisch ins Bild-in-Bild. Voreinstellung: an.
    static var automatischBildInBild: Bool {
        UserDefaults.standard.object(forKey: schluesselBildInBild) as? Bool ?? true
    }
}

/// Zustand eines Videos für die eigene Bedienung: läuft es, wo steht es, wie lang ist es.
@MainActor
@Observable
final class PlayerModell {
    let player: AVPlayer
    private(set) var spielt = false
    var zeit: Double = 0
    private(set) var dauer: Double = 0
    private(set) var stumm = false
    /// Während man an der Zeitleiste zieht, überschreibt der Player die Zeit nicht.
    var zieht = false
    /// Bild-in-Bild, sobald die Videofläche steht.
    var pip: AVPictureInPictureController?
    @ObservationIgnored private var beobachter: Any?
    @ObservationIgnored private var endeAufgabe: Task<Void, Never>?

    init(player: AVPlayer) {
        self.player = player
        beobachter = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.aktualisiere(t) }
        }
        // Am Ende hält der Player an, und der Zeit-Beobachter meldet sich nicht mehr: Knopf zurück auf „Abspielen“.
        let item = player.currentItem
        endeAufgabe = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item) {
                guard let self else { return }
                self.spielt = false
                self.zeit = self.dauer
            }
        }
    }

    private func aktualisiere(_ t: CMTime) {
        if !zieht, t.isNumeric { zeit = t.seconds }
        if let d = player.currentItem?.duration, d.isNumeric, d.seconds > 0 { dauer = d.seconds }
        spielt = player.timeControlStatus != .paused
    }

    func umschalten() {
        if spielt {
            player.pause()
        } else {
            // Am Ende: von vorn.
            if dauer > 0, zeit >= dauer - 0.1 { player.seek(to: .zero) }
            player.play()
        }
        spielt.toggle()
    }

    func spule(zu sekunden: Double) {
        zeit = min(max(sekunden, 0), dauer)
        player.seek(to: CMTime(seconds: zeit, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func tonUmschalten() {
        stumm.toggle()
        player.isMuted = stumm
    }

    func aufraeumen() {
        if let beobachter { player.removeTimeObserver(beobachter) }
        beobachter = nil
        endeAufgabe?.cancel()
        player.pause()
    }
}

/// Videofläche mit `AVPlayerLayer`, über die auch Bild-in-Bild läuft.
struct VideoFlaeche: UIViewRepresentable {
    let modell: PlayerModell

    final class Ansicht: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var ebene: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> Ansicht {
        let v = Ansicht()
        v.isUserInteractionEnabled = false
        v.ebene.player = modell.player
        v.ebene.videoGravity = .resizeAspect
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(contentSource: .init(playerLayer: v.ebene))
            // Wischt man die App weg, während das Video läuft, geht es von selbst ins Bild-in-Bild
            // (abschaltbar in den Einstellungen).
            pip.canStartPictureInPictureAutomaticallyFromInline = VideoEinstellung.automatischBildInBild
            modell.pip = pip
        }
        return v
    }

    func updateUIView(_ v: Ansicht, context: Context) {
        if v.ebene.player !== modell.player { v.ebene.player = modell.player }
    }
}

/// AirPlay-Knopf von iOS.
struct AirPlayKnopf: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .label  // dunkel auf hell, hell auf dunkel
        v.activeTintColor = UIColor(LilithColor.nachtrose)
        v.prioritizesVideoDevices = true
        return v
    }

    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

/// Eigene Bedienung: eine Glas-Kapsel mit Abspielen, Zeitleiste, Ton, Bild-in-Bild und AirPlay.
struct VideoBedienung: View {
    let modell: PlayerModell
    @Environment(\.colorScheme) private var schema

    var body: some View {
        HStack(spacing: 4) {
            Button { modell.umschalten() } label: {
                Image(systemName: modell.spielt ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(modell.spielt ? "Pause" : "Abspielen")

            // Wie Apple: nur Abspielen, Zeitleiste und Ton. Die Zeiten erscheinen beim Ziehen.
            if modell.zieht {
                Text(Self.zeit(modell.zeit))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 34, alignment: .trailing)
                    .transition(.opacity)
            }
            Zeitleiste(modell: modell)
                .padding(.horizontal, 6)
            if modell.zieht {
                Text("-" + Self.zeit(max(modell.dauer - modell.zeit, 0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 38, alignment: .leading)
                    .transition(.opacity)
            }

            Button { modell.tonUmschalten() } label: {
                Image(systemName: modell.stumm ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 36, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(modell.stumm ? "Ton an" : "Ton aus")

        }
        .buttonStyle(.plain)
        // Wie Apple: im hellen Modus hell getöntes Glas mit dunklen Symbolen, im dunklen wie bisher.
        .foregroundStyle(schema == .dark ? Color.white : Color.black)
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.15), value: modell.zieht)
        .lilithGlas(in: .capsule, toenung: schema == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.38))
    }

    static func zeit(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let ganz = Int(s.rounded(.down))
        return String(format: "%d:%02d", ganz / 60, ganz % 60)
    }
}

/// Schlanke Zeitleiste: ziehen spult (genau, ohne Sprünge), beim Ziehen wird sie etwas dicker.
private struct Zeitleiste: View {
    let modell: PlayerModell

    var body: some View {
        GeometryReader { geo in
            let anteil = modell.dauer > 0 ? min(max(modell.zeit / modell.dauer, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.25))
                Capsule().fill(.primary).frame(width: geo.size.width * anteil)
            }
            .frame(height: modell.zieht ? 8 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { wert in
                        modell.zieht = true
                        modell.spule(zu: wert.location.x / max(geo.size.width, 1) * modell.dauer)
                    }
                    .onEnded { _ in modell.zieht = false }
            )
            .animation(.easeOut(duration: 0.15), value: modell.zieht)
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue(VideoBedienung.zeit(modell.zeit))
        .accessibilityAdjustableAction { richtung in
            switch richtung {
            case .increment: modell.spule(zu: modell.zeit + 5)
            case .decrement: modell.spule(zu: modell.zeit - 5)
            @unknown default: break
            }
        }
    }
}
#endif
