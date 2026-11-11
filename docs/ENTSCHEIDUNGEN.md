# Technische Entscheidungen

## 1. Grid-Technik für die Timeline (Schritt 3, 11.11.2026)

**Entscheidung:** Die Timeline nutzt ein natives Grid: `UICollectionView` auf iPhone und iPad, `NSCollectionView` auf dem Mac, beide mit Compositional Layout und in SwiftUI eingebettet (`TimelineGridView`). Reines SwiftUI (`LazyVGrid`) wird nicht verwendet.

**Warum:** Der Prototyp mit 100.000 erfundenen Fotos (180 Monate) hat beide Varianten verglichen. Gemessen wurde mit einem optimierten Build im Simulator (iPhone 18 Pro) und auf dem Mac.

| Messung | Nativ | SwiftUI `LazyVGrid` |
|---|---|---|
| iPhone: Sprung zum ältesten Monat | landet am Ende (99 %), einmal 130 ms Stocken | **landet nicht**: bleibt am Anfang (0 %) |
| Mac: Sprung zum ältesten Monat | landet am Ende | nicht verlässlich gemessen |
| Bildrate beim Scrollen | 60 fps | 55–60 fps, mehr Ruckler |
| Speicher | 29 MB (iPhone), 44 MB (Mac) | 26 MB (iPhone), 41 MB (Mac) |
| Testdaten erzeugen | 70–140 ms für 100.000 Einträge | gleich |

Der Sprung ist entscheidend, weil Scrubber, „Heute vor X Jahren“ und Suchergebnisse beliebig weit in die Vergangenheit springen müssen. Das kann `LazyVGrid` bei dieser Datenmenge nicht zuverlässig.

**Weitere Festlegungen:**
- **Kein Diffable Data Source.** Die Anzahl pro Monat ist durch Immichs Timeline-Buckets vorab bekannt, Inhalte werden erst beim Anzeigen geladen. Ein klassischer Data Source passt dazu besser und vermeidet Snapshots mit 100.000+ Einträgen.
- **Pinch-Zoom in Stufen**: iPhone 1/3/5/7/11, iPad 3/5/7/10/14, Mac 4/6/8/12/18 Spalten. Das Foto unter den Fingern bleibt an seinem Platz. Auf dem Mac geht das auch mit ⌘+ und ⌘−.
- **Zellen bleiben schlank** (UIKit/AppKit-Views statt SwiftUI in jeder Zelle), damit auch bei 18 Spalten nichts ruckelt.

**Nachtrag Schritt 4:**
- Die doppelte Bibliothek auf dem Mac kam vom Prototyp-Aufbau. Seit die Timeline-Daten einmal pro Anmeldung angelegt werden, erscheint sie nur noch einmal.
- Die SwiftUI-Vergleichsvariante und die Messanzeige wurden nach der Entscheidung entfernt.
- Echte Messung auf einem iPhone und mit echten Vorschaubildern steht noch aus. Der Simulator ist nur ein Anhaltspunkt.

## 2. Laden der Timeline (Schritt 4, 11.11.2026)

- **Monate zuerst, Inhalt später:** Beim Öffnen lädt Lilith nur die Liste der Monate mit Anzahl (`/timeline/buckets`). Den Inhalt eines Monats (`/timeline/bucket`) holt sie erst, wenn das Grid ihn anzeigen will oder bald braucht.
- **Platzhalter:** Bis das Vorschaubild da ist, zeigt jede Kachel die Durchschnittsfarbe aus dem Thumbhash.
- **Vorschaubilder:** Nuke mit bis zu 1 GB Festplatten-Cache. Kleine Kacheln laden Immichs „thumbnail“ (ca. 250 px), große Kacheln (ab 320 px) die schärfere „preview“.
- **Noch kein Offline-Spiegel:** Die Monatsdaten liegen nur im Arbeitsspeicher. Die Datenbank (GRDB) für einen Offline-Spiegel und schnelleren Start folgt als eigener Schritt.
