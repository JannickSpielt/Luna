import SwiftUI
import DesignSystem

/// Neueste Version von Luna auf GitHub (Releases des öffentlichen Repos).
struct LunaRelease: Equatable, Sendable {
    let version: String
    let titel: String
    let seite: URL
    /// Direkter Download der Mac-App (DMG, bei älteren Releases ZIP), falls vorhanden.
    let macDownload: URL?
}

enum AppUpdate {
    static let repo = "JannickSpielt/Luna"

    /// Version dieser App, z. B. „0.9.0“.
    static var installiert: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Fragt GitHub nach dem neuesten Release.
    static func neuestes() async throws -> LunaRelease {
        var anfrage = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        anfrage.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        anfrage.timeoutInterval = 15
        let (daten, antwort) = try await URLSession.shared.data(for: anfrage)
        guard (antwort as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let tag_name: String; let name: String?; let html_url: URL; let assets: [Asset] }
        let r = try JSONDecoder().decode(Release.self, from: daten)
        let version = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
        // Mac-App: am liebsten die DMG, sonst die ZIP (ältere Releases).
        let mac = r.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            ?? r.assets.first { $0.name.localizedCaseInsensitiveContains("mac") && $0.name.hasSuffix(".zip") }
        return LunaRelease(version: version, titel: r.name ?? r.tag_name, seite: r.html_url, macDownload: mac?.browser_download_url)
    }

    /// Ist `a` neuer als `b`? Vergleicht Zahlen der Reihe nach („0.10.0“ > „0.9.1“), Zusätze wie „-beta“ zählen nicht.
    static func istNeuer(_ a: String, als b: String) -> Bool {
        func teile(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? [0]
        }
        let x = teile(a), y = teile(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

/// Abschnitt „Über Luna“ in den Einstellungen: Version und nach Updates suchen.
struct UeberLunaAbschnitt: View {
    enum Stand: Equatable {
        case bereit, sucht, aktuell, neu(LunaRelease), fehler
    }

    @State private var stand: Stand = .bereit
    @Environment(\.openURL) private var oeffne

    var body: some View {
        Section {
            LabeledContent("Version", value: AppUpdate.installiert)
            switch stand {
            case .bereit, .fehler:
                Button("Nach Updates suchen") { pruefe() }
            case .sucht:
                HStack {
                    Text("Suche nach Updates …").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            case .aktuell:
                Label("Luna ist auf dem neuesten Stand", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .neu(let release):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Version \(release.version) ist da", systemImage: "arrow.down.circle")
                        .font(.headline)
                    #if os(macOS)
                    Button("Mac-App herunterladen") { oeffne(release.macDownload ?? release.seite) }
                        .buttonStyle(.borderedProminent)
                        .tint(LilithColor.nachtroseFill)
                    #endif
                    Button("Was ist neu?") { oeffne(release.seite) }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Über Luna")
        } footer: {
            #if os(iOS)
            Text(stand == .fehler
                 ? "GitHub war nicht erreichbar. Versuch es später noch einmal."
                 : "Auf dem iPhone kommen neue Versionen über Xcode (später über TestFlight). Hier siehst du, ob es eine neue gibt.")
            #else
            Text(stand == .fehler
                 ? "GitHub war nicht erreichbar. Versuch es später noch einmal."
                 : "Neue Versionen liegen auf GitHub unter „Releases“. Die neue App einfach in den Programme-Ordner ziehen und die alte ersetzen.")
            #endif
        }
        .task { pruefe(leise: true) }
    }

    private func pruefe(leise: Bool = false) {
        if !leise { stand = .sucht }
        Task {
            do {
                let r = try await AppUpdate.neuestes()
                stand = AppUpdate.istNeuer(r.version, als: AppUpdate.installiert) ? .neu(r) : (leise ? .bereit : .aktuell)
            } catch {
                stand = leise ? .bereit : .fehler
            }
        }
    }
}
