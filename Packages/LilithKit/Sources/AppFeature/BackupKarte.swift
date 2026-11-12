import SwiftUI
import DesignSystem
import Backup
#if os(iOS)
import Photos
import PhotosUI
#endif

/// Konto-Kreis mit Mond-Ring: Er füllt sich mit dem Backup. Wolke = angehalten, roter Rand = Fehler.
struct KontoKnopf: View {
    let buchstabe: String
    let backup: BackupDienst?
    let oeffnen: () -> Void

    var body: some View {
        Button(action: oeffnen) {
            Text(buchstabe)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(LilithColor.nachtroseFill, in: .circle)
                .padding(backup?.aktiv == true ? 4 : 0)
                .overlay {
                    if let backup, backup.aktiv {
                        MondRing(anteil: backup.uebersicht.anteil, fehler: backup.uebersicht.fehler > 0, breite: 2)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let backup, backup.aktiv, case .halt = backup.phase {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(LilithColor.textLeise)
                            .offset(x: 3, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Konto und Server")
        .accessibilityValue(backup?.aktiv == true ? backup!.zaehlerText : "")
    }
}

/// Ring vom Neumond (leer) bis Vollmond (voll).
struct MondRing: View {
    let anteil: Double
    var fehler = false
    var breite: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(fehler ? Color.red.opacity(0.7) : LilithColor.mondlicht.opacity(0.25),
                            lineWidth: fehler ? 1 : breite)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, anteil)))
                .stroke(LilithColor.mondlicht, style: StrokeStyle(lineWidth: breite, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: anteil)
    }
}

#if os(iOS)
/// Abschnitt „Backup“ im Konto: Einladung zum Einschalten oder Statuskarte.
struct BackupKarte: View {
    let backup: BackupDienst
    @Environment(\.openURL) private var openURL

    private var geraet: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        Section {
            if backup.aktiv {
                status
            } else {
                einladung
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(backup.aktiv
                 ? "Lilith sichert, solange die App geöffnet ist. Sichern im Hintergrund kommt in einer späteren Version."
                 : "Deine Fotos gehen nur an deinen eigenen Server. Fotos, die schon dort sind (auch von der Immich-App), erkennt Lilith und lädt sie nicht noch einmal hoch.")
        }
    }

    private var einladung: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MondSymbol(phase: 0.15).frame(width: 34, height: 34)
                Text("Fotos von diesem \(geraet) sichern").font(.headline)
            }
            if case .halt(let grund) = backup.phase {
                Text(grund).font(.subheadline).foregroundStyle(.secondary)
                Button("Einstellungen öffnen") { oeffneEinstellungen() }
            } else {
                Button("Backup einschalten") { Task { await backup.einschalten() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 14) {
            ZStack {
                MondRing(anteil: backup.uebersicht.anteil, fehler: backup.uebersicht.fehler > 0)
                // Phase 0 = Neumond, 1 = Vollmond: wächst mit dem Backup.
                MondSymbol(phase: backup.uebersicht.anteil).padding(8)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(backup.zaehlerText).font(.headline).monospacedDigit()
                Text(backup.statusText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if backup.laeuft { ProgressView() }
        }
        .padding(.vertical, 4)

        if backup.zugriff == .eingeschraenkt {
            VStack(alignment: .leading, spacing: 6) {
                Label("Nur ausgewählte Fotos sind freigegeben. Lilith sichert nur diese.", systemImage: "photo.badge.checkmark")
                    .font(.subheadline)
                Button("Auswahl ändern") { aendereAuswahl() }
            }
        }
        if backup.uebersicht.fehler > 0 {
            Button {
                backup.wiederholeFehler()
            } label: {
                Label("\(backup.uebersicht.fehler) nicht gesichert – erneut versuchen", systemImage: "exclamationmark.circle")
            }
            .tint(.red)
        }
        if backup.uebersicht.uebersprungen > 0 {
            Label("\(backup.uebersicht.uebersprungen) übersprungen (meist: Original nur in iCloud)", systemImage: "icloud")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if case .halt = backup.phase, backup.zugriff == .verweigert {
            Button("Einstellungen öffnen") { oeffneEinstellungen() }
        }
        Button("Jetzt prüfen") { backup.starte() }
            .disabled(backup.laeuft)
        Button("Backup ausschalten", role: .destructive) { backup.ausschalten() }
    }

    private func oeffneEinstellungen() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func aendereAuswahl() {
        let szene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var oben = szene?.keyWindow?.rootViewController else { return }
        while let weiter = oben.presentedViewController { oben = weiter }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: oben) { _ in
            Task { @MainActor in
                backup.aktualisiereZugriff()
                backup.starte()
            }
        }
    }
}
#endif
