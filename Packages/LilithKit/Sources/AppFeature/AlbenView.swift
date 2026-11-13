import MapKit
import SwiftUI
import DesignSystem
import Networking
import TimelineGrid

/// Ziel einer Navigation: eine gefilterte Timeline mit Titel.
struct TimelineZiel: Hashable {
    let titel: String
    let filter: TimelineFilter
}

/// Weitere Ziele aus den Sammlungen (außer gefilterten Timelines).
enum SammlungsZiel: Hashable {
    /// Alle eigenen bzw. alle geteilten Alben als Raster.
    case alben(geteilt: Bool)
    /// Alle erkannten Personen.
    case personen
    /// Karte mit allen Orten.
    case orte
    /// Gruppen doppelter Fotos.
    case duplikate
    /// Ordner auf dem Server (`""` = oberste Ebene).
    case ordner(String)
}

/// Der Tab „Sammlungen“, aufgebaut wie in Apples Fotos-App: eine lange Seite mit Abschnitten,
/// jeweils eine Überschrift mit „›“ und darunter eine Reihe zum seitlich Wischen oder eine kurze Liste.
struct AlbenView: View {
    @Environment(BibliothekKontext.self) private var kontext
    @State private var alben: [Album] = []
    @State private var tage: [HochladeTag] = []
    @State private var personen: [Person] = []
    @State private var orte: [Ort] = []
    /// Wann zuletzt vom Server geladen (und bei welchem Stand): kein erneutes Laden bei jedem Öffnen des Tabs.
    @State private var zuletzt: (stand: Int, zeit: Date)?
    @State private var geladen = false
    @State private var fehler: String?
    @State private var neuesAlbum = false
    @State private var neuerName = ""

    private var eigene: [Album] { alben.filter { !$0.geteilt } }
    private var geteilte: [Album] { alben.filter(\.geteilt) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if kontext.client == nil {
                        Text("Sammlungen gibt es nur mit einer Verbindung zum Server.")
                            .foregroundStyle(LilithColor.textLeise)
                            .padding(.horizontal, 16)
                    } else if !geladen {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        if !tage.isEmpty { kuerzlich }
                        albenReihe(titel: "Alben", liste: eigene, geteilt: false)
                        if !geteilte.isEmpty { albenReihe(titel: "Geteilte Alben", liste: geteilte, geteilt: true) }
                        if !personenReihe.isEmpty { personenAbschnitt }
                        if !orte.isEmpty { orteAbschnitt }
                        medienarten
                        weitere
                    }
                }
                .padding(.vertical, 12)
            }
            .background(LilithColor.hintergrund)
            .navigationTitle("Sammlungen")
            .toolbar {
                if kontext.client != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Neues Album", systemImage: "plus") { neuerName = ""; neuesAlbum = true }
                            .tint(.primary)
                    }
                }
            }
            .navigationDestination(for: TimelineZiel.self) { ziel in
                GefilterteTimeline(ziel: ziel)
            }
            .navigationDestination(for: SammlungsZiel.self) { ziel in
                switch ziel {
                case .alben(let geteilt):
                    AlbenRaster(titel: geteilt ? "Geteilte Alben" : "Alben", alben: geteilt ? geteilte : eigene)
                case .personen:
                    PersonenRaster(personen: personen)
                case .orte:
                    OrteKarte(orte: orte)
                case .duplikate:
                    DuplikateView()
                case .ordner(let pfad):
                    OrdnerView(pfad: pfad)
                }
            }
            .refreshable { await lade(erzwingen: true) }
            .task(id: kontext.stand) { await lade() }
            .alert("Neues Album", isPresented: $neuesAlbum) {
                TextField("Name", text: $neuerName)
                Button("Abbrechen", role: .cancel) {}
                Button("Anlegen") { erstelle() }
            }
            .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
                Button("OK") { fehler = nil }
            } message: { Text($0) }
        }
    }

    // MARK: - Abschnitte

    /// Große Karten je Tag, an dem Fotos auf den Server kamen.
    private var kuerzlich: some View {
        VStack(alignment: .leading, spacing: 10) {
            Ueberschrift(titel: "Kürzlich hinzugefügt", ziel: TimelineZiel(titel: "Kürzlich hinzugefügt", filter: .kuerzlich))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(tage) { tag in
                        NavigationLink(value: TimelineZiel(titel: "Kürzlich hinzugefügt", filter: .kuerzlich)) {
                            VStack(alignment: .leading, spacing: 2) {
                                VorschauBild(client: kontext.client, assetId: tag.titelBildId, groesse: .preview)
                                    .frame(width: 260, height: 180)
                                    .clipShape(.rect(cornerRadius: 12))
                                Text(Self.tagName(tag.tag)).font(LilithFont.karte).foregroundStyle(LilithColor.text)
                                    .padding(.top, 6)
                                Text(tag.anzahl == 1 ? "1 Objekt" : "\(tag.anzahl.formatted()) Objekte")
                                    .font(.caption).foregroundStyle(LilithColor.textLeise)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// Alben als Reihe zum seitlich Wischen.
    @ViewBuilder
    private func albenReihe(titel: String, liste: [Album], geteilt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Ueberschrift(titel: titel, sammlung: .alben(geteilt: geteilt))
            if liste.isEmpty {
                Text("Noch keine Alben. Lege mit dem Plus oben eins an.")
                    .foregroundStyle(LilithColor.textLeise)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(liste) { album in
                            NavigationLink(value: TimelineZiel(titel: album.name, filter: .album(album.id))) {
                                AlbumKarte(album: album, client: kontext.client, zeigeGeteilt: false)
                                    .frame(width: 168)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    /// Benannte Personen zuerst. Hat noch niemand einen Namen, die ersten Gesichter.
    private var personenReihe: [Person] {
        let benannt = personen.filter { !$0.name.isEmpty }
        return Array((benannt.isEmpty ? personen : benannt).prefix(20))
    }

    private var personenAbschnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Ueberschrift(titel: "Personen", sammlung: .personen)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(personenReihe) { person in
                        NavigationLink(value: TimelineZiel(titel: person.name.isEmpty ? "Person" : person.name,
                                                           filter: .person(person.id))) {
                            PersonKarte(person: person, client: kontext.client, kante: 84)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// Kleine Karte mit den Orten, darunter die Städte mit den meisten Fotos.
    private var orteAbschnitt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Ueberschrift(titel: "Orte", sammlung: .orte)
            NavigationLink(value: SammlungsZiel.orte) {
                OrteVorschauKarte(orte: orte)
                    .frame(height: 190)
                    // Die Karte selbst nimmt keine Tipps an: Eine durchsichtige Fläche darüber öffnet die große Karte.
                    .overlay { Color.white.opacity(0.001) }
                    .clipShape(.rect(cornerRadius: 14))
                    .contentShape(.rect(cornerRadius: 14))
                    .overlay(alignment: .bottomLeading) {
                        Text(orte.count == 1 ? "1 Ort" : "\(orte.count.formatted()) Orte")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .lilithGlas(in: .capsule)
                            .padding(10)
                    }
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Karte mit \(orte.count) Orten")
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(orte.prefix(20)) { ort in
                        NavigationLink(value: TimelineZiel(titel: ort.stadt, filter: .ort(stadt: ort.stadt, land: ort.land))) {
                            VStack(alignment: .leading, spacing: 2) {
                                VorschauBild(client: kontext.client, assetId: ort.titelBildId)
                                    .frame(width: 140, height: 140)
                                    .clipShape(.rect(cornerRadius: 12))
                                Text(ort.stadt).font(LilithFont.karte).foregroundStyle(LilithColor.text).lineLimit(1)
                                    .padding(.top, 6)
                                Text(ort.anzahl == 1 ? "1 Objekt" : "\(ort.anzahl.formatted()) Objekte")
                                    .font(.caption).foregroundStyle(LilithColor.textLeise)
                            }
                            .frame(width: 140, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var medienarten: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medienarten").font(.title2.bold()).padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(Medienart.allCases.enumerated()), id: \.element) { i, art in
                    if i > 0 { Divider().padding(.leading, 52) }
                    listenEintrag(art.titel, art.symbol, .medienart(art))
                }
            }
            .background(LilithColor.flaeche, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    /// Weitere Sammlungen als Liste wie in den Einstellungen.
    private var weitere: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weitere").font(.title2.bold()).padding(.horizontal, 16)
            VStack(spacing: 0) {
                listenEintrag("Favoriten", "heart", .favoriten)
                Divider().padding(.leading, 52)
                sammlungsEintrag("Doppelte Fotos", "square.on.square", .duplikate)
                Divider().padding(.leading, 52)
                sammlungsEintrag("Ordner", "folder", .ordner(""))
                Divider().padding(.leading, 52)
                listenEintrag("Archiv", "archivebox", .archiv)
                if kontext.papierkorbAktiv {
                    Divider().padding(.leading, 52)
                    listenEintrag("Papierkorb", "trash", .papierkorb)
                }
            }
            .background(LilithColor.flaeche, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    private func listenEintrag(_ titel: String, _ symbol: String, _ filter: TimelineFilter) -> some View {
        listenZeile(titel, symbol, TimelineZiel(titel: titel, filter: filter))
    }

    private func sammlungsEintrag(_ titel: String, _ symbol: String, _ ziel: SammlungsZiel) -> some View {
        listenZeile(titel, symbol, ziel)
    }

    private func listenZeile<Z: Hashable>(_ titel: String, _ symbol: String, _ ziel: Z) -> some View {
        NavigationLink(value: ziel) {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 24)
                Text(titel).foregroundStyle(LilithColor.text)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LilithColor.textLeise)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    static func tagName(_ tag: Date) -> String {
        let k = Calendar.current
        if k.isDateInToday(tag) { return "Heute" }
        if k.isDateInYesterday(tag) { return "Gestern" }
        return tag.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    // MARK: - Laden

    private func lade(erzwingen: Bool = false) async {
        guard let client = kontext.client else { return }
        // Sofort zeigen, was gespeichert ist.
        if !geladen, let s = await SammlungenSpeicher.lies(client.address) {
            alben = s.alben; tage = s.tage; personen = s.personen; orte = s.orte
            geladen = true
        }
        // Gerade erst geladen und nichts geändert: nicht schon wieder.
        if !erzwingen, let z = zuletzt, z.stand == kontext.stand, Date.now.timeIntervalSince(z.zeit) < 120 { return }
        do {
            async let a = client.alben()
            async let t = client.kuerzlichNachTagen()
            async let p = client.personen()
            async let o = client.orte()
            alben = try await a
            tage = (try? await t) ?? []
            personen = (try? await p) ?? []
            orte = (try? await o) ?? []
            geladen = true
            zuletzt = (kontext.stand, .now)
            SammlungenSpeicher.schreibe(SammlungenDaten(alben: alben, tage: tage, personen: personen, orte: orte),
                                        client.address)
        } catch {
            if !geladen { fehler = error.localizedDescription }
            geladen = true
            kontext.pruefe(error)
        }
    }

    private func erstelle() {
        let name = neuerName.trimmingCharacters(in: .whitespaces)
        guard let client = kontext.client, !name.isEmpty else { return }
        Task {
            do {
                _ = try await client.erstelleAlbum(name: name)
                await lade(erzwingen: true)
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
        }
    }
}

/// Überschrift eines Abschnitts mit „›“: führt zu allen Einträgen.
private struct Ueberschrift: View {
    let titel: String
    var ziel: TimelineZiel?
    var sammlung: SammlungsZiel?

    var body: some View {
        Group {
            if let ziel {
                NavigationLink(value: ziel) { inhalt }
            } else if let sammlung {
                NavigationLink(value: sammlung) { inhalt }
            } else {
                inhalt
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityHint("Alle anzeigen")
    }

    private var inhalt: some View {
        HStack(spacing: 4) {
            Text(titel).font(.title2.bold()).foregroundStyle(LilithColor.text)
            Image(systemName: "chevron.right").font(.title3.weight(.semibold)).foregroundStyle(LilithColor.textLeise)
        }
        .contentShape(.rect)
    }
}

/// Eine Person: rundes Gesicht mit Namen darunter.
struct PersonKarte: View {
    let person: Person
    let client: ImmichClient?
    var kante: CGFloat = 84
    @State private var bild: PlattformBild?

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(LilithColor.flaeche)
                .overlay {
                    if let bild {
                        Image(plattform: bild).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.fill").font(.title).foregroundStyle(LilithColor.textLeise)
                    }
                }
                .clipShape(.circle)
                .frame(width: kante, height: kante)
            if !person.name.isEmpty {
                Text(person.name).font(.footnote.weight(.medium)).foregroundStyle(LilithColor.text)
                    .lineLimit(1).frame(maxWidth: kante + 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.name.isEmpty ? "Person ohne Namen" : person.name)
        .task(id: person.id) {
            guard let client else { return }
            bild = try? await BilderCache.lade(client.personBildAnfrage(person.id))
        }
    }
}

/// Alle Personen als Raster („Alle anzeigen“).
struct PersonenRaster: View {
    let personen: [Person]
    @Environment(BibliothekKontext.self) private var kontext

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [SwiftUI.GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 18) {
                ForEach(personen) { person in
                    NavigationLink(value: TimelineZiel(titel: person.name.isEmpty ? "Person" : person.name,
                                                       filter: .person(person.id))) {
                        PersonKarte(person: person, client: kontext.client, kante: 92)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(LilithColor.hintergrund)
        .navigationTitle("Personen")
    }
}

/// Ruhige Kartenvorschau: ein Punkt je Ort, ohne Bedienung.
struct OrteVorschauKarte: View {
    let orte: [Ort]

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: []) {
            ForEach(orte.prefix(60)) { ort in
                Annotation(ort.stadt, coordinate: CLLocationCoordinate2D(latitude: ort.breite, longitude: ort.laenge),
                           anchor: .center) {
                    Circle()
                        .fill(LilithColor.nachtrose)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }
}

/// Große Karte mit allen Orten: Fotos als runde Stecknadeln mit Anzahl. Ein Tipp öffnet die Fotos der Stadt.
struct OrteKarte: View {
    let orte: [Ort]
    @Environment(BibliothekKontext.self) private var kontext

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(orte) { ort in
                Annotation(ort.stadt, coordinate: CLLocationCoordinate2D(latitude: ort.breite, longitude: ort.laenge),
                           anchor: .bottom) {
                    NavigationLink(value: TimelineZiel(titel: ort.stadt, filter: .ort(stadt: ort.stadt, land: ort.land))) {
                        OrtNadel(ort: ort, client: kontext.client)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .navigationTitle("Orte")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #endif
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Stecknadel: rundes Foto mit weißem Rand und der Anzahl.
private struct OrtNadel: View {
    let ort: Ort
    let client: ImmichClient?

    var body: some View {
        VorschauBild(client: client, assetId: ort.titelBildId)
            .frame(width: 46, height: 46)
            .clipShape(.circle)
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .overlay(alignment: .topTrailing) {
                if ort.anzahl > 1 {
                    Text(ort.anzahl > 999 ? "999+" : "\(ort.anzahl)")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(LilithColor.nachtroseFill, in: .capsule)
                        .offset(x: 8, y: -6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ort.stadt), \(ort.anzahl) Fotos")
    }
}

/// Alle Alben als Raster („Alle anzeigen“).
struct AlbenRaster: View {
    let titel: String
    let alben: [Album]
    @Environment(BibliothekKontext.self) private var kontext

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [SwiftUI.GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                ForEach(alben) { album in
                    NavigationLink(value: TimelineZiel(titel: album.name, filter: .album(album.id))) {
                        AlbumKarte(album: album, client: kontext.client)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(LilithColor.hintergrund)
        .navigationTitle(titel)
    }
}

/// Karte eines Albums mit Titelbild, Name und Anzahl.
struct AlbumKarte: View {
    let album: Album
    let client: ImmichClient?
    var zeigeGeteilt = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VorschauBild(client: client, assetId: album.coverAssetId)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topTrailing) {
                    if album.geteilt && zeigeGeteilt {
                        Text("Geteilt")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: .capsule)
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(album.name).font(LilithFont.karte).foregroundStyle(LilithColor.text).lineLimit(1)
                Text(album.anzahl == 1 ? "1 Objekt" : "\(album.anzahl.formatted()) Objekte")
                    .font(.caption)
                    .foregroundStyle(LilithColor.textLeise)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kleines Vorschaubild eines Fotos, quadratisch zugeschnitten.
struct VorschauBild: View {
    let client: ImmichClient?
    let assetId: String?
    var groesse: VorschauGroesse = .thumbnail
    @State private var bild: PlattformBild?

    var body: some View {
        Color.clear
            .overlay {
                if let bild {
                    Image(plattform: bild).resizable().scaledToFill()
                } else {
                    LilithColor.flaeche
                    Image(systemName: "photo").font(.title).foregroundStyle(LilithColor.textLeise)
                }
            }
            .clipped()
            .task(id: assetId) {
                guard let client, let assetId else { bild = nil; return }
                bild = try? await BilderCache.lade(client.vorschauAnfrage(assetId: assetId, groesse: groesse))
            }
            .accessibilityHidden(true)
    }
}

/// Eine gefilterte Timeline (Favoriten, Archiv, Papierkorb oder ein Album) mit eigenem Speicher.
struct GefilterteTimeline: View {
    let ziel: TimelineZiel
    @Environment(BibliothekKontext.self) private var kontext
    @State private var store: TimelineStore?

    var body: some View {
        Group {
            if let store {
                TimelineInhalt(titel: ziel.titel, quelle: store, store: store)
            } else {
                ProgressView()
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard store == nil, let client = kontext.client else { return }
            let neu = TimelineStore(client: client, filter: ziel.filter)
            let k = kontext
            neu.onSitzungAbgelaufen = { [weak k] in k?.onSitzungAbgelaufen?() }
            store = neu
        }
    }
}

/// Auswahl eines Albums, zu dem Fotos hinzugefügt werden, oder Anlegen eines neuen.
struct AlbumWahl: View {
    enum Ziel {
        case vorhanden(Album)
        case neu(String)
    }

    let anzahl: Int
    let wahl: (Ziel) -> Void

    @Environment(BibliothekKontext.self) private var kontext
    @Environment(\.dismiss) private var dismiss
    @State private var alben: [Album]?
    @State private var neuerName = ""
    @State private var fehler: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Neues Album") {
                    HStack {
                        TextField("Name", text: $neuerName)
                        Button("Anlegen") {
                            wahl(.neu(neuerName.trimmingCharacters(in: .whitespaces)))
                            dismiss()
                        }
                        .disabled(neuerName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Vorhandene Alben") {
                    if let alben {
                        if alben.isEmpty { Text("Noch keine Alben").foregroundStyle(.secondary) }
                        ForEach(alben) { album in
                            Button {
                                wahl(.vorhanden(album))
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VorschauBild(client: kontext.client, assetId: album.coverAssetId)
                                        .frame(width: 44, height: 44)
                                        .clipShape(.rect(cornerRadius: 8))
                                    VStack(alignment: .leading) {
                                        Text(album.name).foregroundStyle(.primary)
                                        Text("\(album.anzahl.formatted()) Objekte").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else if let fehler {
                        Text(fehler).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(anzahl == 1 ? "1 Objekt hinzufügen" : "\(anzahl) Objekte hinzufügen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .task {
                do { alben = try await kontext.client?.alben() ?? [] } catch { fehler = error.localizedDescription }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }
}
