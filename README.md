<!-- Swimmich | Project README -->

<div align="center">
  <img src="assets/swimmich-logo.svg" alt="Swimmich logo" width="160" />

  <h1>Swimmich</h1>
  <p><strong>Deine Immich-Fotobibliothek. Nativ auf iOS.</strong></p>
  <p>Ein unabhängiges SwiftUI-Projekt, das Immich mit einer speziell für iPhone und iPad entwickelten Oberfläche verbindet.</p>

  <p>
    <img src="https://img.shields.io/badge/platform-iOS%20%2F%20iPadOS-147EFB?style=flat-square" alt="iOS and iPadOS" />
    <img src="https://img.shields.io/badge/built%20with-SwiftUI-orange?style=flat-square&logo=swift&logoColor=white" alt="Built with SwiftUI" />
    <img src="https://img.shields.io/badge/status-Planning-8B8B8B?style=flat-square" alt="Planning" />
    <img src="https://img.shields.io/badge/backend-Immich-4250AF?style=flat-square" alt="Immich backend" />
  </p>
</div>

---

## Über Swimmich

Swimmich soll eine native iOS-App für bestehende **[Immich](https://immich.app/)-Server** werden. Statt eine eigene Foto-Cloud aufzubauen, nutzt die App die vorhandene Immich-Instanz und deren API.

Das Ziel: eine flüssige, auf Apple-Geräte abgestimmte Fotoverwaltung mit einer vertrauten Bedienung und direkter Verbindung zum eigenen Server.

> **Hinweis:** Swimmich ist ein unabhängiges Community-Projekt und kein offizielles Produkt des Immich-Teams.

## Geplant

| Bereich | Geplante Funktionen |
| --- | --- |
| Verbindung | Eigene Immich-Serveradresse eintragen |
| Anmeldung | Anmeldung mit dem bestehenden Immich-Konto |
| Timeline | Fotos und Videos chronologisch durchsuchen |
| Medienansicht | Fotos im Vollbild ansehen und Videos abspielen |
| Alben | Alben anzeigen und verwalten |
| Favoriten | Lieblingsfotos schnell wiederfinden |
| Später | Suche, Erinnerungen und lokaler Cache |

Die Funktionen sind geplant und noch nicht als verfügbar zu verstehen.

## Technischer Ansatz

- **Swift** als Programmiersprache
- **SwiftUI** für eine native Benutzeroberfläche
- **Immich REST API** für die Kommunikation mit dem Server
- **Keychain** für die sichere Aufbewahrung von Sitzungstokens
- **Lokaler Cache** für eine schnelle und zuverlässige Medienansicht

API-Dokumentation: [api.immich.app](https://api.immich.app/)

## Projektstatus

Swimmich befindet sich in der frühen Planungsphase. Der erste Meilenstein ist eine zuverlässige Verbindung zu einem selbst gehosteten Immich-Server.

- [ ] Projektgrundlage in SwiftUI
- [ ] Serveradresse konfigurieren
- [ ] Anmeldung und Sitzungsverwaltung
- [ ] Foto- und Video-Timeline
- [ ] Detailansicht für Medien
- [ ] Alben und Favoriten
- [ ] Caching und Performance

## Entwicklung

Sobald die erste lauffähige Projektversion bereitsteht, werden hier die Voraussetzungen, Einrichtung und Entwicklungsanleitung ergänzt.

## Lizenz und Nutzung

Für dieses Repository wurde derzeit **keine Lizenz** hinterlegt. Es gelten daher die standardmäßigen urheberrechtlichen Bestimmungen. Eine öffentliche Nutzung, Weiterverbreitung oder Änderung wird durch dieses Repository nicht pauschal gestattet.

---

<div align="center">
  <sub>Made with Swift · Designed for your own photo library</sub>
</div>
