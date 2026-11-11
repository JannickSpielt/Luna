<!-- Lilith | Project README -->

<div align="center">
  <img src="assets/lilith-icon.png" alt="Lilith App-Icon: Mondsichel mit Kamerablende" width="150" />

  <h1>Lilith</h1>
  <p><strong>Deine Immich-Fotobibliothek. Nativ auf Apple-Geräten.</strong></p>
  <p>Eine native SwiftUI-App für den Zugriff auf den eigenen Immich-Server – mit Fokus auf eine moderne, flüssige Fotoerfahrung.</p>

  <p>
    <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20iPadOS%20%7C%20macOS-147EFB?style=flat-square&logo=apple&logoColor=white" alt="iOS, iPadOS and macOS" />
    <img src="https://img.shields.io/badge/Technologie-SwiftUI-orange?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI" />
    <img src="https://img.shields.io/badge/Backend-Immich-4250AF?style=flat-square" alt="Immich" />
    <img src="https://img.shields.io/badge/Status-Konzept-64748b?style=flat-square" alt="Konzeptphase" />
  </p>

  <p>
    <a href="https://immich.app/">Immich kennenlernen</a>
    ·
    <a href="https://api.immich.app/">Immich API</a>
  </p>
</div>

---

## Die Idee

**Lilith** soll eine native Begleit-App für selbst gehostete [Immich](https://immich.app/)-Instanzen werden. Die Fotos und Videos bleiben auf deinem eigenen Server. Lilith stellt dafür eine Oberfläche bereit, die sich auf iPhone und iPad zu Hause fühlt.

Das Projekt baut keine eigene Cloud und ersetzt keinen Immich-Server. Es soll dessen vorhandene Schnittstellen nutzen und den Zugriff auf die persönliche Medienbibliothek angenehmer machen.

> Lilith ist ein unabhängiges Community-Projekt und steht in keiner offiziellen Verbindung zum Immich-Team.

## Geplante Funktionen

| Bereich | Ziel |
| --- | --- |
| **Serververbindung** | Adresse der eigenen Immich-Instanz hinterlegen |
| **Anmeldung** | Mit dem bestehenden Immich-Konto verbinden |
| **Timeline** | Fotos und Videos chronologisch durchstöbern |
| **Medienansicht** | Bilder groß ansehen und Videos wiedergeben |
| **Alben** | Eigene Alben anzeigen und verwalten |
| **Favoriten** | Markierte Medien schnell wiederfinden |
| **Performance** | Zwischenspeicherung für flüssiges Laden |

Alle Punkte sind Entwicklungsziele. Sie sind noch keine bestätigten oder verfügbaren App-Funktionen.

## Technischer Ansatz

Lilith ist als native Apple-App für iPhone, iPad und Mac geplant:

- **Swift** als Programmiersprache
- **SwiftUI** für die Benutzeroberfläche
- **Immich REST API** als Verbindung zum eigenen Server
- **Keychain** zur sicheren Speicherung sensibler Anmeldedaten
- **Lokaler Cache** zur Unterstützung einer schnellen Medienansicht

Die konkrete Architektur wird während der Entwicklung festgelegt. Sicherheit, zuverlässige Synchronisierung und eine gute Bedienbarkeit haben dabei Vorrang.

## Entwicklungsplan

Die Entwicklung soll in überschaubaren Schritten erfolgen:

- [x] Grundgerüst der SwiftUI-App
- [ ] Serveradresse und Verbindung einrichten
- [ ] Anmeldung und sichere Sitzungsspeicherung
- [ ] Foto- und Video-Timeline
- [ ] Detailansicht und Videowiedergabe
- [ ] Alben und Favoriten
- [ ] Cache und Performance-Optimierung

## Projektstatus

<badge>Konzeptphase</badge>

Lilith befindet sich noch am Anfang der Entwicklung. Es gibt derzeit keine veröffentlichte, installierbare Version. Sobald ein erster funktionsfähiger Stand existiert, werden hier Screenshots, Einrichtungshinweise und weitere technische Informationen ergänzt.

## Voraussetzungen

Für die geplante Nutzung wird ein erreichbarer Immich-Server benötigt. Die App soll mit einer bestehenden Immich-Instanz und einem dort eingerichteten Benutzerkonto arbeiten.

Weitere Mindestversionen und Build-Anleitungen werden ergänzt, sobald die technische Basis feststeht.

## Lizenz und Nutzung

Für dieses Repository wurde derzeit **keine Lizenz** hinterlegt. Es gelten daher die standardmäßigen urheberrechtlichen Bestimmungen. Das Einsehen des Quellcodes ist keine pauschale Erlaubnis zur Nutzung, Änderung oder Weiterverbreitung.

---

<div align="center">
  <sub>Lilith – ein unabhängiges SwiftUI-Projekt für die eigene Immich-Bibliothek.</sub>
</div>

## Entwicklung

Den vollständigen, freigegebenen Plan findest du in [docs/PLAN.md](docs/PLAN.md).

Voraussetzungen: Xcode 26 oder neuer und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd App && xcodegen && open Lilith.xcodeproj
```

Die Logik liegt im Swift Package `Packages/LilithKit`. Tests laufen mit `swift test` in diesem Ordner.

Neue Immich-Endpunkte nutzen: in `Packages/LilithKit/Sources/ImmichAPI/openapi-generator-config.yaml` eintragen und `scripts/generate-api.sh` ausführen.
Tests gegen einen echten Server: `LILITH_LIVE_SERVER=https://dein-server swift test` im Ordner `Packages/LilithKit`.
