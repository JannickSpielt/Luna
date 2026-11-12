import SwiftUI
import DesignSystem
import Networking
import TimelineGrid
import Backup
import PhotosUI
import UniformTypeIdentifiers

/// Die Bibliothek: alle Fotos und Videos als Timeline mit Scrubber.
struct BibliothekView: View {
    let quelle: TimelineQuelle
    /// Nur bei echter Verbindung gesetzt (nicht im Demo-Modus).
    let store: TimelineStore?
    @Binding var zeigeKonto: Bool
    let kontoBuchstabe: String

    var body: some View {
        NavigationStack {
            TimelineInhalt(titel: "Fotos", quelle: quelle, store: store,
                           konto: (kontoBuchstabe, { zeigeKonto = true }))
        }
    }
}

/// Eine Timeline mit Scrubber, Detailansicht und Mehrfachauswahl.
/// Wird für die Bibliothek, Favoriten, Archiv, Papierkorb und Alben benutzt.
struct TimelineInhalt: View {
    let titel: String
    let quelle: TimelineQuelle
    let store: TimelineStore?
    var konto: (buchstabe: String, oeffnen: () -> Void)?

    @Environment(BibliothekKontext.self) private var kontext
    @State private var zoom: GridZoom = Self.startZoom
    @State private var sprung: SprungAnfrage?
    /// Eigenes Objekt, damit beim Scrollen nur der Scrubber neu gezeichnet wird, nicht die ganze Ansicht.
    @State private var scroll = ScrollStand()
    /// Tab-Leiste unten: verschwindet beim Scrollen in ältere Fotos.
    @State private var leisteSichtbar = true
    @AppStorage(NichtGesicherte.schluessel) private var zeigeNichtGesicherte = true
    @State private var auswahlModus = false
    @State private var auswahl: [String] = []
    @State private var auswahlStand = 0
    @State private var arbeitet = false
    @State private var frageLoeschen = false
    @State private var zeigeAlbumWahl = false
    @State private var fehler: String?


    private var filter: TimelineFilter { store?.filter ?? .alle }

    // Hochladen
    @State private var fotoAuswahl: [PhotosPickerItem] = []
    @State private var zeigeImport = false
    @State private var ziehtDarueber = false

    /// Hochladen gibt es in der Bibliothek und in Alben, nicht in Favoriten, Archiv, Papierkorb oder Suche.
    private var kannHochladen: Bool {
        guard kontext.uploads != nil else { return false }
        switch filter {
        case .alle, .album: return true
        default: return false
        }
    }

    private var zielAlbum: String? {
        if case .album(let id) = filter { return id }
        return nil
    }

    private static var startZoom: GridZoom {
        #if os(macOS)
        .mac
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    var body: some View {
        inhalt
            .background(LilithColor.hintergrund)
            .navigationTitle(auswahl.isEmpty ? titel : "\(auswahl.count) ausgewählt")
            #if os(iOS)
            // Kein großer Titel über weißem Grund: Die Fotos beginnen ganz oben.
            .navigationBarTitleDisplayMode(.inline)
            .modifier(TitelAusblenden(aktiv: konto != nil && store?.zustand == .bereit))
            #if os(iOS)
            .toolbarVisibility(leisteSichtbar ? .visible : .hidden, for: .tabBar)
            #endif
            #endif
            .toolbar { werkzeuge }
            #if os(iOS)
            .toolbar {
                // In Sammlungen: Titel in einer Glas-Kapsel, gut lesbar über den Fotos.
                if konto == nil {
                    ToolbarItem(placement: .principal) {
                        Text(auswahl.isEmpty ? titel : "\(auswahl.count) ausgewählt")
                            .font(.headline)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .lilithGlas(in: .capsule)
                    }
                }
            }
            #endif
            .overlay(alignment: .top) {
                if let hinweis = store?.hinweis {
                    OfflineHinweis(text: hinweis) { Task { await store?.laden() } }
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: store?.hinweis)
            .overlay(alignment: .bottom) {
                if auswahl.isEmpty, kontext.detail == nil, let uploads = kontext.uploads {
                    UploadAnzeige(uploads: uploads)
                }
            }
            .overlay {
                if ziehtDarueber {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(LilithColor.nachtrose, lineWidth: 3)
                        .background(LilithColor.nachtrose.opacity(0.08), in: .rect(cornerRadius: 18))
                        .overlay {
                            Label(zielAlbum == nil ? "Zum Hochladen loslassen" : "In dieses Album hochladen",
                                  systemImage: "arrow.up.circle")
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(.regularMaterial, in: .capsule)
                        }
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard kannHochladen else { return false }
                ladeHoch(urls, quelle: "ziehen")
                return true
            } isTargeted: { ziehtDarueber = kannHochladen && $0 }
            .fileImporter(isPresented: $zeigeImport, allowedContentTypes: [.image, .movie, .folder],
                          allowsMultipleSelection: true) { ergebnis in
                if case .success(let urls) = ergebnis { ladeHoch(urls, quelle: "import") }
            }
            .onChange(of: zeigeNichtGesicherte) { _, _ in Task { await store?.laden() } }
            .onChange(of: fotoAuswahl) { _, neu in
                guard !neu.isEmpty else { return }
                ladeHochAusAuswahl(neu)
                fotoAuswahl = []
            }
            .overlay(alignment: .bottom) {
                if !auswahl.isEmpty && kontext.detail == nil {
                    aktionsleiste.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.25), value: auswahl.isEmpty)
            .task {
                if let store, store.zustand == .laedt { await store.laden() }
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "LilithSprung"), !quelle.sections.isEmpty {
                    try? await Task.sleep(for: .seconds(2))
                    sprung = SprungAnfrage(section: quelle.sections.count - 1)
                }
                // Zum Testen: „-LilithSprungMonat 12“ springt zum 12. Monat (0 = neuester).
                let monat = UserDefaults.standard.integer(forKey: "LilithSprungMonat")
                if monat > 0, monat < quelle.sections.count {
                    try? await Task.sleep(for: .seconds(2))
                    sprung = SprungAnfrage(section: monat)
                }
                #endif
            }
            .onChange(of: kontext.stand) { _, _ in
                // Eine andere Ansicht hat etwas geändert: hier neu laden.
                if kontext.letzteQuelle !== store { Task { await store?.laden() } }
            }
            .confirmationDialog(loeschFrage, isPresented: $frageLoeschen, titleVisibility: .visible) {
                Button(loeschtEndgueltig ? "Endgültig löschen" : "In den Papierkorb", role: .destructive) {
                    let endgueltig = loeschtEndgueltig
                    fuehreAus { try await $0.loesche(assetIds: $1, endgueltig: endgueltig) }
                }
            } message: {
                Text(loeschtEndgueltig ? "Das lässt sich nicht rückgängig machen."
                                       : "Du kannst sie im Papierkorb wiederherstellen.")
            }
            .sheet(isPresented: $zeigeAlbumWahl) {
                AlbumWahl(anzahl: auswahl.count) { ziel in
                    switch ziel {
                    case .vorhanden(let album): fuehreAus { try await $0.fuegeZuAlbum(albumId: album.id, assetIds: $1) }
                    case .neu(let name): fuehreAus { _ = try await $0.erstelleAlbum(name: name, assetIds: $1) }
                    }
                }
            }
            .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
                Button("OK") { fehler = nil }
            } message: { Text($0) }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var inhalt: some View {
        switch store?.zustand ?? .bereit {
        case .laedt:
            VStack(spacing: 16) {
                MondSymbol(phase: 0.5).frame(width: 48, height: 48)
                Text("Wird geladen …").foregroundStyle(LilithColor.textLeise)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .leer:
            let text = Self.leerText(filter)
            ContentUnavailableView {
                Label(text.titel, systemImage: text.symbol)
            } description: {
                Text(text.text)
            }
        case .fehler(let text):
            ContentUnavailableView {
                Label("Nicht geladen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Erneut versuchen") { Task { await store?.laden() } }
                    .buttonStyle(.borderedProminent)
            }
        case .bereit:
            #if os(iOS)
            // Die Fotos laufen unter Statusleiste, Leiste und Tab-Leiste durch. Darüber: Titel, Monats-Etikett
            // aus Glas und Scrubber, jeweils mit Abstand zu den Leisten (rand = Bereich unter der Leiste).
            GeometryReader { geo in
                let rand = geo.safeAreaInsets
                // Abstand zur Statusleiste: Der Titel steht in derselben Reihe wie die Leiste rechts.
                let fenster = VideoSeite.fensterRand().top
                raster
                    .ignoresSafeArea()
                    .overlay(alignment: .top) {
                        // Weicher Verlauf, damit Titel und Leiste über hellen Fotos lesbar bleiben.
                        LinearGradient(colors: [.black.opacity(0.38), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: fenster + 90)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topLeading) {
                        // Kein großer Titel: Der Tab sagt schon, wo man ist. Oben links steht, was man sieht –
                        // Monat, Ort und Anzahl, in derselben Reihe wie die Leiste rechts (bzw. die Auswahl).
                        // Nur in „Fotos“. In Sammlungen (Alben, Videos …) steht oben schon der Titel.
                        if konto != nil {
                            MonatsEtikett(quelle: quelle, scroll: scroll,
                                          auswahlText: auswahl.isEmpty ? nil : "\(auswahl.count) ausgewählt")
                                // Nie unter die Leiste rechts: lange Ortsnamen werden gekürzt.
                                .frame(maxWidth: max(geo.size.width - 200, 120), alignment: .leading)
                                .padding(.leading, 16)
                                .padding(.top, fenster)
                                .ignoresSafeArea(edges: .top)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        ScrubberMitStand(quelle: quelle, scroll: scroll, umgekehrt: umgekehrt) { sprung = SprungAnfrage(section: $0) }
                            .padding(.top, fenster + 72)
                            .padding(.bottom, rand.bottom + 8)
                    }
            }
            #else
            raster
                .overlay(alignment: .trailing) {
                    ScrubberMitStand(quelle: quelle, scroll: scroll) { sprung = SprungAnfrage(section: $0) }
                        .padding(.vertical, 8)
                }
            #endif
        }
    }

    private var raster: some View {
        TimelineGridView(quelle: quelle, zoom: $zoom, sprung: sprung,
                         auswahlModus: auswahlModus, auswahlStand: auswahlStand,
                         onAuswahl: { auswahl = $0 },
                         onTap: { section, index, rahmen in oeffne(DetailPosition(section: section, index: index), rahmen) },
                         onScroll: { [scroll] in scroll.anteil = $0 },
                         onMonat: { [scroll] in scroll.monat = $0 },
                         onEnde: { [scroll] in scroll.amEnde = $0 },
                         onDatum: { [scroll] in scroll.datum = $0 },
                         onLeiste: { zeigen in withAnimation(.easeOut(duration: 0.25)) { leisteSichtbar = zeigen } },
                         umgekehrt: umgekehrt)
    }

    /// Wie in Apples Fotos-App: Neuestes unten, nach oben scrollen für Älteres.
    /// Suchergebnisse bleiben von oben nach unten, weil sie nach Relevanz sortiert sind.
    private var umgekehrt: Bool {
        #if os(iOS)
        if case .suche = filter { return false }
        return true
        #else
        return false
        #endif
    }

    static func leerText(_ filter: TimelineFilter) -> (titel: String, text: String, symbol: String) {
        switch filter {
        case .alle: ("Noch keine Fotos", "Sobald Fotos auf deinem Immich-Server sind, erscheinen sie hier.", "photo.on.rectangle.angled")
        case .favoriten: ("Noch keine Favoriten", "Tippe bei einem Foto auf das Herz, dann findest du es hier wieder.", "heart")
        case .archiv: ("Archiv ist leer", "Archivierte Fotos verschwinden aus „Fotos“ und liegen hier.", "archivebox")
        case .papierkorb: ("Papierkorb ist leer", "Gelöschte Fotos liegen hier, bis der Server sie endgültig entfernt.", "trash")
        case .kuerzlich: ("Nichts Neues", "In den letzten 30 Tagen wurde nichts hochgeladen.", "clock.arrow.circlepath")
        case .person: ("Keine Fotos", "Immich hat diese Person noch auf keinem Foto erkannt.", "person.crop.circle")
        case .medienart(let art): ("Keine \(art.titel)", "In deiner Bibliothek gibt es davon noch nichts.", art.symbol)
        case .suche: ("Nichts gefunden", "Versuch es mit anderen Worten, zum Beispiel einem Ort, einem Tier oder einer Farbe.", "magnifyingglass")
        case .album: ("Album ist leer", "Wähle unter „Fotos“ Bilder aus und füge sie diesem Album hinzu.", "rectangle.stack")
        }
    }

    // MARK: - Werkzeuge

    @ToolbarContentBuilder
    private var werkzeuge: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if kannHochladen && !auswahlModus {
                #if os(iOS)
                PhotosPicker(selection: $fotoAuswahl, matching: .any(of: [.images, .videos]),
                             preferredItemEncoding: .current, photoLibrary: .shared()) {
                    Label("Hochladen", systemImage: "plus")
                }
                .accessibilityLabel(zielAlbum == nil ? "Fotos hochladen" : "Fotos in dieses Album hochladen")
                .tint(.primary)
                #else
                Button("Importieren …", systemImage: "plus") { zeigeImport = true }
                    .keyboardShortcut("i", modifiers: .command)
                    .help("Fotos und Videos hochladen (⌘I)")
                #endif
            }
            #if os(iOS)
            if kontext.client != nil, store?.zustand == .bereit {
                // „Auswählen“ steckt im Menü, damit die Leiste kompakt bleibt. „Fertig“ bleibt sichtbar.
                if auswahlModus {
                    Button("Fertig") { beendeAuswahl() }
                }
            }
            #endif
            if !auswahlModus {
            Menu {
                #if os(iOS)
                if kontext.client != nil, store?.zustand == .bereit {
                    Button("Auswählen", systemImage: "checkmark.circle") { auswahlModus = true }
                    Divider()
                }
                #endif
                #if os(iOS)
                if filter == .alle, kontext.backup?.aktiv == true {
                    Toggle("Nicht gesicherte zeigen", systemImage: "icloud.slash", isOn: $zeigeNichtGesicherte)
                    Divider()
                }
                #endif
                Button("Größer (weniger Spalten)", systemImage: "plus.magnifyingglass") { zoom.groesser() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Kleiner (mehr Spalten)", systemImage: "minus.magnifyingglass") { zoom.kleiner() }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Zum neuesten Monat", systemImage: "arrow.up.to.line") { sprung = SprungAnfrage(section: 0) }
                Button("Zum ältesten Monat", systemImage: "arrow.down.to.line") {
                    sprung = SprungAnfrage(section: max(quelle.sections.count - 1, 0))
                }
                if let store {
                    Divider()
                    Button("Neu laden", systemImage: "arrow.clockwise") { Task { await store.laden() } }
                        .keyboardShortcut("r", modifiers: .command)
                }
            } label: {
                Label("Ansicht", systemImage: "line.3.horizontal.decrease")
            }
            .tint(.primary)
            }
            if let konto, !auswahlModus {
                KontoKnopf(buchstabe: konto.buchstabe, backup: kontext.backup, client: kontext.client,
                           nutzerId: kontext.nutzerId, oeffnen: konto.oeffnen)
            }
        }
    }

    /// Leiste mit Aktionen für die ausgewählten Fotos.
    private var aktionsleiste: some View {
        HStack(spacing: 2) {
            if filter == .papierkorb {
                aktion("Wiederherstellen", "arrow.uturn.backward") { fuehreAus { try await $0.stelleWiederHer(assetIds: $1) } }
                aktion("Endgültig löschen", "trash.slash", rot: true, taste: KeyboardShortcut(.delete, modifiers: [])) { frageLoeschen = true }
            } else {
                if filter == .favoriten {
                    aktion("Favorit entfernen", "heart.slash", taste: KeyboardShortcut("f", modifiers: [])) { fuehreAus { try await $0.aendere(assetIds: $1, favorit: false) } }
                } else {
                    aktion("Favorit", "heart", taste: KeyboardShortcut("f", modifiers: [])) { fuehreAus { try await $0.aendere(assetIds: $1, favorit: true) } }
                }
                if filter == .archiv {
                    aktion("Aus Archiv holen", "arrow.uturn.backward") { fuehreAus { try await $0.aendere(assetIds: $1, archiviert: false) } }
                } else {
                    aktion("Archivieren", "archivebox") { fuehreAus { try await $0.aendere(assetIds: $1, archiviert: true) } }
                }
                aktion("Zu Album", "rectangle.stack.badge.plus") { zeigeAlbumWahl = true }
                aktion("Löschen", "trash", rot: true, taste: KeyboardShortcut(.delete, modifiers: [])) { frageLoeschen = true }
            }
            if arbeitet { ProgressView().padding(.horizontal, 10) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .lilithGlas(in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.bottom, 12)
        .disabled(arbeitet)
    }

    private func aktion(_ titel: String, _ symbol: String, rot: Bool = false, taste: KeyboardShortcut? = nil,
                        _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.body)
                Text(titel).font(.caption2)
            }
            .frame(minWidth: 62, minHeight: 44)
            .foregroundStyle(rot ? Color.red : LilithColor.text)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(taste)
        .help(taste.map { "\(titel) (\(Self.tastenText($0)))" } ?? titel)
    }

    static func tastenText(_ taste: KeyboardShortcut) -> String {
        let zeichen: String
        switch taste.key {
        case .delete: zeichen = "⌫"
        case .return: zeichen = "↩"
        default: zeichen = String(taste.key.character).uppercased()
        }
        return (taste.modifiers.contains(.command) ? "⌘" : "") + zeichen
    }

    // MARK: - Aktionen

    private var loeschtEndgueltig: Bool { filter == .papierkorb || !kontext.papierkorbAktiv }

    private var loeschFrage: String {
        let n = auswahl.count
        let was = n == 1 ? "1 Objekt" : "\(n) Objekte"
        return loeschtEndgueltig ? "\(was) endgültig löschen?" : "\(was) in den Papierkorb legen?"
    }

    private func oeffne(_ start: DetailPosition, _ rahmen: CGRect) {
        let k = kontext
        kontext.detail = DetailAnzeige(
            quelle: quelle, store: store, start: start, rahmen: rahmen,
            loeschen: kontext.client == nil || filter == .papierkorb ? nil : { await loescheEinzeln($0) },
            schliessen: { ende in
                // Das Grid dorthin mitnehmen, wo man beim Blättern gelandet ist.
                if ende.section != start.section { sprung = SprungAnfrage(section: ende.section) }
                k.detail = nil
            })
    }

    // MARK: - Hochladen

    /// Dateien (Mac: gezogen oder importiert) in die Warteschlange geben.
    private func ladeHoch(_ urls: [URL], quelle: String) {
        guard let uploads = kontext.uploads else { return }
        let album = zielAlbum
        Task {
            // Dateien aus „Importieren …“ sind nur mit ausdrücklicher Freigabe lesbar.
            let freigegeben = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { freigegeben.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                let anzahl = try await uploads.fuegeHinzu(urls, quelle: quelle, albumId: album)
                if anzahl == 0 { fehler = "Darunter waren keine Fotos oder Videos." }
            } catch {
                fehler = error.localizedDescription
            }
        }
    }

    /// Fotos aus Apples Foto-Auswahl: als Original-Datei holen und hochladen.
    private func ladeHochAusAuswahl(_ eintraege: [PhotosPickerItem]) {
        guard let uploads = kontext.uploads else { return }
        let album = zielAlbum
        Task {
            var dateien: [URL] = []
            var fehlgeschlagen = 0
            for eintrag in eintraege {
                if let datei = try? await eintrag.loadTransferable(type: AuswahlDatei.self) {
                    dateien.append(datei.url)
                } else {
                    fehlgeschlagen += 1
                }
            }
            do {
                try await uploads.fuegeHinzu(dateien, quelle: "auswahl", albumId: album)
            } catch {
                fehler = error.localizedDescription
            }
            // Die Zwischenkopien der Auswahl werden nicht mehr gebraucht (die Warteschlange hat eigene).
            for datei in dateien { try? FileManager.default.removeItem(at: datei.deletingLastPathComponent()) }
            if fehlgeschlagen > 0 {
                fehler = fehlgeschlagen == 1 ? "Ein Objekt konnte nicht geladen werden (vielleicht liegt es nur in iCloud)."
                                             : "\(fehlgeschlagen) Objekte konnten nicht geladen werden (vielleicht liegen sie nur in iCloud)."
            }
        }
    }

    private func beendeAuswahl() {
        auswahlModus = false
        auswahl = []
        auswahlStand += 1
    }

    /// Führt eine Aktion für die ausgewählten Fotos aus und lädt danach neu.
    private func fuehreAus(_ aktion: @escaping (ImmichClient, [String]) async throws -> Void) {
        guard let client = kontext.client, !auswahl.isEmpty, !arbeitet else { return }
        let ids = auswahl
        arbeitet = true
        Task {
            defer { arbeitet = false }
            do {
                try await aktion(client, ids)
                beendeAuswahl()
                await store?.laden()
                kontext.melde(von: store)
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
        }
    }

    /// Löschen aus der Detailansicht. Gibt zurück, ob es geklappt hat.
    private func loescheEinzeln(_ id: String) async -> Bool {
        guard let client = kontext.client else { return false }
        do {
            try await client.loesche(assetIds: [id], endgueltig: !kontext.papierkorbAktiv)
            await store?.laden()
            kontext.melde(von: store)
            return true
        } catch {
            fehler = error.localizedDescription
            kontext.pruefe(error)
            return false
        }
    }
}

/// Schmaler Hinweis oben, wenn der Server gerade nicht antwortet. Die geladenen Fotos bleiben sichtbar.
struct OfflineHinweis: View {
    let text: String
    let erneut: () -> Void
    @State private var zeigeDetails = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Server nicht erreichbar").font(.subheadline.weight(.semibold))
                Text(zeigeDetails ? text : "Du siehst die zuletzt geladenen Fotos.")
                    .font(.caption)
                    .foregroundStyle(LilithColor.textLeise)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onTapGesture { zeigeDetails.toggle() }
            Spacer(minLength: 8)
            Button("Erneut", action: erneut)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .lilithGlas(in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Scroll-Position der Timeline (0…1). Nur der Scrubber liest sie.
@MainActor
@Observable
final class ScrollStand {
    var anteil = 0.0
    /// Monat, der gerade oben unter der Leiste steht.
    var monat = 0
    /// Ganz unten bei den neuesten Fotos: dann zeigt das Etikett die Anzahl statt des Monats.
    var amEnde = false
    /// Aufnahmedatum des Fotos, das gerade am Rand steht.
    var datum: Date?
}

/// Monats-Etikett aus Glas: welcher Monat gerade oben steht, mit Ort und Anzahl.
/// Ersetzt die grauen Monats-Bänder im Raster.
private struct MonatsEtikett: View {
    let quelle: TimelineQuelle
    let scroll: ScrollStand
    /// Im Auswahl-Modus steht hier die Anzahl statt des Monats.
    var auswahlText: String?

    var body: some View {
        if let auswahlText {
            Text(auswahlText)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .lilithGlas(in: .capsule)
        } else if scroll.amEnde {
            // Wie in Apples Fotos-App: ganz unten steht, wie viele Objekte es sind.
            let gesamt = quelle.sections.reduce(0) { $0 + $1.anzahl }
            Text("\(gesamt.formatted()) Objekte")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 16)
                .frame(height: 44)
                .lilithGlas(in: .capsule)
        } else if scroll.monat < quelle.sections.count {
            // Zwei getrennte Pillen auf derselben Höhe: links nur das Datum (Tag, Monat, Jahr),
            // rechts die Leiste. Gleiche Höhe (44 pt), gleiche Oberkante.
            Text(scroll.datum.map { $0.formatted(.dateTime.day().month(.wide).year()) }
                 ?? quelle.sections[scroll.monat].titel)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .lilithGlas(in: .capsule)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: scroll.datum)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Liest die Scroll-Position selbst, damit Änderungen nur diese kleine Ansicht neu zeichnen.
private struct ScrubberMitStand: View {
    let quelle: TimelineQuelle
    let scroll: ScrollStand
    var umgekehrt = false
    let springe: (Int) -> Void

    var body: some View {
        Scrubber(quelle: quelle, anteil: scroll.anteil, umgekehrt: umgekehrt, springe: springe)
    }
}

#if os(iOS)
/// Blendet den Titel der Leiste aus, wenn er stattdessen groß über den Fotos steht.
private struct TitelAusblenden: ViewModifier {
    let aktiv: Bool
    func body(content: Content) -> some View {
        if aktiv { content.toolbar(removing: .title) } else { content }
    }
}
#endif
