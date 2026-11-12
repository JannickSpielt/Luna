import ImageIO
import SwiftUI
import Backup
import DesignSystem
import Persistence

/// Was nicht gesichert wurde und warum. Jedes Foto lässt sich einzeln erneut versuchen oder ignorieren.
struct FehlerListeView: View {
    let uploads: UploadWarteschlange?
    let backup: BackupDienst?

    @State private var auftraege: [UploadWarteschlange.FehlerEintrag] = []
    @State private var fehlerFotos: [LokalesFoto] = []
    @State private var uebersprungen: [LokalesFoto] = []

    var body: some View {
        List {
            if auftraege.isEmpty && fehlerFotos.isEmpty && uebersprungen.isEmpty {
                ContentUnavailableView("Keine Fehler", systemImage: "checkmark.circle",
                                       description: Text("Alles, was gesichert werden soll, ist auf dem Server oder auf dem Weg dorthin."))
                    .listRowBackground(Color.clear)
            }
            if !auftraege.isEmpty || !fehlerFotos.isEmpty {
                Section {
                    ForEach(auftraege) { a in
                        zeile(titel: a.dateiname, grund: a.fehler, vorschau: vorschau(lokaleId: a.lokaleId, datei: a.datei)) {
                            uploads?.wiederhole(a.id)
                            lade()
                        } ignorieren: {
                            uploads?.verwirf(a.id)
                            lade()
                        }
                    }
                    ForEach(fehlerFotos, id: \.lokaleId) { f in
                        zeile(titel: datum(f.erstellt), grund: f.grund ?? "Unbekannter Fehler",
                              vorschau: vorschau(lokaleId: f.lokaleId, datei: nil)) {
                            backup?.wiederhole(lokaleId: f.lokaleId)
                            lade()
                        } ignorieren: {
                            backup?.ignoriere(lokaleId: f.lokaleId)
                            lade()
                        }
                    }
                } header: {
                    Text("Nicht gesichert")
                } footer: {
                    Text("„Ignorieren“ sichert das Foto nicht mehr, bis du es hier erneut versuchst.")
                }
            }
            if !uebersprungen.isEmpty {
                Section("Übersprungen") {
                    ForEach(uebersprungen, id: \.lokaleId) { f in
                        zeile(titel: datum(f.erstellt), grund: f.grund ?? "Übersprungen",
                              vorschau: vorschau(lokaleId: f.lokaleId, datei: nil),
                              erneut: {
                                  backup?.wiederhole(lokaleId: f.lokaleId)
                                  lade()
                              },
                              ignorieren: nil)
                    }
                }
            }
        }
        .navigationTitle("Nicht gesichert")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !auftraege.isEmpty || !fehlerFotos.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Alle erneut") {
                        uploads?.wiederhole()
                        backup?.wiederholeFehler()
                        lade()
                    }
                }
            }
        }
        .onAppear(perform: lade)
    }

    private func lade() {
        auftraege = uploads?.fehlerEintraege() ?? []
        let mitAuftrag = Set(auftraege.compactMap(\.lokaleId))
        // Ein Foto mit gescheitertem Auftrag nur einmal zeigen.
        fehlerFotos = (backup?.fehlerFotos() ?? []).filter { !mitAuftrag.contains($0.lokaleId) }
        uebersprungen = backup?.uebersprungeneFotos() ?? []
    }

    private func datum(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    private func vorschau(lokaleId: String?, datei: String?) -> FehlerVorschau {
        FehlerVorschau(backup: backup, lokaleId: lokaleId, datei: datei)
    }

    private func zeile(titel: String, grund: String, vorschau: FehlerVorschau,
                       erneut: @escaping () -> Void, ignorieren: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            vorschau
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(titel).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(grund).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
            Button("Erneut", action: erneut)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .swipeActions {
            if let ignorieren {
                Button("Ignorieren", role: .destructive, action: ignorieren)
            }
        }
        .contextMenu {
            Button("Erneut versuchen", systemImage: "arrow.clockwise", action: erneut)
            if let ignorieren {
                Button("Ignorieren", systemImage: "eye.slash", role: .destructive, action: ignorieren)
            }
        }
    }
}

/// Vorschau eines Fotos in der Fehlerliste: vom Gerät oder aus der hochzuladenden Kopie.
struct FehlerVorschau: View {
    let backup: BackupDienst?
    let lokaleId: String?
    let datei: String?
    @State private var bild: CGImage?
    @Environment(\.displayScale) private var skala

    var body: some View {
        ZStack {
            LilithColor.flaeche
            if let bild {
                Image(decorative: bild, scale: skala).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(LilithColor.textLeise)
            }
        }
        .task {
            if let lokaleId, let backup, let b = await backup.vorschau(lokaleId, kante: 48 * skala) {
                bild = b
            } else if let datei {
                bild = await Task.detached { Self.miniatur(datei, kante: 144) }.value
            }
        }
    }

    nonisolated static func miniatur(_ pfad: String, kante: CGFloat) -> CGImage? {
        guard let quelle = CGImageSourceCreateWithURL(URL(fileURLWithPath: pfad) as CFURL, nil) else { return nil }
        let optionen: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: kante,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary)
    }
}
