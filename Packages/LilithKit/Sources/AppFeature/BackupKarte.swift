import SwiftUI
import DesignSystem
import Backup
import Networking
import TimelineGrid
#if os(iOS)
import Photos
import PhotosUI
#endif

/// Konto-Kreis mit Mond-Ring: Er füllt sich mit dem Backup. Wolke = angehalten, roter Rand = Fehler.
struct KontoKnopf: View {
    let buchstabe: String
    let backup: BackupDienst?
    var client: ImmichClient?
    var nutzerId: String?
    let oeffnen: () -> Void

    private var zeigeRing: Bool {
        guard let backup, backup.aktiv else { return false }
        return !backup.allesGesichert || backup.uebersicht.fehler > 0
    }

    var body: some View {
        Button(action: oeffnen) {
            ProfilBild(client: client, nutzerId: nutzerId, buchstabe: buchstabe, groesse: 30)
                .padding(zeigeRing ? 4 : 0)
                .overlay {
                    // Nur solange gesichert wird (oder etwas fehlt): Ist alles auf dem Server, verschwindet der Ring.
                    if let backup, zeigeRing {
                        MondRing(anteil: backup.uebersicht.anteil, fehler: backup.uebersicht.fehler > 0, breite: 2.5)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: zeigeRing)
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

/// Profilbild vom Server. Ohne Bild (oder offline) der Anfangsbuchstabe im Nachtrose-Kreis.
struct ProfilBild: View {
    let client: ImmichClient?
    let nutzerId: String?
    let buchstabe: String
    let groesse: CGFloat
    @State private var bild: PlattformBild?

    var body: some View {
        ZStack {
            Circle().fill(LilithColor.nachtroseFill)
            if let bild {
                Image(plattform: bild).resizable().scaledToFill()
            } else {
                Text(buchstabe)
                    .font(.system(size: groesse * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: groesse, height: groesse)
        .clipShape(.circle)
        .task(id: nutzerId) {
            guard let client, let nutzerId else { return }
            // Ohne Profilbild antwortet der Server mit 404: dann bleibt der Buchstabe.
            bild = try? await BilderCache.lade(client.profilbildAnfrage(nutzerId: nutzerId))
        }
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
    var uploads: UploadWarteschlange?
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
                 ? "Luna sichert beim Öffnen der App und im Hintergrund, meist nachts am Ladekabel im WLAN. Wann genau, entscheidet iOS."
                 : "Deine Fotos gehen nur an deinen eigenen Server. Fotos, die schon dort sind (auch von der Immich-App), erkennt Luna und lädt sie nicht noch einmal hoch.")
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
                Label("Nur ausgewählte Fotos sind freigegeben. Luna sichert nur diese.", systemImage: "photo.badge.checkmark")
                    .font(.subheadline)
                Button("Auswahl ändern") { aendereAuswahl() }
            }
        }
        if backup.uebersicht.fehler > 0 || backup.uebersicht.uebersprungen > 0 {
            NavigationLink {
                FehlerListeView(uploads: uploads, backup: backup)
            } label: {
                if backup.uebersicht.fehler > 0 {
                    Label("\(backup.uebersicht.fehler) nicht gesichert", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                } else {
                    Label("\(backup.uebersicht.uebersprungen) übersprungen", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        if case .halt = backup.phase, backup.zugriff == .verweigert {
            Button("Einstellungen öffnen") { oeffneEinstellungen() }
        }
        NavigationLink {
            AlbenAuswahlView(backup: backup)
        } label: {
            LabeledContent("Alben", value: albenText)
        }
        NavigationLink {
            BackupEinstellungenView(backup: backup)
        } label: {
            LabeledContent("Einstellungen", value: backup.einstellungen.nurWLAN ? "Nur WLAN" : "WLAN und Mobilfunk")
        }
        if #available(iOS 26, *) {
            // Läuft weiter, wenn du die App verlässt. iOS zeigt den Fortschritt an.
            Button("Jetzt sichern") {
                if !BackupZentrale.shared.jetztSichern() { backup.starte() }
            }
            .disabled(BackupZentrale.shared.jetztAktiv)
        } else {
            Button("Jetzt prüfen") { backup.starte() }
                .disabled(backup.laeuft)
        }
        Button("Backup ausschalten", role: .destructive) { backup.ausschalten() }
    }

    /// Kurzfassung der Albenauswahl.
    private var albenText: String {
        let a = backup.auswahl
        if a.leer { return "Keine" }
        let basis = a.gewaehlt.contains(AlbenAuswahl.alle)
            ? "Alle Fotos" : (a.gewaehlt.count == 1 ? "1 Album" : "\(a.gewaehlt.count) Alben")
        return a.ausgeschlossen.isEmpty ? basis : "\(basis), \(a.ausgeschlossen.count) ausgeschlossen"
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

#if os(iOS)
/// Alben fürs Backup auswählen, wie in der Immich-App:
/// einmal antippen = sichern, zweimal = ausschließen, dreimal = neutral.
struct AlbenAuswahlView: View {
    let backup: BackupDienst
    @State private var alben: [MediathekAlbum] = []
    @State private var laedt = true
    @State private var auswahl: AlbenAuswahl

    init(backup: BackupDienst) {
        self.backup = backup
        _auswahl = State(initialValue: backup.auswahl)
    }

    var body: some View {
        List {
            Section {
                zeile(id: AlbenAuswahl.alle, titel: "Alle Fotos", untertitel: "Alles in der Mediathek", bildId: nil)
            } footer: {
                Text(auswahl.leer
                     ? "Nichts gewählt: Es wird nichts gesichert."
                     : "Einmal tippen: sichern. Zweimal: ausschließen (z. B. Screenshots). Gesichert wird, was in einem gewählten und in keinem ausgeschlossenen Album liegt.")
            }
            if laedt {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            let eigene = alben.filter { !$0.vonIOS }
            if !eigene.isEmpty {
                Section("Meine Alben") {
                    ForEach(eigene) { a in zeile(id: a.id, titel: a.titel, untertitel: anzahl(a.anzahl), bildId: a.titelBildId) }
                }
            }
            let ios = alben.filter(\.vonIOS)
            if !ios.isEmpty {
                Section("Von iOS") {
                    ForEach(ios) { a in zeile(id: a.id, titel: a.titel, untertitel: anzahl(a.anzahl), bildId: a.titelBildId) }
                }
            }
            Section {
                Toggle("Alben auch auf dem Server anlegen", isOn: Binding(
                    get: { backup.serverAlben }, set: { backup.setze(serverAlben: $0) }))
                    .tint(LilithColor.schalter)
            } footer: {
                Text("Gesicherte Fotos aus deinen gewählten Alben landen auf dem Server im Album mit demselben Namen.")
            }
        }
        .navigationTitle("Alben fürs Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            alben = await backup.mediathekAlben()
            laedt = false
        }
        .onDisappear {
            if auswahl != backup.auswahl { backup.setze(auswahl: auswahl) }
        }
    }

    private func anzahl(_ n: Int) -> String { n == 1 ? "1 Objekt" : "\(n.formatted(.number)) Objekte" }

    private func zeile(id: String, titel: String, untertitel: String, bildId: String?) -> some View {
        let zustand = auswahl.zustand(id)
        return Button {
            auswahl.weiter(id)
        } label: {
            HStack(spacing: 12) {
                LokalesVorschaubild(backup: backup, id: bildId, kante: 44)
                    .clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel).foregroundStyle(LilithColor.text)
                    Text(untertitel).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                switch zustand {
                case .neutral:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                case .gewaehlt:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LilithColor.nachtrose)
                case .ausgeschlossen:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .font(.body)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(zustand == .gewaehlt ? "wird gesichert" : zustand == .ausgeschlossen ? "ausgeschlossen" : "nicht gewählt")
    }
}

/// Einstellungen des Backups: wann und was gesichert wird.
struct BackupEinstellungenView: View {
    let backup: BackupDienst
    @State private var e: BackupEinstellungen

    init(backup: BackupDienst) {
        self.backup = backup
        _e = State(initialValue: backup.einstellungen)
    }

    private static let erklaerung = [
        "Beim Öffnen der App holt Luna immer nach, was fehlt. Das ist der zuverlässigste Weg.",
        "Verlässt du die App, übergibt Luna die nächsten Uploads an iOS. Sie laufen weiter, auch wenn die App geschlossen ist.",
        "Nachts am Ladekabel im WLAN darf Luna länger arbeiten, auch für große Videos und iCloud-Originale.",
        "Einen festen Takt gibt es nicht: iOS entscheidet. Stromsparmodus und Beenden der App im App-Umschalter pausieren das Backup.",
        "Das erste Backup einer großen Mediathek kann mehrere Nächte dauern.",
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Nur über WLAN", isOn: $e.nurWLAN)
                    .tint(LilithColor.schalter)
                Toggle("Nur beim Laden", isOn: $e.nurBeimLaden)
                    .tint(LilithColor.schalter)
            } footer: {
                Text("Ohne WLAN vergleicht Luna nur mit dem Server (wenige Daten) und lädt erst im WLAN hoch.")
            }
            Section {
                Toggle("Videos sichern", isOn: $e.videos)
                    .tint(LilithColor.schalter)
                Toggle("Originale aus iCloud laden", isOn: $e.iCloud)
                    .tint(LilithColor.schalter)
            } footer: {
                Text("Bei „iPhone-Speicher optimieren“ liegen manche Originale nur in iCloud. Luna lädt sie dann einzeln und sichert sie. Ist weniger als 1 GB frei, hält das Backup an.")
            }
            Section("So funktioniert das Backup") {
                ForEach(Self.erklaerung, id: \.self) { satz in
                    Label(satz, systemImage: "moon.stars")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Backup-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if e != backup.einstellungen { backup.setze(einstellungen: e) }
        }
    }
}

/// Vorschaubild direkt vom Gerät.
struct LokalesVorschaubild: View {
    let backup: BackupDienst
    let id: String?
    let kante: CGFloat
    @State private var bild: CGImage?
    @Environment(\.displayScale) private var skala

    var body: some View {
        ZStack {
            LilithColor.flaeche
            if let bild {
                Image(decorative: bild, scale: skala).resizable().scaledToFill()
            } else {
                Image(systemName: id == nil ? "photo.stack" : "photo").foregroundStyle(LilithColor.textLeise)
            }
        }
        .frame(width: kante, height: kante)
        .clipped()
        .task(id: id) {
            guard let id else { bild = nil; return }
            bild = await backup.vorschau(id, kante: kante * skala)
        }
    }
}
#endif
