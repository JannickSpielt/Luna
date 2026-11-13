import MapKit
import SwiftUI
import DesignSystem
import Networking

/// Infos unter dem Foto (wie Apple Fotos): Das Foto rutscht nach oben, darunter Karten mit Datum, Kamera und Ort.
struct InfoUnterFoto: View {
    let info: AssetInfo?
    let client: ImmichClient?

    var body: some View {
        ScrollView {
            if let info {
                VStack(spacing: 16) {
                    if let text = info.beschreibung, !text.isEmpty {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(LilithColor.flaeche, in: .rect(cornerRadius: 22))
                    }
                    aufnahmeKarte(info)
                    ortKarte(info)
                    if !info.personen.isEmpty {
                        Label(info.personen.joined(separator: ", "), systemImage: "person.2")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(LilithColor.flaeche, in: .rect(cornerRadius: 22))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                // Platz für die untere Leiste.
                .padding(.bottom, 110)
            } else {
                ProgressView().padding(.top, 40)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Datum, Datei, Kamera, Belichtung

    private func aufnahmeKarte(_ info: AssetInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(InfoPanel.datum(info.aufgenommenLokal, mitWochentag: true)) um \(InfoPanel.uhrzeit(info.aufgenommenLokal))")
                    .font(.body.weight(.medium))
                Text(info.dateiname).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(16)

            Divider().padding(.leading, 16)
            HStack {
                Text(info.kamera ?? (info.istVideo ? "Video" : "Unbekannte Kamera"))
                Spacer()
                if let endung = Self.endung(info.dateiname) {
                    Text(endung)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: .capsule)
                }
            }
            .padding(16)

            Divider().padding(.leading, 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(info.objektiv ?? "Keine Objektivinformationen")
                if let datei = Self.dateiZeile(info) { Text(datei) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(16)

            let werte = Self.belichtungsWerte(info)
            if !werte.isEmpty {
                Divider().padding(.leading, 16)
                HStack(spacing: 0) {
                    ForEach(Array(werte.enumerated()), id: \.offset) { i, wert in
                        if i > 0 { Divider().frame(height: 18) }
                        Text(wert).frame(maxWidth: .infinity)
                    }
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
        }
        .background(LilithColor.flaeche, in: .rect(cornerRadius: 22))
    }

    // MARK: Ort

    @ViewBuilder
    private func ortKarte(_ info: AssetInfo) -> some View {
        if let lat = info.latitude, let lon = info.longitude {
            let ort = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(center: ort, latitudinalMeters: 2500, longitudinalMeters: 2500)),
                    interactionModes: []) {
                    Annotation(info.ort ?? "Aufnahmeort", coordinate: ort) {
                        VorschauBild(client: client, assetId: info.id)
                            .frame(width: 52, height: 52)
                            .clipShape(.rect(cornerRadius: 8))
                            .padding(3)
                            .background(.white, in: .rect(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .annotationTitles(.hidden)
                }
                .frame(height: 200)
                .accessibilityLabel("Karte: \(info.ort ?? "Aufnahmeort")")
                if let name = info.ort {
                    Text(name)
                        .font(.subheadline)
                        .padding(16)
                }
            }
            .background(LilithColor.flaeche)
            .clipShape(.rect(cornerRadius: 22))
        } else if let name = info.ort {
            Label(name, systemImage: "mappin.and.ellipse")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LilithColor.flaeche, in: .rect(cornerRadius: 22))
        }
    }

    // MARK: Formatierung

    static func endung(_ name: String) -> String? {
        let e = (name as NSString).pathExtension.uppercased()
        return e.isEmpty ? nil : (e == "JPG" ? "JPEG" : e)
    }

    /// „12 MP · 4288 × 2848 · 1,9 MB“
    static func dateiZeile(_ info: AssetInfo) -> String? {
        var teile: [String] = []
        if let b = info.breite, let h = info.hoehe, b > 0, h > 0 {
            teile.append(InfoPanel.megapixel(b, h))
            teile.append("\(b) × \(h)")
        }
        if let bytes = info.dateigroesse { teile.append(Int64(bytes).formatted(.byteCount(style: .file))) }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    /// Einzelwerte für die Zeile ganz unten: ISO, Brennweite, Blende, Belichtungszeit.
    static func belichtungsWerte(_ info: AssetInfo) -> [String] {
        let de = Locale(identifier: "de_DE")
        var w: [String] = []
        if let iso = info.iso, iso > 0 { w.append("ISO \(iso)") }
        if let b = info.brennweite, b > 0 { w.append("\(b.formatted(.number.precision(.fractionLength(0...1)).locale(de))) mm") }
        if let f = info.blende, f > 0 { w.append("ƒ\(f.formatted(.number.precision(.fractionLength(0...1)).locale(de)))") }
        if let t = info.belichtung { w.append("\(t) s") }
        return w
    }
}
