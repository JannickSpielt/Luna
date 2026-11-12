import SwiftUI
import DesignSystem
import Networking
import TimelineGrid

/// Ziel einer Navigation: eine gefilterte Timeline mit Titel.
struct TimelineZiel: Hashable {
    let titel: String
    let filter: TimelineFilter
}

/// Der Alben-Tab: Sammlungen (Favoriten, Archiv, Papierkorb) und alle Alben.
struct AlbenView: View {
    @Environment(BibliothekKontext.self) private var kontext
    @State private var alben: [Album] = []
    @State private var geladen = false
    @State private var fehler: String?
    @State private var neuesAlbum = false
    @State private var neuerName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    sammlungen
                    albenBereich
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(LilithColor.hintergrund)
            .navigationTitle("Alben")
            .toolbar {
                if kontext.client != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Neues Album", systemImage: "plus") { neuerName = ""; neuesAlbum = true }
                    }
                }
            }
            .navigationDestination(for: TimelineZiel.self) { ziel in
                GefilterteTimeline(ziel: ziel)
            }
            .refreshable { await lade() }
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

    private var sammlungen: some View {
        VStack(spacing: 0) {
            sammlung("Kürzlich hinzugefügt", "clock.arrow.circlepath", .kuerzlich)
            Divider().padding(.leading, 52)
            sammlung("Favoriten", "heart", .favoriten)
            Divider().padding(.leading, 52)
            sammlung("Archiv", "archivebox", .archiv)
            if kontext.papierkorbAktiv {
                Divider().padding(.leading, 52)
                sammlung("Papierkorb", "trash", .papierkorb)
            }
        }
        .background(LilithColor.flaeche, in: .rect(cornerRadius: 16))
    }

    private func sammlung(_ titel: String, _ symbol: String, _ filter: TimelineFilter) -> some View {
        NavigationLink(value: TimelineZiel(titel: titel, filter: filter)) {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(LilithColor.nachtrose).frame(width: 24)
                Text(titel).foregroundStyle(LilithColor.text)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(LilithColor.textLeise)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(kontext.client == nil)
    }

    @ViewBuilder
    private var albenBereich: some View {
        if kontext.client == nil {
            Text("Alben gibt es nur mit einer Verbindung zum Server.").foregroundStyle(LilithColor.textLeise)
        } else if !geladen {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
        } else if alben.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Alben", systemImage: "rectangle.stack")
            } description: {
                Text("Lege mit dem Plus oben ein Album an.")
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Meine Alben").font(.system(.title3, design: .serif, weight: .semibold))
                LazyVGrid(columns: [SwiftUI.GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                    ForEach(alben) { album in
                        NavigationLink(value: TimelineZiel(titel: album.name, filter: .album(album.id))) {
                            AlbumKarte(album: album, client: kontext.client)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func lade() async {
        guard let client = kontext.client else { return }
        do {
            alben = try await client.alben()
            geladen = true
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
                await lade()
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
        }
    }
}

/// Karte eines Albums mit Titelbild, Name und Anzahl.
struct AlbumKarte: View {
    let album: Album
    let client: ImmichClient?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VorschauBild(client: client, assetId: album.coverAssetId)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 16))
                .overlay(alignment: .topTrailing) {
                    if album.geteilt {
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
                bild = try? await BilderCache.lade(client.vorschauAnfrage(assetId: assetId, groesse: .thumbnail))
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
