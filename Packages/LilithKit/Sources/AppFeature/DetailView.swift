import CoreTransferable
import MapKit
import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
import Networking
import TimelineGrid

/// Detailansicht: ein Foto groß, mit Blättern, Zoom, Info, Favorit und Teilen.
struct DetailView: View {
    let quelle: TimelineQuelle
    let store: TimelineStore?
    /// Löscht das Foto mit dieser ID. `nil`, wenn Löschen hier nicht angeboten wird.
    let loeschen: ((String) async -> Bool)?
    let schliessen: (DetailPosition) -> Void

    @State private var seiten: [DetailPosition]
    @State private var aktuell: DetailPosition?
    @State private var item: Kachel?
    @State private var info: AssetInfo?
    @State private var zeigeInfo = false
    @State private var zeigeBedienung = true
    @State private var gezoomt = false
    @State private var zug: CGFloat = 0
    @State private var zugAktiv = false
    @State private var fehler: String?
    /// Kurze Bestätigung, z. B. „Titelbild gesetzt“.
    @State private var meldung: String?
    @State private var frageLoeschen = false
    @State private var loescht = false
    @FocusState private var fokus: Bool
    @Environment(BibliothekKontext.self) private var kontext

    init(quelle: TimelineQuelle, store: TimelineStore?, start: DetailPosition,
         loeschen: ((String) async -> Bool)? = nil, schliessen: @escaping (DetailPosition) -> Void) {
        self.quelle = quelle
        self.store = store
        self.loeschen = loeschen
        self.schliessen = schliessen
        _seiten = State(initialValue: Self.fenster(um: start, quelle: quelle))
        _aktuell = State(initialValue: start)
        _item = State(initialValue: quelle.item(section: start.section, index: start.index))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(zug / 400, 0.7)).ignoresSafeArea()
            blaetterer
                .offset(y: zug)
                .scaleEffect(1 - min(zug / 1500, 0.2))
            if zeigeBedienung && !zugAktiv {
                bedienung.transition(.opacity)
            }
            if let meldung {
                Label(meldung, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .lilithGlas(in: .capsule, klar: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 120)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        // Obere und untere Leiste blenden immer weich ein und aus, auch beim Wegziehen.
        .animation(.smooth(duration: 0.3), value: zeigeBedienung && !zugAktiv)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($fokus)
        .onAppear { fokus = true }
        .onKeyPress(.escape) { schliesse(); return .handled }
        .onKeyPress(.leftArrow) { blaettere(-1); return .handled }
        .onKeyPress(.rightArrow) { blaettere(1); return .handled }
        .onChange(of: aktuell) { _, neu in
            guard let neu else { return }
            item = quelle.item(section: neu.section, index: neu.index)
            info = nil
            gezoomt = false
            fensterNachziehen(um: neu)
        }
        .task(id: aktuell) {
            // Kurz warten, damit beim schnellen Blättern nicht für jedes Foto Infos geladen werden.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let aktuell else { return }
            while item == nil, !Task.isCancelled {
                item = quelle.item(section: aktuell.section, index: aktuell.index)
                if item == nil { try? await Task.sleep(for: .milliseconds(150)) }
            }
            guard let id = item?.id, item?.lokal == nil, let client = store?.client else { return }
            info = try? await client.assetInfo(id: id)
        }
        .sheet(isPresented: $zeigeInfo) {
            InfoPanel(info: info, monat: aktuell.map { quelle.sections[$0.section].titel } ?? "")
                .presentationDetents([.medium, .large])
        }
        .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
            Button("OK") { fehler = nil }
        } message: { text in
            Text(text)
        }
    }

    // MARK: - Blättern

    private var blaetterer: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(seiten, id: \.self) { position in
                    DetailSeite(position: position, quelle: quelle, store: store, istAktuell: position == aktuell,
                                gezoomt: $gezoomt, zeigeBedienung: zeigeBedienung && !zugAktiv,
                                verberge: { withAnimation(.smooth(duration: 0.45)) { zeigeBedienung = false } }) {
                        withAnimation(.smooth(duration: 0.3)) { zeigeBedienung.toggle() }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        // Jede Seite füllt den ganzen Bildschirm, ohne zusätzliche Ränder.
        .contentMargins(.all, 0, for: .scrollContent)
        .scrollPosition(id: $aktuell)
        .scrollIndicators(.hidden)
        .scrollDisabled(gezoomt)
        .ignoresSafeArea()
        .simultaneousGesture(gezoomt ? nil : zumSchliessenZiehen)
    }

    /// Nach unten ziehen schließt die Ansicht.
    private var zumSchliessenZiehen: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { wert in
                if !zugAktiv {
                    // Starten, sobald die Bewegung eher nach unten als zur Seite geht (sonst ist es Blättern).
                    guard wert.translation.height > abs(wert.translation.width) else { return }
                    zugAktiv = true
                }
                // Folgt dem Finger direkt, ohne Widerstand.
                zug = max(0, wert.translation.height)
            }
            .onEnded { wert in
                guard zugAktiv else { return }
                // Schon ein kurzer Zug mit etwas Schwung schließt.
                if zug > 80 || wert.predictedEndTranslation.height > 220 {
                    schliesse()
                } else {
                    withAnimation(.smooth(duration: 0.3)) { zug = 0 }
                    zugAktiv = false
                }
            }
    }

    private func schliesse() {
        schliessen(aktuell ?? seiten.first ?? DetailPosition(section: 0, index: 0))
    }

    private func blaettere(_ schritt: Int) {
        guard !gezoomt, let aktuell, let i = seiten.firstIndex(of: aktuell), seiten.indices.contains(i + schritt) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { self.aktuell = seiten[i + schritt] }
    }

    /// Hält rund um das aktuelle Foto genug Seiten bereit, ohne je alle 100.000 anzulegen.
    private func fensterNachziehen(um position: DetailPosition) {
        guard let i = seiten.firstIndex(of: position) else { return }
        let amAnfang = i < 4 && Self.davor(seiten[0], quelle: quelle) != nil
        let amEnde = i > seiten.count - 5 && Self.danach(seiten[seiten.count - 1], quelle: quelle) != nil
        guard amAnfang || amEnde else { return }
        seiten = Self.fenster(um: position, quelle: quelle)
        aktuell = position
    }

    static func fenster(um mitte: DetailPosition, quelle: TimelineQuelle, radius: Int = 40) -> [DetailPosition] {
        var vorher: [DetailPosition] = []
        var p = mitte
        while vorher.count < radius, let v = davor(p, quelle: quelle) { vorher.append(v); p = v }
        var nachher: [DetailPosition] = []
        p = mitte
        while nachher.count < radius, let n = danach(p, quelle: quelle) { nachher.append(n); p = n }
        return vorher.reversed() + [mitte] + nachher
    }

    static func davor(_ p: DetailPosition, quelle: TimelineQuelle) -> DetailPosition? {
        if p.index > 0 { return DetailPosition(section: p.section, index: p.index - 1) }
        var s = p.section - 1
        while s >= 0 {
            if quelle.sections[s].anzahl > 0 { return DetailPosition(section: s, index: quelle.sections[s].anzahl - 1) }
            s -= 1
        }
        return nil
    }

    static func danach(_ p: DetailPosition, quelle: TimelineQuelle) -> DetailPosition? {
        if p.index + 1 < quelle.sections[p.section].anzahl { return DetailPosition(section: p.section, index: p.index + 1) }
        var s = p.section + 1
        while s < quelle.sections.count {
            if quelle.sections[s].anzahl > 0 { return DetailPosition(section: s, index: 0) }
            s += 1
        }
        return nil
    }

    // MARK: - Bedienelemente

    private var bedienung: some View {
        VStack {
            HStack(alignment: .center) {
                Button(action: schliesse) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }
                .lilithGlas(in: .circle, klar: true)
                .accessibilityLabel("Zurück")
                .keyboardShortcut(.cancelAction)
                Spacer()
                VStack(spacing: 1) {
                    Text(titel).font(.subheadline.weight(.semibold))
                    if let untertitel { Text(untertitel).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .lilithGlas(in: .capsule, klar: true)
                .accessibilityElement(children: .combine)
                Spacer()
                #if os(iOS)
                if item?.art == .video {
                    // AirPlay oben rechts, gegenüber von „Zurück“.
                    AirPlayKnopf()
                        .frame(width: 44, height: 44)
                        .lilithGlas(in: .circle, klar: true)
                        .accessibilityLabel("AirPlay")
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                #else
                Color.clear.frame(width: 44, height: 44)
                #endif
            }
            .padding(.horizontal, 16)
            Spacer()
            if let lokal = item?.lokal {
                lokaleLeiste(lokal)
            } else {
                serverLeiste
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .sensoryFeedback(.impact(weight: .light), trigger: item?.favorit)
    }

    /// Für Fotos nur auf dem Gerät: Stand und „Jetzt sichern“ statt Favorit, Teilen und Löschen.
    private func lokaleLeiste(_ lokal: GridLokal) -> some View {
        HStack(spacing: 12) {
            Label(lokal == .laedtHoch ? "Wird hochgeladen …" : (lokal == .fehler ? "Hochladen gescheitert" : "Nur auf diesem Gerät"),
                  systemImage: lokal == .laedtHoch ? "arrow.up.circle" : (lokal == .fehler ? "exclamationmark.circle" : "icloud.slash"))
                .font(.subheadline)
            if lokal != .laedtHoch, let id = item?.lokaleId, let backup = kontext.backup {
                Button("Jetzt sichern") {
                    backup.sichereJetzt(id)
                    if let alt = item {
                        item = Kachel(id: alt.id, farbe: alt.farbe, art: alt.art, favorit: false, dauer: alt.dauer, lokal: .laedtHoch)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(LilithColor.nachtroseFill, in: .capsule)
                .foregroundStyle(.white)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .lilithGlas(in: .capsule, klar: true)
        .padding(.bottom, 12)
    }

    private var serverLeiste: some View {
            HStack(spacing: 4) {
                teilenKnopf
                Button {
                    wechsleFavorit()
                } label: {
                    Image(systemName: item?.favorit == true ? "heart.fill" : "heart")
                        .foregroundStyle(item?.favorit == true ? LilithColor.nachtrose : .primary)
                        .frame(width: 52, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(item?.favorit == true ? "Favorit entfernen" : "Als Favorit markieren")
                .keyboardShortcut("f", modifiers: [])
                .disabled(item == nil || store == nil)
                Button {
                    zeigeInfo = true
                } label: {
                    Image(systemName: "info.circle").frame(width: 52, height: 44)
                }
                .accessibilityLabel("Informationen")
                .keyboardShortcut("i", modifiers: .command)
                titelbildMenue
                if loeschen != nil {
                    Button {
                        frageLoeschen = true
                    } label: {
                        Image(systemName: "trash").frame(width: 52, height: 44)
                    }
                    .accessibilityLabel("Löschen")
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(item == nil || loescht)
                    .confirmationDialog("Dieses Objekt löschen?", isPresented: $frageLoeschen, titleVisibility: .visible) {
                        Button("Löschen", role: .destructive) { loesche() }
                    }
                }
            }
            .font(.title3)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .lilithGlas(in: .capsule, klar: true)
            .padding(.bottom, 12)
    }

    /// Im Album oder bei einer Person: dieses Foto als Titelbild verwenden.
    @ViewBuilder
    private var titelbildMenue: some View {
        if let item, item.lokal == nil, let client = store?.client {
            switch store?.filter {
            case .album(let album):
                Button {
                    setzeTitelbild { try await client.setzeAlbumTitelbild(album: album, foto: item.id) }
                } label: {
                    Image(systemName: "photo.badge.checkmark").frame(width: 52, height: 44)
                }
                .accessibilityLabel("Als Albumtitelbild verwenden")
            case .person(let person):
                Button {
                    setzeTitelbild {
                        try await client.setzePersonBild(person: person, foto: item.id)
                        BilderCache.vergiss(client.personBildAnfrage(person))
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.checkmark").frame(width: 52, height: 44)
                }
                .accessibilityLabel("Als Bild für diese Person verwenden")
            default:
                EmptyView()
            }
        }
    }

    private func setzeTitelbild(_ tun: @escaping () async throws -> Void) {
        Task {
            do {
                try await tun()
                kontext.melde(von: nil)
                withAnimation(.smooth) { meldung = "Titelbild gesetzt" }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.smooth) { meldung = nil }
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
        }
    }

    @ViewBuilder
    private var teilenKnopf: some View {
        let symbol = Image(systemName: "square.and.arrow.up").frame(width: 52, height: 44)
        if let item, let client = store?.client {
            let name = info?.dateiname
            #if os(iOS)
            // Das Teilen-Menü öffnet sofort, das Original lädt erst, wenn ein Ziel es braucht.
            Button { TeilenBlatt.zeige(client: client, assetId: item.id, dateiname: name, istVideo: item.art == .video) } label: { symbol }
                .accessibilityLabel("Teilen")
            #else
            if item.art == .video {
                ShareLink(item: VideoDatei(client: client, assetId: item.id, dateiname: name),
                          preview: SharePreview(name ?? "Video")) { symbol }
                    .accessibilityLabel("Teilen")
            } else {
                ShareLink(item: FotoDatei(client: client, assetId: item.id, dateiname: name),
                          preview: SharePreview(name ?? "Foto")) { symbol }
                    .accessibilityLabel("Teilen")
            }
            #endif
        } else {
            symbol.opacity(0.4).accessibilityHidden(true)
        }
    }

    private var titel: String {
        if let info { return InfoPanel.datum(info.aufgenommenLokal) }
        return aktuell.map { quelle.sections[$0.section].titel } ?? ""
    }

    private var untertitel: String? {
        guard let info else { return nil }
        let zeit = InfoPanel.uhrzeit(info.aufgenommenLokal)
        return info.ort.map { "\($0.split(separator: ",").first.map(String.init) ?? $0) · \(zeit)" } ?? zeit
    }

    private func loesche() {
        guard let id = item?.id, let loeschen, !loescht else { return }
        loescht = true
        Task {
            if await loeschen(id) {
                schliesse()
            }
            loescht = false
        }
    }

    private func wechsleFavorit() {
        guard let aktuell, let alt = item, let store else { return }
        item = alt.mit(favorit: !alt.favorit)
        Task {
            do {
                try await store.setzeFavorit(section: aktuell.section, index: aktuell.index, !alt.favorit)
            } catch {
                if item?.id == alt.id { item = alt }
                fehler = error.localizedDescription
            }
        }
    }
}

// MARK: - Teilen

/// Lädt die Originaldatei erst, wenn wirklich geteilt wird.
private func originalDatei(_ client: ImmichClient, _ assetId: String, _ dateiname: String?) async throws -> SentTransferredFile {
    var name = dateiname
    if name == nil { name = try? await client.assetInfo(id: assetId).dateiname }
    return SentTransferredFile(try await client.ladeOriginal(assetId: assetId, dateiname: name ?? assetId))
}

#if os(iOS)
/// Reicht Rückruf und Fortschritt an die Lade-Aufgabe weiter (beide sind threadsicher gedacht).
private final class Uebergabe: @unchecked Sendable {
    let fertig: (URL?, Bool, (any Error)?) -> Void
    let fortschritt: Progress
    init(fertig: @escaping (URL?, Bool, (any Error)?) -> Void, fortschritt: Progress) {
        self.fertig = fertig; self.fortschritt = fortschritt
    }
}

/// Teilen-Menü ohne Warten: `NSItemProvider` lädt das Original erst, wenn ein Ziel gewählt ist,
/// und iOS zeigt dabei selbst den Fortschritt.
@MainActor
enum TeilenBlatt {
    static func zeige(client: ImmichClient, assetId: String, dateiname: String?, istVideo: Bool) {
        let typ: UTType = istVideo ? .movie : .image
        let anbieter = NSItemProvider()
        anbieter.suggestedName = dateiname
        anbieter.registerFileRepresentation(for: typ, visibility: .all, openInPlace: false) { fertig in
            let fortschritt = Progress(totalUnitCount: 1)
            let uebergabe = Uebergabe(fertig: fertig, fortschritt: fortschritt)
            Task.detached {
                do {
                    let datei = try await originalDatei(client, assetId, dateiname).file
                    uebergabe.fortschritt.completedUnitCount = 1
                    uebergabe.fertig(datei, false, nil)
                } catch {
                    uebergabe.fertig(nil, false, error)
                }
            }
            return fortschritt
        }
        let blatt = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [anbieter]))
        guard let szene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let fenster = szene.keyWindow, var oben = fenster.rootViewController else { return }
        while let weiter = oben.presentedViewController { oben = weiter }
        // iPad: als Popover unten mittig, wo der Knopf sitzt.
        blatt.popoverPresentationController?.sourceView = fenster
        blatt.popoverPresentationController?.sourceRect = CGRect(x: fenster.bounds.midX, y: fenster.bounds.maxY - 60, width: 1, height: 1)
        oben.present(blatt, animated: true)
    }
}
#endif

struct FotoDatei: Transferable {
    let client: ImmichClient
    let assetId: String
    let dateiname: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .image) { try await originalDatei($0.client, $0.assetId, $0.dateiname) }
    }
}

struct VideoDatei: Transferable {
    let client: ImmichClient
    let assetId: String
    let dateiname: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .movie) { try await originalDatei($0.client, $0.assetId, $0.dateiname) }
    }
}

// MARK: - Info-Panel

/// Angaben zum Foto: Datum, Kamera, Datei, Karte, Personen.
struct InfoPanel: View {
    let info: AssetInfo?
    let monat: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let info {
                    inhalt(info)
                } else {
                    ProgressView("Infos werden geladen …").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Informationen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private func inhalt(_ info: AssetInfo) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.datum(info.aufgenommenLokal, mitWochentag: true))
                        .font(.title3.weight(.semibold))
                    Text("\(Self.uhrzeit(info.aufgenommenLokal)) Uhr · \(info.dateiname)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let text = info.beschreibung { Text(text) }
            }

            if info.kamera != nil || info.objektiv != nil || !Self.aufnahme(info).isEmpty {
                Section("Kamera") {
                    if let kamera = info.kamera { LabeledContent("Kamera", value: kamera) }
                    if let objektiv = info.objektiv { LabeledContent("Objektiv", value: objektiv) }
                    let werte = Self.aufnahme(info)
                    if !werte.isEmpty { LabeledContent("Aufnahme", value: werte) }
                }
            }

            Section("Datei") {
                if let b = info.breite, let h = info.hoehe, b > 0, h > 0 {
                    LabeledContent("Größe", value: "\(b) × \(h) · \(Self.megapixel(b, h))")
                }
                if let bytes = info.dateigroesse {
                    LabeledContent("Dateigröße", value: Int64(bytes).formatted(.byteCount(style: .file)))
                }
                LabeledContent("Art", value: info.istVideo ? "Video" : (info.livePhotoVideoId != nil ? "Live Photo" : "Foto"))
            }

            if let lat = info.latitude, let lon = info.longitude {
                let ort = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                Section("Ort") {
                    Map(initialPosition: .region(MKCoordinateRegion(center: ort, latitudinalMeters: 1500, longitudinalMeters: 1500)),
                        interactionModes: []) {
                        Marker(info.ort ?? "Aufnahmeort", coordinate: ort).tint(LilithColor.nachtroseFill)
                    }
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Karte: \(info.ort ?? "Aufnahmeort")")
                    if let name = info.ort { Text(name) }
                }
            } else if let name = info.ort {
                Section("Ort") { Text(name) }
            }

            if !info.personen.isEmpty {
                Section("Personen") { Text(info.personen.joined(separator: ", ")) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Formatierung

    /// Die Aufnahmezeit liegt als Ortszeit der Aufnahme vor, deshalb ohne Umrechnung in die eigene Zeitzone.
    private static var stil: Date.FormatStyle {
        var s = Date.FormatStyle(locale: Locale(identifier: "de_DE"))
        s.timeZone = .gmt
        return s
    }

    static func datum(_ d: Date, mitWochentag: Bool = false) -> String {
        mitWochentag ? d.formatted(stil.weekday(.wide).day().month(.wide).year())
                     : d.formatted(stil.day().month(.wide).year())
    }

    static func uhrzeit(_ d: Date) -> String {
        d.formatted(stil.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func megapixel(_ breite: Int, _ hoehe: Int) -> String {
        let mp = Double(breite * hoehe) / 1_000_000
        return "\(mp.formatted(.number.precision(.fractionLength(mp < 10 ? 1 : 0)).locale(Locale(identifier: "de_DE")))) MP"
    }

    /// „24 mm · ƒ1,8 · 1/120 s · ISO 80“
    static func aufnahme(_ info: AssetInfo) -> String {
        let de = Locale(identifier: "de_DE")
        var teile: [String] = []
        if let b = info.brennweite, b > 0 { teile.append("\(b.formatted(.number.precision(.fractionLength(0...1)).locale(de))) mm") }
        if let f = info.blende, f > 0 { teile.append("ƒ\(f.formatted(.number.precision(.fractionLength(0...1)).locale(de)))") }
        if let t = info.belichtung { teile.append("\(t) s") }
        if let iso = info.iso, iso > 0 { teile.append("ISO \(iso)") }
        return teile.joined(separator: " · ")
    }
}
