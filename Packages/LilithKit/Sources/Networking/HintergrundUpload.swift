import Foundation

/// Uploads über eine Hintergrund-Session: iOS führt sie weiter, auch wenn Lilith geschlossen ist,
/// und weckt die App, wenn sie fertig sind. Es gibt pro App genau eine (`geteilt`).
public final class HintergrundUpload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public static let kennung = "app.lilith.upload"

    /// Für die App. Tests erzeugen eigene Instanzen mit normaler Konfiguration.
    public static let geteilt = HintergrundUpload(konfiguration: nil, koerperOrdner: standardOrdner())

    /// Ergebnis eines Uploads, auf den gerade niemand wartet (z. B. fertig geworden, während die App zu war).
    public typealias Abschluss = @Sendable (_ kennung: String, _ ergebnis: Result<UploadErgebnis, ImmichError>) -> Void

    private var session: URLSession!
    private let koerperOrdner: URL
    private let sperre = NSLock()
    private var antworten: [Int: Data] = [:]
    private var warter: [String: CheckedContinuation<UploadErgebnis, any Error>] = [:]
    private var fortschritte: [String: @Sendable (Double) -> Void] = [:]
    private var abschluss: Abschluss?
    /// Ergebnisse, die ankamen, bevor jemand zuhört (nach einem Neustart im Hintergrund).
    private var unzugestellt: [(String, Result<UploadErgebnis, ImmichError>)] = []
    private var systemAbschluss: (() -> Void)?

    /// - Parameter konfiguration: `nil` für die Hintergrund-Session der App.
    public init(konfiguration: URLSessionConfiguration?, koerperOrdner: URL) {
        self.koerperOrdner = koerperOrdner
        super.init()
        let k = konfiguration ?? {
            let k = URLSessionConfiguration.background(withIdentifier: Self.kennung)
            k.sessionSendsLaunchEvents = true
            // Nicht „discretionary“: Manuelle Uploads sollen sofort laufen. iOS bremst im Hintergrund ohnehin.
            k.isDiscretionary = false
            k.timeoutIntervalForResource = 7 * 24 * 3600
            return k
        }()
        session = URLSession(configuration: k, delegate: self, delegateQueue: nil)
    }

    static func standardOrdner() -> URL {
        let basis = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return basis.appending(path: "Lilith/Uploadkoerper", directoryHint: .isDirectory)
    }

    /// Wer Ergebnisse ohne Wartenden bekommt. Schon eingetroffene werden sofort nachgereicht.
    public func setzeAbschluss(_ neu: @escaping Abschluss) {
        let offen = sperre.withLock {
            abschluss = neu
            defer { unzugestellt = [] }
            return unzugestellt
        }
        for (k, e) in offen { neu(k, e) }
    }

    /// Vom App-Delegate: iOS hat die App für fertige Hintergrund-Uploads geweckt.
    public func setzeSystemAbschluss(_ fertig: @escaping () -> Void) {
        sperre.withLock { systemAbschluss = fertig }
    }

    /// Kennungen der Uploads, die gerade (noch) laufen, auch aus einem früheren App-Start.
    public func laufendeKennungen() async -> Set<String> {
        Set(await session.allTasks.filter { $0.state == .running || $0.state == .suspended }.compactMap(\.taskDescription))
    }

    /// Startet einen Upload und kehrt sofort zurück. Das Ergebnis kommt über `setzeAbschluss`.
    public func starte(_ d: UploadDatei, client: ImmichClient, kennung: String) throws {
        try FileManager.default.createDirectory(at: koerperOrdner, withIntermediateDirectories: true)
        let body = koerper(kennung)
        try? FileManager.default.removeItem(at: body)
        let grenze = try Multipart.schreibe(d, nach: body)
        let aufgabe = session.uploadTask(with: client.uploadAnfrage(grenze: grenze, datei: d), fromFile: body)
        aufgabe.taskDescription = kennung
        aufgabe.resume()
    }

    /// Lädt hoch und wartet auf das Ergebnis (läuft trotzdem weiter, falls die App dabei in den Hintergrund geht).
    public func ladeHoch(_ d: UploadDatei, client: ImmichClient, kennung: String,
                         fortschritt: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> UploadErgebnis {
        try await withCheckedThrowingContinuation { fortsetzen in
            sperre.withLock {
                warter[kennung] = fortsetzen
                fortschritte[kennung] = fortschritt
            }
            do {
                try starte(d, client: client, kennung: kennung)
            } catch {
                let w = sperre.withLock { () -> CheckedContinuation<UploadErgebnis, any Error>? in
                    fortschritte[kennung] = nil
                    return warter.removeValue(forKey: kennung)
                }
                w?.resume(throwing: ImmichError.dateiNichtLesbar(error.localizedDescription))
            }
        }
    }

    private func koerper(_ kennung: String) -> URL {
        let sicher = kennung.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return koerperOrdner.appending(path: "\(sicher).multipart")
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        sperre.withLock { antworten[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0, let k = task.taskDescription,
              let melden = sperre.withLock({ fortschritte[k] }) else { return }
        melden(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let kennung = task.taskDescription else { return }
        let daten = sperre.withLock { antworten.removeValue(forKey: task.taskIdentifier) } ?? Data()
        try? FileManager.default.removeItem(at: koerper(kennung))

        let ergebnis: Result<UploadErgebnis, ImmichError>
        if let error {
            ergebnis = .failure(.nichtErreichbar(ImmichClient.kurzerGrund(error)))
        } else {
            do {
                ergebnis = .success(try ImmichClient.werteUploadAus(
                    status: (task.response as? HTTPURLResponse)?.statusCode ?? 0, daten: daten))
            } catch {
                ergebnis = .failure(error as? ImmichError ?? .keinImmichServer)
            }
        }

        let (wartend, empfaenger) = sperre.withLock { () -> (CheckedContinuation<UploadErgebnis, any Error>?, Abschluss?) in
            fortschritte[kennung] = nil
            let w = warter.removeValue(forKey: kennung)
            if w == nil, abschluss == nil { unzugestellt.append((kennung, ergebnis)) }
            return (w, abschluss)
        }
        if let wartend {
            wartend.resume(with: ergebnis.mapError { $0 as any Error })
        } else {
            empfaenger?(kennung, ergebnis)
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let fertig = sperre.withLock { () -> (() -> Void)? in
            defer { systemAbschluss = nil }
            return systemAbschluss
        }
        DispatchQueue.main.async { fertig?() }
    }
}
