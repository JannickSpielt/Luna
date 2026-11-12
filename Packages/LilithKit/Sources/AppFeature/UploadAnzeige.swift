import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import DesignSystem
import Backup

/// Datei aus Apples Foto-Auswahl, als Original (z. B. HEIC) in einen eigenen Ordner kopiert.
struct AuswahlDatei: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { erhalten in
            let ordner = FileManager.default.temporaryDirectory
                .appending(path: "lilith-auswahl/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            let ziel = ordner.appending(path: erhalten.file.lastPathComponent)
            try FileManager.default.copyItem(at: erhalten.file, to: ziel)
            return AuswahlDatei(url: ziel)
        }
    }
}

/// Kleine Anzeige unten: was gerade hochgeladen wird, danach kurz das Ergebnis.
struct UploadAnzeige: View {
    let uploads: UploadWarteschlange
    @State private var zeigeErgebnis = false
    @State private var zeigeFehler = false
    @Environment(\.accessibilityReduceMotion) private var wenigBewegung

    var body: some View {
        let s = uploads.stand
        Group {
            if s.laeuft {
                inhalt {
                    MondSymbol(phase: s.gesamtAnteil).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lädt hoch · \(min(s.erledigt + 1, s.gesamt)) von \(s.gesamt)")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: s.gesamtAnteil).tint(LilithColor.nachtrose).frame(width: 170)
                    }
                }
                .accessibilityLabel("Lädt hoch, \(s.erledigt) von \(s.gesamt) fertig")
            } else if let halt = uploads.halt {
                inhalt {
                    Image(systemName: "pause.circle").foregroundStyle(LilithColor.nachtrose)
                    Text(halt).font(.caption).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 260, alignment: .leading)
                    Button("Erneut") { uploads.wiederhole(); uploads.start() }.font(.caption.weight(.semibold))
                }
            } else if zeigeErgebnis || s.fehler > 0 {
                inhalt {
                    Image(systemName: s.fehler > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(s.fehler > 0 ? LilithColor.nachtrose : Color.green)
                    Text(zusammenfassung(s)).font(.subheadline)
                    if s.fehler > 0 {
                        Button("Details") { zeigeFehler = true }.font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(.bottom, 12)
        .animation(wenigBewegung ? nil : .spring(duration: 0.3), value: s)
        .onChange(of: s.laeuft) { _, laeuft in
            guard !laeuft, s.gesamt > 0 else { return }
            zeigeErgebnis = true
            Task {
                try? await Task.sleep(for: .seconds(5))
                zeigeErgebnis = false
            }
        }
        .alert("Nicht hochgeladen", isPresented: $zeigeFehler) {
            Button("Erneut versuchen") { uploads.wiederhole() }
            Button("Verwerfen", role: .destructive) { uploads.verwirfFehler() }
            Button("Schließen", role: .cancel) {}
        } message: {
            Text(uploads.fehlerListe().prefix(5).map { "\($0.dateiname): \($0.fehler)" }.joined(separator: "\n\n"))
        }
    }

    private func inhalt<Inhalt: View>(@ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        HStack(spacing: 10) { inhalt() }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func zusammenfassung(_ s: UploadWarteschlange.Stand) -> String {
        var teile: [String] = []
        if s.hochgeladen > 0 { teile.append(s.hochgeladen == 1 ? "1 hochgeladen" : "\(s.hochgeladen) hochgeladen") }
        if s.duplikate > 0 { teile.append(s.duplikate == 1 ? "1 war schon da" : "\(s.duplikate) waren schon da") }
        if s.fehler > 0 { teile.append(s.fehler == 1 ? "1 fehlgeschlagen" : "\(s.fehler) fehlgeschlagen") }
        return teile.isEmpty ? "Fertig" : teile.joined(separator: " · ")
    }
}
