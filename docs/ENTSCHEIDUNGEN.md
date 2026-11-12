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
- **Ladezeit nach Sprüngen (gemessen 11.11.2026):** Gemessen wurde mit leerem Cache, wie lange es nach einem Scrubber-Sprung über rund vier Jahre dauert, bis alle sichtbaren Kacheln ein Foto zeigen (iPhone-Simulator, echter Server).

  | | Monat geladen | Alle Fotos sichtbar |
  |---|---|---|
  | vorher | 0,37–0,40 s | 6,5 s |
  | nachher | 0,24–0,35 s | **1,1–1,2 s** |

  Was geholfen hat:
  1. Das kleine Vorschaubild hat hohe Priorität. Das scharfe startet erst danach und mit niedriger Priorität, statt beide gleichzeitig.
  2. Überflogene Monate werden nicht geladen: kurze Wartezeit von 120 ms und nur Monate in der Nähe des Sichtbaren. Laufende Anfragen für verlassene Monate werden abgebrochen.
  3. Vorladen für die alte Position wird beim Sprung gestoppt.
- **Noch kein Offline-Spiegel:** Die Monatsdaten liegen nur im Arbeitsspeicher. Die Datenbank (GRDB) für einen Offline-Spiegel und schnelleren Start folgt als eigener Schritt.

## 3. Detailansicht (Schritt 5, 11.11.2026)

- **Öffnen:** Antippen im Grid (auf dem Mac Doppelklick) öffnet das Foto über der Bibliothek, mit Zoom-Übergang aus der Kachel. Schließen: Zurück-Knopf, nach unten ziehen oder Esc.
- **Blättern:** Es werden nie alle Fotos als Seiten angelegt, sondern ein Fenster von 40 Fotos vor und nach dem aktuellen. Kommt man dem Rand nahe, wird das Fenster neu um das aktuelle Foto gelegt. Monate, die dabei erreicht werden, lädt die App sofort nach.
- **Bilder:** Erst das kleine Vorschaubild (meist schon im Cache), dann Immichs „preview“ (ca. 1440 px). Das Original wird nur zum Teilen geladen, noch nicht beim Hineinzoomen.
- **Videos:** `AVPlayer` mit Anmelde-Headern über Immichs Wiedergabe-Adresse. Geprüft gegen den echten Server.
- **Live Photos:** Der „Live“-Knopf spielt das zugehörige kurze Video einmal über dem Foto ab.
- **Favorit:** Wird sofort angezeigt und dann an den Server geschickt. Bei einem Fehler wird die Anzeige zurückgestellt.
- **Teilen:** Die Originaldatei wird erst geladen, wenn wirklich geteilt wird.
- **Datumsangaben:** Immich schickt Zeitpunkte mit und ohne Sekundenbruchteile. Beides wird gelesen (vorher konnte das Laden von Nutzerdaten daran still scheitern).

**Offen:** Original in voller Auflösung beim starken Hineinzoomen, Löschen/Archivieren (Schritt 6), nach oben wischen für das Info-Panel.

## 4. Alben, Favoriten, Archiv, Papierkorb (Schritt 6, 11.11.2026)

- **Eine Timeline für alles:** Bibliothek, Favoriten, Archiv, Papierkorb und jedes Album nutzen dieselbe Ansicht (`TimelineInhalt`) mit einem Filter. Immich liefert für alle dieselben Monats-Abfragen, nur mit anderen Parametern. Scrubber, Detailansicht und Auswahl gibt es dadurch überall.
- **Mehrfachauswahl:** Auf iPhone und iPad über „Auswählen“, dann Antippen. Auf dem Mac wie im Finder mit Klick, ⌘-Klick und ⇧-Klick. Auswahl per Wischen über mehrere Fotos fehlt noch.
- **Aktionen:** Favorit, Archivieren, Zu Album (vorhandenes oder neues), Löschen. Im Papierkorb: Wiederherstellen und endgültig Löschen. Löschen fragt immer nach. Ist der Papierkorb auf dem Server aus, sagt die Frage, dass endgültig gelöscht wird.
- **Nach einer Aktion** lädt die betroffene Ansicht neu und meldet die Änderung, damit auch die anderen Ansichten (z. B. die Bibliothek) neu laden.
- **Veraltete Schnittstelle:** Das Ändern mehrerer Fotos (`PUT /assets`) ist in Immich v3 als veraltet markiert, einen Nachfolger gibt es in v3.3.5 aber noch nicht.

**Offen:** Fotos aus einem Album entfernen, Alben umbenennen und löschen, Papierkorb leeren, geteilte Alben getrennt anzeigen, Auswahl per Wischen.

## 5. Smart Search (Schritt 7, 11.11.2026)

- **Suche in normaler Sprache** über Immichs `POST /search/smart`. Der Suchen-Tab zeigt Beispiele zum Antippen. Ist Machine Learning auf dem Server aus, erklärt die App das, statt ein leeres Suchfeld zu zeigen.
- **Ergebnisse als Timeline ohne Monate:** Die Treffer stehen nach Relevanz in einem einzigen Abschnitt und nutzen dieselbe Ansicht wie die Bibliothek. Detailansicht, Auswahl und Aktionen funktionieren dadurch auch in den Suchergebnissen.
- **Feste Obergrenze von 500 Fotos:** Smart Search liefert immer die ähnlichsten Fotos, keine exakte Trefferzahl. Die Schnittstelle hat in v3.3.5 kein Weiterblättern mehr (die Seitenzahl ist veraltet), deshalb holt Lilith einmal 500 Stück.

**Offen:** Filter (Zeitraum, Ort, Person, nur Videos), Suche nach Dateiname oder Text im Bild (OCR), letzte Suchen merken.

## 6. Mac und iPad (Schritt 8, 12.11.2026)

- **Anmeldung auf dem Mac:** Der moderne Schlüsselbund braucht auf dem Mac eine Signatur mit Apple-Entwicklerkonto (sonst Fehler -34018). Lilith nimmt dann den klassischen Mac-Schlüsselbund. Auf iPhone und iPad bleibt es beim modernen.
- **Tastatur auf dem Mac:** Pfeiltasten bewegen die Auswahl im Grid (⇧ erweitert sie), Leertaste oder Return öffnet das Foto, Esc schließt. F markiert als Favorit, ⌫ löscht (mit Rückfrage). ⌘1/⌘2/⌘3 wechseln zwischen Bibliothek, Alben und Suche, ⌘F öffnet die Suche. Die Pfeiltasten sind selbst gebaut, weil `NSCollectionView` mit dem verwendeten Layout die Richtung nicht berechnen kann.
- **Fotos herausziehen:** Auf dem Mac in Finder, Mail und andere Apps (als „Datei-Versprechen“: das Original wird beim Ziehen geladen und beim Loslassen geschrieben). Auf dem iPad als Datei in andere Apps.
- **Quick Look:** Statt Apples Quick-Look-Fenster öffnet die Leertaste die eigene Detailansicht, weil die Fotos auf dem Server liegen und nicht als Datei auf dem Mac.

**Offen:** Die Detailansicht deckt auf dem Mac die Seitenleiste nicht ab, und rechts erscheint ein schwarzer Rand. Fotos in Lilith hineinziehen (Upload) kommt mit dem Backup-Schritt. Pfeiltasten auf dem iPad mit Tastatur.

## 7. Feinschliff (Schritt 9, 12.11.2026)

- **Detailansicht über dem ganzen Fenster:** Sie liegt jetzt eine Ebene über der Tab- bzw. Seitenleiste. Damit deckt sie auf dem Mac auch die Seitenleiste ab, und der schwarze Rand rechts ist weg.
- **Offline:** Lädt die Bibliothek nicht neu, weil der Server nicht antwortet, bleiben die schon geladenen Fotos sichtbar. Oben erscheint ein Hinweis mit „Erneut“. Eine Fehlerseite kommt nur, wenn noch gar nichts geladen war.
- **App-Sperre:** In „Konto“ einschaltbar. Lilith sperrt sich beim Verlassen und entsperrt mit Face ID, Touch ID oder dem Gerätecode. Beim Einschalten wird einmal geprüft, ob das Entsperren klappt, damit man sich nicht aussperrt.
- **Sichtschutz:** Auf iPhone und iPad zeigt der App-Umschalter ein neutrales Bild statt der Fotos (auch ohne App-Sperre).
- **Bewegung reduzieren:** Ist es in den Bedienungshilfen eingeschaltet, blendet die Detailansicht nur ein statt zu zoomen, und der Mond beim Anmelden springt ohne Animation.
- **TestFlight vorbereitet:** Berechtigungstexte, Datenschutz-Manifest, Verschlüsselungsangabe, Team-ID über `LILITH_TEAM`. Anleitung in `docs/TESTFLIGHT.md`.
