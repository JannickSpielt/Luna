# Lilith – Gesamtplan

Stand: 11.11.2026 · Version 2 des Plans · Status: **freigegeben am 11.11.2026** (offene Entscheidungen: jeweils der Vorschlag)

Lilith ist eine native SwiftUI-App für **iPhone, iPad und Mac**, die auf einen bestehenden Immich-Server zugreift. Kein eigener Server, keine eigene Cloud.

**Designvorschau:** https://claude.ai/artifact/JBsTyt51K4PKVMfLgvA72C (nur zum Ansehen des geplanten Looks, kein App-Code)

**Neu in Version 2:** Mac-App, dein Server (v3.3.5) als Referenz, 16 neue Ideen (Abschnitt 3).

---

## 1. Rahmen

| Punkt | Vorschlag |
|---|---|
| Plattform | iOS / iPadOS **18+** und **macOS 15+**, eine echte Mac-App (kein „iPad-App auf dem Mac“) |
| Sprache | Swift 6 mit strikter Concurrency von Anfang an |
| Immich-Server | **nur v3.x**. Dein Server läuft mit **v3.3.5**, damit wird entwickelt und getestet. Ältere Server bekommen beim Verbinden den Hinweis „Server zu alt“. |
| Repo | JannickSpielt/Lilith, wird lokal geklont, sobald der Plan freigegeben ist |

## 2. Funktionen

### Version 1.0 (MVP): Fotos zuverlässig ansehen und verwalten
1. **Verbindung:** Serveradresse eingeben, Verbindung und Version prüfen, Hilfe bei selbstsignierten Zertifikaten
2. **Login:** E-Mail und Passwort, API-Key als Expertenoption, Token im Keychain
3. **Timeline:** alle Fotos und Videos chronologisch, Datumsüberschriften, Scrubber am Rand, Zoomstufen per Pinch
4. **Detailansicht:** Fotos zoomen, Videos abspielen, Live Photos, Info-Panel (Datum, Kamera, Karte), Teilen
5. **Alben:** ansehen, anlegen, Fotos hinzufügen
6. **Favoriten, Archiv, Papierkorb**
7. **Smart Search:** Suche in normaler Sprache („Hund am Strand“), wenn Machine Learning auf dem Server läuft
8. **Cache:** Vorschaubilder und Daten lokal gespeichert, damit Scrollen flüssig ist und die App auch offline etwas zeigt

### Version 1.x
- Upload und Backup aus der Fotomediathek, zuerst manuell, dann im Hintergrund, mit Live Activity für den Fortschritt
- Share Extension („In Lilith hochladen“ aus jeder App)
- OAuth/SSO-Login (Authentik, Authelia usw.)
- Personen und Gesichter, Karte, Erinnerungen („Heute vor X Jahren“)
- Geteilte Links erstellen, Partner-Sharing, Gesperrter Ordner mit Face ID
- Widgets (Foto des Tages, Erinnerungen)

### Später oder vielleicht
Bearbeitung, OCR-Overlay, Stacks, Personen verwalten, mehrere Server in der Oberfläche, Siri/Shortcuts, SharePlay, visionOS

## 3. Neue Ideen (vom Ideen-Subagent)

**Vorschlag für 1.0** (wenig Aufwand oder großer Alltagsnutzen):

| Idee | Was sie macht | Plattform |
|---|---|---|
| **Mondphasen-Verbindung** | Erkennt, ob du im Heimnetz, unterwegs oder per Tailscale/VPN bist, und wechselt automatisch zwischen interner und externer Server-Adresse. Ein kleiner Mond zeigt den Weg: voll = Heimnetz, Sichel = unterwegs, Neumond = offline. | alle |
| **Drag & Drop + Quick Look** | Fotos aus Lilith in Finder, Mail oder Keynote ziehen. Dateien aus dem Finder hineinziehen. Leertaste öffnet Quick Look. | Mac, iPad |
| **Tastatursteuerung** | J/K blättern, F für Favorit, ⌫ für Papierkorb, ⌘F für Suche, ⌘K Befehlspalette, mehrere Fenster | Mac, iPad |
| **Datenschutz-Check** | Warnt vor dem Teilen, wenn GPS-Daten oder Gesichter drin sind. Metadaten auf Wunsch entfernen. App-Sperre mit Face ID/Touch ID, unscharfes Bild im App-Umschalter. | alle |

**Vorschlag für 1.x:**

| Idee | Was sie macht | Plattform |
|---|---|---|
| **Nachtwache** | Server-Status: Erreichbarkeit, Version, dein Speicherverbrauch. Admins sehen auch laufende Jobs und Gesamtstatistik. | alle |
| **Menüleisten-Rose** | Mond-Symbol in der Mac-Menüleiste: Upload-Fortschritt, Serverstatus, Dateien hineinziehen, „Heute vor X Jahren“ | Mac |
| **Ordnerwächter** | Beobachtet Ordner (SD-Karte, Bildschirmfotos, Downloads) und lädt neue Fotos automatisch hoch, optional in ein festes Album | Mac |
| **Handoff & Continuity Camera** | Foto auf dem iPhone ansehen, auf dem Mac weitermachen. Am Mac mit dem iPhone fotografieren und direkt hochladen. | alle |
| **Abendvorführung** | Diashow mit Ken-Burns-Effekt per AirPlay auf den Fernseher, später eigene Apple-TV-App | iOS, Mac, später tvOS |
| **StandBy-Bilderrahmen** | Widget für StandBy, zeigt Erinnerungen. Nachts automatisch rot getönt. | iPhone |
| **Control-Center-Schalter** | „Backup jetzt“, „Backup pausieren“, Action Button | iPhone |
| **Focus-Filter** | Im Fokus „Arbeit“ private Alben ausblenden, im Fokus „Familie“ das Familienalbum zeigen | iOS, Mac |
| **Albumgeflüster** | Likes und Kommentare in geteilten Alben, mit Mitteilungen | alle |
| **Dubletten-Gärtner** | Doppelte Fotos per Wischen aussortieren, auf dem Mac nebeneinander vergleichen | alle |

**Später:**
- **Briefe an die Zukunft:** ein Album mit Notiz versiegeln, es öffnet sich erst an einem bestimmten Datum, z. B. zum 18. Geburtstag.
- **Jahresrose:** ein automatischer Jahresrückblick mit Statistik und Kapiteln, teilbar als Video.

## 4. Mac-App

- **Echte Mac-App** mit SwiftUI, kein iPad-Port. Fühlt sich an wie eine Mac-App: Seitenleiste, Toolbar mit Suchfeld, Info-Spalte rechts, Menüs, Tastaturkürzel, mehrere Fenster.
- **Gemeinsamer Code:** Netzwerk, Datenbank, Sync, Bilder und die meisten Bildschirme teilen sich iPhone, iPad und Mac. Nur Grid und ein paar Bedienelemente bekommen je Plattform eine eigene Umsetzung.
- **Mac-Extras in 1.0:** Drag & Drop mit dem Finder, Quick Look mit der Leertaste, Tastatursteuerung, „Original exportieren“ in einen Ordner
- **Mac-Extras in 1.x:** Menüleisten-Rose, Ordnerwächter, Continuity Camera

## 5. Design

- **Navigation iPhone:** Tab Bar mit den Tabs **Bibliothek · Erinnerungen · Alben · Suche**. Einstellungen liegen hinter dem Avatar oben rechts. (Der Tab „Erinnerungen“ ist in 1.0 noch ausgeblendet.)
- **Navigation iPad:** Sidebar mit angepinnten Alben, optional eine Info-Spalte, Tastaturkürzel, Drag & Drop
- **Navigation Mac:** Fenster mit Seitenleiste (Bibliothek, Favoriten, Archiv, Papierkorb, Alben, Ordnerwächter), Suchfeld in der Toolbar, Info-Spalte rechts
- **Look:** nächtlich, ruhig und warm. Akzentfarbe „Nachtrose“ (Granatrot, etwa #B0305A) mit Mondlicht-Ton. Dark Mode ist das Herzstück. Für große Titel eine Serif-Schrift (New York). Liquid Glass nur bei Leisten, nie über Fotos.
- **Icon-Idee:** schmale Mondsichel, die zugleich eine Kamerablende ist
- **Gesten:** Mehrfachauswahl durch Wischen, Zoom-Übergang vom Grid ins Foto, nach unten wischen zum Schließen, sparsame Haptik
- **Zustände:** Platzhalter in der Farbe des Fotos statt Ladekreisel. Offline-Banner, der Cache bleibt nutzbar. Bei abgelaufener Anmeldung erscheint ein Sheet, ohne Rauswurf.
- **Barrierefreiheit:** Dynamic Type, VoiceOver mit Datum, Ort und Personen, Reduce Motion, Reduce Transparency
- **Besondere Momente:** Mondsichel füllt sich zum Vollmond, sobald der Server antwortet. Favoriten-Glühen. Später das Jahresrückblick-Feature „Lilith Nights“.

## 6. Technik

| Bereich | Entscheidung | Warum |
|---|---|---|
| Aufbau | Schlankes Xcode-Projekt mit **zwei App-Targets (iOS/iPadOS und macOS)** plus lokales Swift Package `LilithKit` mit Modulen, die beide nutzen | schnelle Builds, sauber getrennt, gut testbar, viel gemeinsamer Code |
| Architektur | `@Observable`-Stores plus Services, Abhängigkeiten über `@Environment` (kein TCA) | Apple-nativ, wenig Boilerplate, gute Kontrolle beim Grid |
| Netzwerk | Aus der Immich-OpenAPI-Spec generiert (swift-openapi-generator, nur genutzte Endpunkte), dahinter eine eigene Fassade `ImmichClient` | Änderungen an der Immich-API betreffen nur eine Stelle |
| Server-Fähigkeiten | Version und Features beim Verbinden abfragen, Funktionen danach ein- oder ausblenden | ML, Papierkorb usw. können auf dem Server abgeschaltet sein |
| Datenbank | **GRDB (SQLite)** statt SwiftData | zuverlässig bei 100.000+ Fotos |
| Sync | 1.0: Timeline-Buckets, beim Scrollen nachgeladen und gespeichert. 1.x: Sync-Stream für einen vollständigen lokalen Spiegel | einfach starten, später robust erweitern |
| Bilder | **Nuke** für Laden, Cache und Prefetching. Thumbhash als sofortiger Platzhalter. Stufen: Thumbnail → Preview → Original | erprobt, spart Eigenbau |
| Grid | `UICollectionView` (iPhone/iPad) und `NSCollectionView` (Mac), in SwiftUI eingebettet, hinter einer gemeinsamen Schnittstelle. Wird zuerst mit 100.000 Testfotos geprüft. | `LazyVGrid` stößt bei riesigen Bibliotheken an Grenzen |
| Verbindung | Mehrere Adressen pro Server (intern/extern), automatische Wahl nach Netzwerk (Mondphasen-Verbindung) | Homelab-Alltag |
| Video | `AVPlayer` mit Auth-Header, Fallback über Resource Loader (für selbstsignierte Zertifikate) | |
| Konten | Datenmodell kann ab Tag 1 mehrere Konten, die Oberfläche zeigt zuerst nur eins | spätere Erweiterung ohne Umbau |
| Tests / CI | Swift Testing, GitHub Actions (Build, Tests, Lint), wöchentlicher Check auf neue Immich-API-Versionen | |

Ordnerstruktur:
```
Lilith/
├─ App/                     # Xcode-Projekt: iOS- und macOS-Target, Assets, Entitlements
├─ Packages/LilithKit/
│  └─ Sources/
│     ├─ ImmichAPI/         # generierter API-Code + Spec
│     ├─ Networking/        # ImmichClient, Login, Zertifikate, Server-Fähigkeiten
│     ├─ Persistence/       # GRDB-Datenbank
│     ├─ Sync/
│     ├─ Media/             # Bilder, Thumbhash, Video
│     ├─ DesignSystem/      # Farben, Schriften, Komponenten
│     └─ Features/          # Login, Timeline, Detail, Alben, Suche, Einstellungen
└─ .github/workflows/
```

## 7. Reihenfolge der Umsetzung (Version 1.0)

1. **Grundgerüst:** Projekt mit iOS- und Mac-Target, Package, CI, Design-System (Farben, Schriften)
2. **Verbindung und Login:** Server prüfen, anmelden, Keychain, interne/externe Adresse
3. **Grid-Prototyp mit 100.000 Testfotos** auf iPhone und Mac: Hier fällt die wichtigste Technikentscheidung.
4. **Echte Timeline:** Buckets, Thumbnails, Cache, Scrubber, Zoomstufen
5. **Detailansicht:** Fotos, Videos, Live Photos, Info-Panel
6. **Alben, Favoriten, Archiv, Papierkorb**
7. **Smart Search**
8. **Mac- und iPad-Extras:** Drag & Drop, Quick Look, Tastatursteuerung
9. **Feinschliff:** Offline- und Fehlerzustände, Datenschutz-Check, Barrierefreiheit, TestFlight

## 8. Größte Risiken

1. **Immich ändert seine API oft** (v3.0 hat viel gebrochen). Gegenmittel: Fassade, Feature-Abfrage und CI-Check.
2. **Flüssiges Scrollen bei riesigen Bibliotheken.** Gegenmittel: früher Prototyp (Schritt 3).
3. **Videos und selbstsignierte Zertifikate.** AVFoundation ist dabei zickig, dafür Zeit einplanen.
4. **Hintergrund-Upload** (1.x): iOS begrenzt Hintergrundarbeit stark. Ein Backup „wie iCloud“ ist schwer.
5. **App-Store-Review** braucht einen Demo-Zugang (z. B. demo.immich.app).
6. **Drei Plattformen = mehr Arbeit.** Die Mac-App braucht ein eigenes Grid und eigene Bedienung. Gegenmittel: so viel gemeinsamer Code wie möglich, Mac-Extras gestaffelt.

## 9. Offene Entscheidungen für dich

- [ ] **OAuth-Login schon in 1.0** oder erst in 1.x? (Vorschlag: 1.x. Wenn dein Server über Authentik/Authelia läuft, besser 1.0.)
- [ ] **iOS 18 / macOS 15** als Minimum okay? (Alternative: iOS 26 / macOS 26, dann wäre Liquid Glass überall nativ, aber weniger Geräte)
- [ ] **Mac-App gleichzeitig mit 1.0** oder kurz danach? (Vorschlag: gleichzeitig, weil der meiste Code geteilt ist)
- [ ] **Welche neuen Ideen** sollen rein? (Vorschlag: die vier aus „Vorschlag für 1.0“)
- [ ] **Upload/Backup erst in 1.x** okay?
- [ ] **Design-Richtung „Nachtrose“** (Granatrot, Mond, Serif-Titel) okay?
- [ ] Soll ich nach der Freigabe die README im Repo an diesen Plan anpassen?
