import SwiftUI
import DesignSystem
import Networking

// MARK: - Doppelte Fotos

/// Gruppen doppelter Fotos. Je Gruppe: Fotos nebeneinander mit Größe und Auflösung, Immichs Vorschlag ist
/// vorausgewählt. „Auswahl behalten“ legt die übrigen in den Papierkorb (dort wiederherstellbar).
struct DuplikateView: View {
    @Environment(BibliothekKontext.self) private var kontext
    @State private var gruppen: [DuplikatGruppe]?
    @State private var behalten: [String: Set<String>] = [:]
    @State private var arbeitet: String?
    @State private var fehler: String?

    var body: some View {
        Group {
            if let gruppen {
                if gruppen.isEmpty {
                    ContentUnavailableView {
                        Label("Keine doppelten Fotos", systemImage: "checkmark.circle")
                    } description: {
                        Text("Immich hat keine doppelten Fotos gefunden. Die Suche danach läuft auf dem Server.")
                    }
                } else {
                    liste(gruppen)
                }
            } else {
                ProgressView()
            }
        }
        .background(LilithColor.hintergrund)
        .navigationTitle("Doppelte Fotos")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await lade() }
        .refreshable { await lade() }
        .alert("Das hat nicht geklappt", isPresented: .constant(fehler != nil), presenting: fehler) { _ in
            Button("OK") { fehler = nil }
        } message: { Text($0) }
    }

    private func liste(_ gruppen: [DuplikatGruppe]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(gruppen.count == 1 ? "1 Gruppe" : "\(gruppen.count) Gruppen")
                    .font(.subheadline).foregroundStyle(LilithColor.textLeise)
                    .padding(.horizontal, 16)
                ForEach(gruppen) { gruppe in
                    gruppeAnsicht(gruppe)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func gruppeAnsicht(_ gruppe: DuplikatGruppe) -> some View {
        let auswahl = behalten[gruppe.id] ?? gruppe.vorschlag
        let weg = gruppe.fotos.count - auswahl.count
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(gruppe.fotos) { foto in
                        let gewaehlt = auswahl.contains(foto.id)
                        Button {
                            var neu = auswahl
                            if gewaehlt { neu.remove(foto.id) } else { neu.insert(foto.id) }
                            behalten[gruppe.id] = neu
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                VorschauBild(client: kontext.client, assetId: foto.id)
                                    .frame(width: 150, height: 150)
                                    .clipShape(.rect(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: gewaehlt ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, gewaehlt ? LilithColor.nachtroseFill : .black.opacity(0.25))
                                            .padding(8)
                                    }
                                    .opacity(gewaehlt ? 1 : 0.55)
                                Text(details(foto)).font(.caption).foregroundStyle(LilithColor.textLeise).lineLimit(2)
                            }
                            .frame(width: 150, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(foto.dateiname), \(details(foto))")
                        .accessibilityValue(gewaehlt ? "wird behalten" : "kommt in den Papierkorb")
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            HStack {
                Text(weg == 0 ? "Alle behalten" : "\(weg) in den Papierkorb")
                    .font(.subheadline).foregroundStyle(LilithColor.textLeise)
                Spacer()
                Button {
                    loese(gruppe, behalten: auswahl)
                } label: {
                    if arbeitet == gruppe.id { ProgressView() } else { Text("Auswahl behalten") }
                }
                .buttonStyle(.borderedProminent)
                .tint(LilithColor.nachtroseFill)
                .disabled(auswahl.isEmpty || weg == 0 || arbeitet != nil)
            }
            .padding(.horizontal, 16)
        }
    }

    private func details(_ f: DuplikatFoto) -> String {
        var teile: [String] = []
        if let b = f.breite, let h = f.hoehe { teile.append("\(b) × \(h)") }
        if let bytes = f.bytes { teile.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
        teile.append(f.aufgenommen.formatted(date: .abbreviated, time: .omitted))
        return teile.joined(separator: " · ")
    }

    private func lade() async {
        guard let client = kontext.client else { return }
        do {
            gruppen = try await client.duplikate()
        } catch {
            if gruppen == nil { gruppen = [] }
            fehler = error.localizedDescription
            kontext.pruefe(error)
        }
    }

    private func loese(_ gruppe: DuplikatGruppe, behalten auswahl: Set<String>) {
        guard let client = kontext.client else { return }
        arbeitet = gruppe.id
        Task {
            do {
                try await client.loeseDuplikat(gruppe, behalten: auswahl)
                withAnimation(.smooth) { gruppen?.removeAll { $0.id == gruppe.id } }
                kontext.melde(von: nil)
            } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
            arbeitet = nil
        }
    }
}

// MARK: - Ordner

/// Ordner auf dem Server wie im Dateien-Browser: Unterordner als Liste, Fotos des Ordners als Timeline.
struct OrdnerView: View {
    /// `""`: oberste Ebene (beginnt beim gemeinsamen Anfang aller Pfade).
    let pfad: String
    @Environment(BibliothekKontext.self) private var kontext
    @State private var alle: [String]?
    @State private var fehler: String?

    private var aktuell: String {
        guard let alle else { return pfad }
        return pfad.isEmpty ? OrdnerBaum.gemeinsamerAnfang(alle) : pfad
    }

    var body: some View {
        Group {
            if let alle {
                let unter = OrdnerBaum.unterordner(von: aktuell, in: alle)
                List {
                    if OrdnerBaum.hatFotos(aktuell, in: alle) {
                        Section {
                            NavigationLink(value: TimelineZiel(titel: name(aktuell), filter: .ordner(aktuell))) {
                                Label { Text("Fotos in diesem Ordner") } icon: {
                                    Image(systemName: "photo.on.rectangle").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(unter, id: \.pfad) { o in
                            NavigationLink(value: SammlungsZiel.ordner(o.pfad)) {
                                // Symbole in Listen einfarbig (Akzent nur für Auswahl).
                                Label { Text(o.name) } icon: { Image(systemName: "folder").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .overlay {
                    if unter.isEmpty && !OrdnerBaum.hatFotos(aktuell, in: alle) {
                        ContentUnavailableView("Keine Ordner", systemImage: "folder")
                    }
                }
            } else if let fehler {
                ContentUnavailableView("Nicht geladen", systemImage: "exclamationmark.triangle", description: Text(fehler))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(pfad.isEmpty ? "Ordner" : name(pfad))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard alle == nil, let client = kontext.client else { return }
            do { alle = try await client.ordnerPfade() } catch {
                fehler = error.localizedDescription
                kontext.pruefe(error)
            }
        }
    }

    private func name(_ p: String) -> String {
        p.split(separator: "/").last.map(String.init) ?? p
    }
}

// MARK: - Gesperrter Bereich

/// Immichs gesperrter Bereich: Fotos darin tauchen nirgends sonst auf. Öffnen mit Face ID
/// (die Immich-PIN liegt geschützt im Schlüsselbund) oder mit der PIN.
struct GesperrtView: View {
    @Environment(BibliothekKontext.self) private var kontext

    enum Stand: Equatable { case prueft, einrichten, pin, offen, fehler(String) }

    @State private var stand: Stand = .prueft
    @State private var pin = ""
    @State private var pinWiederholt = ""
    @State private var arbeitet = false
    @State private var hinweis: String?

    private var konto: String { kontext.client?.address.description ?? "" }

    var body: some View {
        Group {
            switch stand {
            case .prueft:
                ProgressView("Wird geöffnet …")
            case .offen:
                GefilterteTimeline(ziel: TimelineZiel(titel: "Gesperrt", filter: .gesperrt))
            case .einrichten:
                pinFormular(einrichten: true)
            case .pin:
                pinFormular(einrichten: false)
            case .fehler(let text):
                ContentUnavailableView("Nicht geöffnet", systemImage: "lock.slash", description: Text(text))
            }
        }
        .navigationTitle("Gesperrt")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await oeffne() }
        .onDisappear {
            // Beim Verlassen sofort wieder sperren.
            guard let client = kontext.client else { return }
            Task { await client.sperreSitzung() }
        }
    }

    private func pinFormular(einrichten: Bool) -> some View {
        Form {
            Section {
                SecureField("PIN (6 Ziffern)", text: $pin)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textContentType(einrichten ? .newPassword : .password)
                if einrichten {
                    SecureField("PIN wiederholen", text: $pinWiederholt)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            } header: {
                Text(einrichten ? "PIN einrichten" : "PIN eingeben")
            } footer: {
                Text(hinweis ?? (einrichten
                     ? "Immich schützt den gesperrten Bereich mit einer eigenen PIN. Luna merkt sie sich hinter Face ID, du musst sie danach nicht mehr eingeben."
                     : "Die PIN deines gesperrten Bereichs auf dem Immich-Server. Luna merkt sie sich danach hinter Face ID."))
            }
            Section {
                Button {
                    Task { await bestaetige(einrichten: einrichten) }
                } label: {
                    HStack { Text(einrichten ? "Einrichten und öffnen" : "Öffnen"); Spacer(); if arbeitet { ProgressView() } }
                }
                .disabled(arbeitet || pin.count != 6 || pin.contains { !$0.isNumber } || (einrichten && pin != pinWiederholt))
            }
        }
        .formStyle(.grouped)
    }

    private func oeffne() async {
        guard let client = kontext.client else { stand = .fehler("Keine Verbindung zum Server."); return }
        do {
            let status = try await client.sperrStatus()
            if status.entsperrt { stand = .offen; return }
            guard status.hatPin else { stand = .einrichten; return }
            // Gespeicherte PIN per Face ID holen und damit entsperren.
            if PinSafe.hatGespeichert(konto: konto), let gemerkt = await PinSafe.lies(konto: konto) {
                do {
                    try await client.entsperre(pin: gemerkt)
                    stand = .offen
                    return
                } catch {
                    PinSafe.loesche(konto: konto)   // passt nicht mehr (z. B. in Immich geändert)
                }
            }
            stand = .pin
        } catch {
            stand = .fehler(error.localizedDescription)
            kontext.pruefe(error)
        }
    }

    private func bestaetige(einrichten: Bool) async {
        guard let client = kontext.client else { return }
        arbeitet = true
        defer { arbeitet = false }
        do {
            if einrichten { try await client.richtePinEin(pin) }
            try await client.entsperre(pin: pin)
            try? PinSafe.speichere(pin, konto: konto)
            pin = ""; pinWiederholt = ""
            withAnimation(.smooth) { stand = .offen }
        } catch {
            hinweis = einrichten ? "Das hat nicht geklappt: \(error.localizedDescription)" : "Die PIN stimmt nicht."
            pin = ""
        }
    }
}
