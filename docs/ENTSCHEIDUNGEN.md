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

## 8. Upload per Hand (Backup-Etappe 1, 12.11.2026)

Plan: `docs/BACKUP-PLAN.md`.

- **Datenbank (GRDB):** Neues Modul `Persistence`. Jeder Upload ist ein Auftrag mit Zustand (wartet, läuft, fertig, Duplikat, Fehler), Prüfsumme, Versuchen und Server-ID. Nach einem Absturz setzt Lilith laufende Aufträge auf „wartet“ zurück und macht weiter.
- **Kopie statt Verweis:** Ausgewählte Dateien werden nach `Application Support/Lilith/Uploads` kopiert und nach dem Upload gelöscht. So geht der Upload auch nach einem Neustart weiter, obwohl die Foto-Auswahl nur kurz Zugriff gibt.
- **Duplikate vorab erkennen:** Lilith berechnet SHA1 (Base64) wie die offizielle Immich-App und fragt `bulk-upload-check`, bevor sie hochlädt. Was schon da ist, wird nicht noch einmal gesendet.
- **Upload aus einer Datei:** Der Multipart-Inhalt wird zuerst als Datei geschrieben und dann mit `URLSession.upload(fromFile:)` gesendet. So bleibt der Speicher klein, der Fortschritt ist sichtbar, und Etappe 3 kann dieselbe Datei im Hintergrund hochladen.
- **Wo der „+“ erscheint:** In der Bibliothek und in Alben (dort landen die Fotos direkt im Album). Nicht in Favoriten, Archiv und Papierkorb. Auf dem Mac: Fenster als Ablagefläche und „Importieren …“ (⌘I), auch für Ordner.
- **Fehler:** Abgelaufene Anmeldung und volles Kontingent halten die Warteschlange an. Server nicht erreichbar: Anhalten, bei nächster Gelegenheit neu versuchen, nach 5 Versuchen Fehler. Zu große Datei (413) erklärt den Reverse-Proxy. Gescheiterte Dateien lassen sich erneut versuchen oder verwerfen.
- **Fotos nur in iCloud:** Die Foto-Auswahl liefert sie ggf. nicht. Lilith meldet dann, wie viele fehlen.

**Offen:** Live Photos werden über die Foto-Auswahl noch als einzelnes Foto hochgeladen (Live-Paar kommt mit Etappe 2). Ablegen auf ein Album in der Mac-Seitenleiste. Live Activity.

## 9. Backup bei geöffneter App (Backup-Etappe 2, 12.11.2026)

- **Nur iPhone und iPad.** Auf dem Mac bleibt es beim Hochladen per Hand (Entscheidung im Backup-Plan).
- **Ablauf:** Mediathek lesen (nur Kopfdaten) → mit der Datenbank abgleichen → Prüfsumme pro Foto → beim Server nachfragen (100 auf einmal) → nur Fehlendes exportieren und hochladen. Was der Server schon hat, wird gar nicht erst exportiert.
- **Prüfsumme der aktuellen Version:** Bei bearbeiteten Fotos die bearbeitete Datei, sonst das Original, als SHA1 (Base64) stückweise aus PhotoKit. Wird ein Foto später bearbeitet, prüft Lilith es neu.
- **Abgleich statt Änderungsabfrage:** Lilith liest bei jedem Durchgang die Liste aller Fotos (auch bei großen Mediatheken nur Sekunden) und vergleicht mit der Datenbank. Das ist einfacher und robuster als iOS' Änderungsabfrage. Die kommt erst, falls es zu langsam wird.
- **Blöcke von 20:** Es werden höchstens 20 Fotos auf einmal exportiert. So liegen nie viele Kopien auf dem Gerät.
- **Live Photos:** Das Video geht zuerst versteckt hoch, danach das Foto mit Verweis darauf, wie bei der offiziellen Immich-App.
- **Nur in iCloud:** Originale, die nicht auf dem Gerät liegen, werden in dieser Etappe übersprungen und gezählt. Laden aus iCloud kommt mit Etappe 3.
- **Wann:** Beim Öffnen der App, beim Zurückkehren in die App und mit „Jetzt prüfen“. Geht die App in den Hintergrund, hält das Backup an.
- **Anzeige:** Konto-Kreis mit Mond-Ring (füllt sich mit dem Fortschritt, Wolke = angehalten, roter Rand = Fehler). Im Konto eine Statuskarte: „8.412 von 9.030 gesichert“, Statuszeile mit Grund, Fehler erneut versuchen, „Auswahl ändern“ bei eingeschränktem Zugriff.
- **Prüfen ohne echten Upload:** Mit dem Startargument `-LilithBackupVorschau YES` zeigt die App feste Beispielzahlen.

**Offen:** Hinweis-Banner in der Bibliothek („Fotos von diesem iPhone sichern?“), Einstellungen (WLAN, Laden, Videos, Alben) und Hintergrund kommen mit Etappe 3, die Fehlerliste mit Etappe 4.

## 10. Feinschliff, Albenauswahl, nicht gesicherte Fotos (12.11.2026)

- **Kompakte Leiste:** Oben nur noch „+“, Ansicht-Menü und Konto. „Auswählen“ steht im Ansicht-Menü.
- **Auswählen per Wischen:** Im Auswahl-Modus Foto antippen, nach rechts und dann nach unten wischen. Das ist UIKits eingebaute Mehrfachauswahl (wie in Fotos), mit zwei Fingern auch ohne Auswahl-Modus.
- **Profilbild** vom Server (`/users/{id}/profile-image`). Ohne Bild bleibt der Anfangsbuchstabe.
- **Scrubber ruckelte:** Die Scroll-Position lag im Zustand der ganzen Bibliotheksansicht, die dadurch bis zu 120-mal pro Sekunde neu berechnet wurde. Jetzt liegt sie in einem eigenen Objekt, das nur der Scrubber liest.
- **Albenauswahl fürs Backup** (Plan Abschnitt 9 B): wie in der Immich-App einmal tippen = sichern, zweimal = ausschließen. Gespeichert pro Konto in den Einstellungen der App (klein, kein eigener Tabellenbedarf). Optional werden gewählte eigene Alben auf dem Server mit demselben Namen angelegt und gefüllt (Schalter, aus).
- **Nicht gesicherte Fotos in der Bibliothek** (Plan Abschnitt 9 A): Gezeigt wird, was laut Server fehlt (bereit, in der Warteschlange, Fehler, übersprungen). Noch ungeprüfte Fotos nicht, sonst stünden Fotos, die längst auf dem Server sind, kurz doppelt da. Sie werden nach Datum zwischen die Server-Fotos gemischt. Monate nur mit Fotos vom Gerät bekommen einen eigenen Abschnitt.
- **Datum der Server-Fotos:** Die Timeline liefert die Ortszeit ohne Zeitzone und mit wechselnden Nachkommastellen („2026-11-12T10:01:18.13“). Lilith liest sie als Ortszeit des Geräts.
- **Auswahl:** Fotos nur auf dem Gerät lassen sich nicht markieren (Favorit, Archiv, Löschen gehen erst nach dem Upload).
- **Prüfen ohne Upload:** `-LilithLokalVorschau YES` zeigt die Fotos der Mediathek als „nicht gesichert“, ohne etwas hochzuladen.

**Offen:** Videos vom Gerät zeigen in der Detailansicht nur das Standbild. Die Videodauer fehlt auf der Kachel.
- **Zittern beim Öffnen eines Fotos:** Während des Zooms füllte die Detailansicht nur den sicheren Bereich (ohne Statusleiste und Home-Leiste) und wuchs erst danach auf den ganzen Bildschirm. Das zentrierte Foto sprang dabei um einige Punkte. Jetzt hat die Detailansicht von Anfang an die volle Größe, nur die Knöpfe halten Abstand zu Notch und Home-Leiste. Die Statusleiste bleibt sichtbar (weiß auf Schwarz). Geprüft per Bildschirmaufnahme: Der Versatz nach dem Zoom ist in jedem Bild 0.
- **4 Fotos pro Reihe** sind auf dem iPhone jetzt Standard (Stufen 1, 3, 4, 5, 7, 11).
- **Kürzlich hinzugefügt** (im Alben-Tab, ganz oben): Was in den letzten 30 Tagen hochgeladen wurde, neueste zuerst, bis 1.000 Objekte. Immich kann nur nach Hochladezeit filtern (`createdAfter`), nicht sortieren. Lilith sortiert deshalb selbst.
- **Heller Modus in Weiß:** Statt des warmen Papiertons (#FAF5EE) ist der Hintergrund jetzt reines Weiß, Flächen wie Karten sind das iOS-übliche Hellgrau (#F2F2F7), die Schrift ist neutral statt bräunlich. Der Dunkelmodus bleibt unverändert.

## 11. Backup im Hintergrund (Backup-Etappe 3, 12.11.2026)

- **Uploads über eine Hintergrund-Session:** Jeder Upload läuft über `URLSession` mit Hintergrund-Konfiguration (`app.lilith.upload`). Geht die App in den Hintergrund, läuft der aktuelle Upload weiter. Zusätzlich übergibt Lilith bis zu 30 vorbereitete Aufträge an iOS, die ohne die App hochgeladen werden. Ausgenommen sind Live Photos, weil Video und Foto nacheinander gehen müssen.
- **Ergebnisse nach einem Neustart:** iOS weckt Lilith, wenn Hintergrund-Uploads fertig sind. Ergebnisse, die ankommen, bevor die Warteschlange bereit ist, werden gesammelt und nachgereicht. Beim Start bleiben Aufträge, die iOS noch hochlädt, auf „läuft“ und werden nicht doppelt gesendet.
- **BackupZentrale:** Warteschlange und Backup gibt es pro App-Start genau einmal, für die Oberfläche und für Läufe ohne Bildschirm. Ohne Oberfläche lädt sie die Anmeldung selbst aus dem Schlüsselbund (lesbar ab dem ersten Entsperren nach dem Neustart).
- **Läufe im Hintergrund:** nachts als `BGProcessingTask` (nur am Strom, mit Netz) und zwischendurch als `BGAppRefreshTask` (frühestens alle 2 Stunden). Jeder Lauf vergleicht, sichert und übergibt danach Uploads an iOS. Ist die Zeit um, hält er an und übergibt, was fertig vorbereitet ist.
- **Einstellungen:** Nur über WLAN (Voreinstellung), Nur beim Laden, Videos sichern, Originale aus iCloud laden. Ohne WLAN wird nur verglichen (wenige Daten), hochgeladen wird erst im WLAN. Die Uploads selbst verbieten Mobilfunk und Datensparmodus, damit das auch im Hintergrund gilt. Uploads per Hand gehen immer.
- **iCloud-Originale:** Werden einzeln geladen (eins nach dem anderen). Sind sie erlaubt, werden vorher übersprungene Fotos neu geprüft. Unter 1 GB freiem Speicher hält das Backup an.
- **Statuszeile:** „Wartet auf WLAN“, „Wartet auf Strom“ oder „Zu wenig Speicher frei“, der Mond-Ring zeigt dann die Wolke.

**Nicht geprüft:** Ob iOS die Läufe wirklich auslöst, lässt sich im Simulator nicht zuverlässig testen. Das zeigt erst ein echtes iPhone über ein paar Nächte. **Offen (Etappe 4):** „Jetzt sichern“ ab iOS 26, Live Activity, Fehlerliste, Vollmond-Moment.

## 12. Backup-Etappe 4 und Feinschliff (12.11.2026)

- **Fehlerliste:** Im Konto unter Backup („N nicht gesichert“) und nach Uploads per Hand („Details“). Pro Foto: Vorschau, Grund, „Erneut“, per Wischen „Ignorieren“ (wird dann nicht mehr gesichert, bis man es erneut versucht). Übersprungene (z. B. nur in iCloud) stehen in einem eigenen Abschnitt.
- **Vollmond-Moment:** Einmal pro Konto, wenn das erste Backup komplett ist (alles gesichert, keine Fehler): Der Mond geht auf, „Alles sicher. Gute Nacht.“ Mit „Bewegung reduzieren“ ohne Animation. Zum Ansehen: `-LilithVollmond YES`.
- **„Jetzt sichern“ (ab iOS 26):** Startet einen Durchgang als `BGContinuedProcessingTask`. Er läuft weiter, wenn man die App verlässt, iOS zeigt Titel und Fortschritt an. Unter iOS 26 bleibt es bei „Jetzt prüfen“. Jede Anfrage hat eine eigene Kennung (`app.lilith.Lilith.jetzt.*`).
- **Live Activity:** Ab 20 Fotos per Hand erscheint der Fortschritt auf dem Sperrbildschirm und in der Dynamic Island (eigene Widget-Erweiterung `LilithWidgets`, gemeinsames Modul `LiveAktivitaet`). Höchstens alle 1,5 Sekunden aktualisiert, nach dem Ende noch eine Minute sichtbar. Zum Ansehen: `-LilithLiveVorschau YES`.
- **Hilfeseite:** „So funktioniert das Backup“ steht in den Backup-Einstellungen (seit Etappe 3).
- **Foto öffnen ohne Zoom:** Der Zoom aus der Kachel blieb auf dem iPhone manchmal auf halbem Weg stehen. Jetzt blendet die Detailansicht schnell ein (0,18 s), und bis das Bild da ist, zeigt sie einen Lade-Mond statt einer leeren Fläche.
- **Videoplayer:** Apples voller Player (`AVPlayerViewController`) mit Vollbild, Bild-in-Bild, AirPlay und Geschwindigkeit. Er liegt zwischen den eigenen Leisten, damit sich die Bedienelemente nicht überdecken. Bis das erste Bild des Videos da ist, ist die Vorschau zu sehen.
- **Ladebildschirm beim Start:** Statt eines weißen Bildschirms zeigt iOS einen Nachthimmel mit dem Lilith-Mond (Asset `StartMond`, Farbe `StartFarbe`). Die App übernimmt genau dieses Bild, lässt den Mond zunehmen und „Lilith“ erscheinen, bis die Bibliothek geladen ist (höchstens 5 Sekunden), und blendet dann über.

**Nicht geprüft:** „Jetzt sichern“ und die Läufe im Hintergrund brauchen ein echtes Gerät mit iOS 26.

## 13. Redesign: Fotos zuerst, Liquid Glass maßvoll (12.11.2026)

Plan: `docs/REDESIGN-PLAN.md`. Vorbild: Apples Fotos-App mit Liquid Glass, ohne es zu überladen.

- **Schrift:** nur noch SF mit den Textstilen des Systems. Die Serife (New York) bei Monaten, Alben, Suche und Anmeldung ist weg.
- **Farbe:** Flächen und Text kommen vom System. Nachtrose (hell #C8102E, dunkel #FF4D6A) nur noch für gewählten Tab, Auswahl, Favorit und Hauptknopf. Symbole in Leisten sind einfarbig, Listen-Symbole grau, Schalter grün wie im System. Mondlicht nur für den Mond, auf Weiß kräftiger (#A8843E, 3,5 : 1).
- **„Fotos“ statt „Bibliothek“:** Der Tab heißt „Fotos“. Ein großer Titel fehlt bewusst: Der Tab sagt schon, wo man ist. Oben links steht stattdessen, was man sieht: Monat, Ort und Anzahl als Glas-Kapsel in derselben Reihe wie die Leiste rechts (im Auswahl-Modus die Anzahl der ausgewählten Fotos).
- **Fotos unter den Leisten:** Das Raster beginnt ganz oben und läuft unter Statusleiste, Leiste und Tab-Leiste durch. Ein weicher Verlauf oben hält die Leiste lesbar. Die grauen Monats-Bänder sind weg, Monate gehen mit derselben 2-pt-Fuge ineinander über.
- **Liquid Glass (ab iOS 26, sonst Material):** Leiste, Tab-Leiste, Monats-Kapsel, Knöpfe der Fotoansicht (klares Glas), Upload-Anzeige, Auswahl-Leiste, Offline-Hinweis. Bewusst ohne Glas: Scrubber, Listen, Karten, Album-Kacheln.
- **Ecken:** Album-Kacheln 10, Karten 12.
- **Reihenfolge wie in Apples Fotos-App (iPhone/iPad):** Das Neueste steht unten rechts, nach oben scrollt man in die Vergangenheit. Umgesetzt durch Drehen der Sammlung um 180° (die Zellen werden zurückgedreht), die Daten und Indizes bleiben unverändert. Die App öffnet ganz unten, solange man nicht selbst gescrollt hat. Scrubber und „Zum neuesten Monat“ springen ganz nach unten. Suchergebnisse bleiben von oben nach unten (Relevanz). „Ziehen zum Aktualisieren“ entfällt dort, neu laden geht über das Menü.
- **Pille oben links:** nur das Datum des Fotos am Rand (Tag, Monat, Jahr, z. B. „10. November 2026“), kein Ort, keine Anzahl. Exakt so hoch (44 pt) und auf derselben Höhe wie die Leiste rechts. Ganz unten zeigt sie die Gesamtzahl („3.571 Objekte“).
- **Tab-Leiste (iPhone):** wie in Apples Fotos-App: „Fotos“ und „Alben“ zusammen links, die Suche als eigener runder Knopf rechts (`tabViewSearchActivation(.searchTabSelection)`). In „Fotos“ verschwindet sie beim Scrollen in beide Richtungen und kommt nach 3 Sekunden Stillstand wieder. iPad und Mac behalten die Seitenleiste.
- **Ansicht-Menü** mit Apples Filtersymbol (`line.3.horizontal.decrease`) statt drei Punkten.

## 14. Feinschliff nach dem ersten Test am iPhone (12.11.2026)

Plan: `docs/FEINSCHLIFF-PLAN.md`.

- **Akzent Kirschrot:** hell #C8102E (5,9 : 1 auf Weiß), dunkel #FF4D6A (6,5 : 1 auf Schwarz), auch im AccentColor-Asset und in der Live-Aktivität.
- **Ton:** Videos schalten beim Abspielen auf `AVAudioSession.playback` (spielt auch im Stummmodus) und danach zurück, damit Musik weiterläuft. Live Photos bleiben im Stummmodus stumm.
- **Raster ohne Lücken:** eigenes `FliessLayout` statt Compositional Layout. Die Monate bleiben Sections, laufen aber ohne Umbruch ineinander (wie in Apples Fotos-App). Vorbereitete Kacheln werden beim Anzeigen nachgeladen, abgebrochene Monate beim Stehenbleiben. Der Platzhalter ist deckend grau.
- **Kachel-Zoom:** interaktiver Layout-Übergang (`startInteractiveTransition`) mit dem Pinch als Fortschritt. Die Kachel unter den Fingern bleibt stehen. Bildgrößen werden auf feste Stufen gerundet, und Kacheln behalten ihr Bild, bis das schärfere da ist.
- **Zoom im Foto:** UIKit-Pinch (`UIGestureRecognizerRepresentable`), weil SwiftUIs `MagnifyGesture` die Fingerposition nicht laufend liefert. Gezoomt wird um die Finger, Verschieben geht gleichzeitig. Doppeltippen zoomt auf die Stelle.
- **Teilen:** Das Teilen-Blatt öffnet sofort, `NSItemProvider` lädt das Original erst bei Bedarf. Originale werden je Foto wiederverwendet. Der Upload-Fortschritt wird in einer kleinen eigenen Ansicht beobachtet, damit nicht jedes Mal die ganze App neu rechnet.
- **Eigener Videoplayer (iOS):** `AVPlayerLayer` und eine Glas-Leiste (Abspielen, Zeitleiste, Ton, Bild-in-Bild, AirPlay). Sie blendet sich nach 3 s beim Abspielen aus. Hintergrundmodus „audio“ für Bild-in-Bild. Der Mac behält Apples `VideoPlayer`.
- **Start:** Die Mondsichel wird zum Vollmond (0,7 s), dann kommt der Mond näher und die App öffnet sich in seiner Mitte (0,8 s, Loch per gerade-ungerade gefülltem Pfad). Mit „Bewegung reduzieren“ wird nur überblendet. Der Sichtschutz für den App-Umschalter erscheint erst, wenn die App schon aktiv war (sonst flackerte es beim Start grau).

## 15. Die App heißt Luna (12.11.2026)

- Sichtbar heißt die App jetzt **Luna**: Name unter dem Symbol, Startbildschirm und Startbild, alle Texte in der App, Live-Aktivität, Hinweise für Fotos, Face ID und lokales Netzwerk.
- **Intern bleibt „Lilith“** als Code-Name: Bundle-ID `app.lilith.Lilith`, Hintergrund-Aufgaben, Schlüsselbund, Ordner und Datenbank, `LilithKit` und Typnamen sowie das Repo. Sonst gingen Anmeldung, Backup-Stand und laufende Uploads auf dem iPhone verloren.

## 16. Sammlungen (12.11.2026)

Plan: `docs/SAMMLUNGEN-PLAN.md`.

- Der Tab heißt **„Sammlungen“** (wie bei Apple): eine Seite mit Abschnitten, jeweils Überschrift mit „›“ und einer Reihe zum Wischen oder einer kurzen Liste.
- **Kürzlich hinzugefügt** zeigt Karten je Hochlade-Tag (Suche mit `createdAfter`, nach Tag gruppiert).
- **Personen:** `getAllPeople` (ohne ausgeblendete), Gesichter über `/people/{id}/thumbnail`. Ein Tipp öffnet die Timeline mit `personId`.
- **Medienarten** nutzen die einfachen, älteren Suchfelder (`type`, `isMotion`, `lensModel`, `originalFileName`), weil der neue `filter` auf v3.3.5 mit 400 antwortete. Selfies: Objektive mit „front“ aus `getSearchSuggestions`. Bildschirmfotos: PNG-Bilder. RAW: bekannte Endungen. Mehrere Abfragen werden zusammengeführt und nach Datum sortiert.
- **Start-Animation:** Erst erscheint unten „von Jannick Stahn“ (geladen), dann wird der Mond voll, dann geht es mit wachsender Geschwindigkeit hinein (0,55 s).

## 17. Orte und Fehlerbehebungen (13.11.2026)

- **Orte:** `getMapMarkers`, je Stadt zusammengefasst (Mittelpunkt, Anzahl, ein Foto als Titelbild). Kleine Karte in den Sammlungen, große Karte mit runden Foto-Nadeln; ein Tipp zeigt die Fotos der Stadt (Suche mit `city`/`country`).
- **„Jetzt sichern“ beendete die App:** Hintergrund-Aufgaben wurden mit `using: nil` angemeldet; iOS ruft den Block dann im Hintergrund auf, Swift 6 bricht ab, weil er zum MainActor gehört. Jetzt `using: .main`, und `expirationHandler` sind `@Sendable`. Betraf auch die nächtlichen Läufe.
- **Ring ums Profilbild** nur, solange gesichert wird oder etwas fehlt.
- **Video:** AirPlay oben rechts neben der Datums-Pille, kein Bild-in-Bild-Knopf mehr; stattdessen automatisch beim Verlassen der App (Schalter unter Konto → Videos). Beim Spulen sind Blättern und Wegziehen gesperrt, damit die Leiste bleibt. Weichere Übergänge.
- **Auswahl in Alben:** „Zurück“ und damit das Zurückwischen sind aus, solange man auswählt.

## 18. Laden: schneller und gleichmäßiger (13.11.2026)

Plan: `docs/LADEN-PLAN.md`.

- **Hauptursache für „mal schnell, mal langsam“:** Backup- und Upload-Meldungen haben Timeline und Sammlungen jedes Mal komplett neu geladen. Jetzt werden sie gebündelt (höchstens alle 2 s), und `TimelineStore.laden()` behält jeden Monat, dessen Schlüssel und Anzahl gleich sind (Server-Inhalt je Monat wird gemerkt, lokale Fotos neu eingemischt). Ist nichts geändert, passiert nichts.
- **Kleinere Bremsen:** 120 ms Wartezeit nur noch beim Scrollen (das Raster meldet `scrollt`), fehlgeschlagene Monate werden nach 0,5 s und 2 s erneut geladen, Datum wird von Hand gelesen (statt drei Formatierern pro Foto), Datenbank und Sortieren der Gerätefotos laufen abseits des Haupt-Threads, Nuke speichert verkleinerte Bilder auch auf der Festplatte (`dataCachePolicy = .automatic`).
- **Sofortstart:** Statt der im Plan genannten Datenbank-Tabellen eine JSON-Datei im Caches-Ordner (einfacher, gleiche Wirkung): Monatsliste und Inhalt der 3 neuesten Monate. Beim Start sofort zeigen, danach gespeicherte Monate einmal frisch holen. Beim Abmelden wird alles gelöscht.
- **Sammlungen** werden genauso gespeichert und sofort gezeigt; neu geladen wird erst nach 2 Minuten oder bei einer Änderung (Ziehen zum Aktualisieren erzwingt es).
- **Messen:** `LadeMessung` schreibt Signposts und Zeilen ins Log (Subsystem `app.lilith`, Kategorie `Laden`).

## 19. Doppelte Fotos und Ordner (13.11.2026)

- **Doppelte Fotos:** `getAssetDuplicates`; je Gruppe die Fotos nebeneinander mit Auflösung, Dateigröße und Datum, Immichs Vorschlag (`suggestedKeepAssetIds`) ist vorausgewählt. „Auswahl behalten“ ruft `resolveDuplicates` auf: Die übrigen kommen in den Papierkorb und sind dort wiederherstellbar.
- **Ordner:** `getUniqueOriginalPaths` als Baum, beginnend beim gemeinsamen Anfang aller Pfade (statt fünf leeren Ebenen wie `/usr/src/app/upload/…`). „Fotos in diesem Ordner“ nutzt `getAssetsByOriginalPath`. Symbole in der Liste grau.

## 20. „Heute in früheren Jahren“ (13.11.2026)

- Ganz oben in den Sammlungen: je früherem Jahr eine Karte mit den Fotos vom heutigen Kalendertag („Vor einem Jahr“, „Vor 5 Jahren“). Gibt es keine, bleibt der Abschnitt weg.
- Bewusst über die Suche (`takenAfter`/`takenBefore`, bis 20 Jahre zurück, parallel) statt über Immichs „Erinnerungen“: Die hängen von einem nächtlichen Serverauftrag ab. Wird einmal pro Tag geladen. Zum Prüfen: `-LilithHeute 2026-11-21`.

## 21. Teilen-Links (13.11.2026)

- Immich-Freigabelinks (`createSharedLink`): für ein Album (Ansicht-Menü → „Link zum Album teilen …“) oder ausgewählte Fotos (Auswahl-Leiste → „Link“; nur Fotos vom Server). Optionen: gültig 1 Tag / 7 Tage / 30 Tage / nie, Herunterladen erlauben, Passwort. Danach Link senden oder kopieren.
- Link-Adresse: `<Server>/share/<key>` bzw. `/s/<slug>`.
- Konto → „Geteilte Links“: alle Links, senden, löschen (Wischen oder Kontextmenü). Löschen entfernt nur den Link, nicht die Fotos.

## 22. Gesperrter Bereich, aufgeräumtes Ansicht-Menü (13.11.2026)

- **Gesperrt:** Sammlungen → Weitere → „Gesperrt“ nutzt Immichs gesperrten Ordner (Sichtbarkeit `locked`). Die Immich-PIN wird einmal eingegeben und im Schlüsselbund abgelegt (nur dieses Gerät, nur mit Face ID/Gerätecode lesbar). Beim Verlassen sperrt Luna die Sitzung wieder. Gibt es noch keine PIN, richtet Luna eine ein.
- **Ansicht-Menü wie bei Apple:** oben die Aktionen (Auswählen, Titelbild wählen …, Link teilen …), darunter die Abschnitte „Ansicht“ und „Springen“, ganz unten „Neu laden“.
- **Titelbild wählen:** im Album bzw. bei Personen über das Menü. Ein Foto antippen, „Übernehmen“. Zusätzlich weiterhin in der Fotoansicht.
- **Auswahl-Leiste:** Favorit, Zu Album, Link, Löschen bleiben sichtbar. Seltenes (Titelbild, Archivieren, Sperren) liegt unter „Mehr“, damit die Leiste nicht überläuft.

## 23. „In Luna hochladen“ und Vorschau-Leiste (13.11.2026)

- **Teilen-Erweiterung** (`App/Teilen`, nur iPhone/iPad): erscheint im Teilen-Menü bei Fotos und Videos (bis 50). Optional Album wählen, dann hochladen; Duplikate erkennt der Server.
- **Anmeldung:** `GeteiltesKonto` legt Konto und Zugang in einen gemeinsamen Schlüsselbund-Bereich (`keychain-access-groups`, erste Gruppe = Standard). Luna zieht die Anmeldung beim Start selbst um, kein neues Anmelden. Entitlements nur für iOS, weil der Mac ohne Profil sonst nicht startet.
- **Vorschau-Leiste** in der Fotoansicht wie bei Apple: kleine Bilder der Nachbarn, das aktuelle breiter, Antippen springt hin.

## 24. Fotoansicht wie Apple Fotos, AirPlay (13.11.2026)

- **Vorlage:** Apple Fotos (iOS 26), untersucht mit Replica (`replica/recon.md`, `replica/features.csv`). Nur Aufbau und Abläufe, keine Apple-Symbole oder -Texte; Luna behält Namen, Kirschrot und Mond.
- **Etappe 1:** Hintergrund hell mit Bedienelementen (heller Modus), schwarz zum Ansehen; unten Teilen links und Löschen rechts als eigene Knöpfe, Favorit und Info in der Mitte; „…“ oben rechts mit Kopieren, Ausblenden (gesperrter Bereich), Zu Album, Titelbild, Link teilen, Archivieren. Vorschau-Leiste bei Videos aus (dort sitzt die Zeitleiste).
- **AirPlay:** Das Apple TV lädt Videos selbst und bekam Lunas Anmelde-Header nicht. Jetzt steht der Zugang zusätzlich im Video-Link (`sessionKey` bzw. `apiKey`), Immich akzeptiert das.
- **Etappe 2:** Info öffnet kein eigenes Fenster mehr. Das Foto rutscht nach oben (so hoch wie das Bild bei voller Breite), darunter Karten: Datum + Dateiname, Kamera + Format, Objektiv + Größe, Belichtungswerte, Karte mit dem Foto als Stecknadel, Personen. Antippen des Fotos oder Ziehen nach unten schließt die Infos. Der Untertitel wird nur angezeigt; Bearbeiten käme später (schreibt auf den Server).
- **Vorschau-Leiste ohne Ende:** Sie zeigt immer 120 Nachbarn je Seite rund um das aktuelle Foto und rückt mit; Wischen über die Leiste blättert mit, wie bei Apple.
- **Etappe 3 (Mediathek):** Großer Titel „Fotos“ mit Anzahl darunter statt Kapsel, heller Verlauf oben; beim Scrollen großes Datum mit Ort. Oben rechts nur ≡ und „Auswählen“ (eigener Knopf). Im ≡-Menü: Hochladen, Filter (Alle Objekte, Favoriten, Medienarten) direkt in „Fotos“, Darstellung, Springen. Das Profil sitzt jetzt in den Sammlungen.
- **Etappe 4 (Sammlungen):** Titel in einer Reihe mit „…“ und Profil (iOS 26), jeder Abschnitt mit Pfeil zum Einklappen (wird gemerkt), Medienarten und „Weitere“ als Kacheln in zwei Spalten, „Gesperrt“ mit Schloss.
- **Etappe 5 (Suche):** Suchfeld unten mit ✕ war schon wie bei Apple; „Zuletzt angesehen“ fehlt noch.
- **Test (replica-test):** Testplan in `replica/test-plan.md`, Fehler in `replica/bugs.md`. Wichtigster Fund (S1): Der gesperrte Bereich ging mit gemerkter PIN ohne sichtbare Bestätigung auf. Jetzt fragt Luna immer ausdrücklich nach Face ID bzw. Gerätecode, bevor die PIN aus dem Schlüsselbund gelesen wird; ohne Gerätesperre muss die PIN eingetippt werden.
- **Reihenfolge wie Apple:** In „Fotos“ liegen beim Blättern und in der Vorschau-Leiste ältere Fotos links, das neueste ganz rechts (wie im Raster unten rechts). In Alben und Filtern bleibt es „Neuestes zuerst“, passend zu deren Raster (`DetailView.aeltereLinks`).
- **Videos wie Apple:** Oben die Video-Leiste (Abspielen, Zeitleiste, Ton; Zeiten nur beim Ziehen), darunter die Vorschau-Leiste, darunter die Knöpfe. Die Video-Leiste ist im hellen Modus hell getöntes Glas mit dunklen Symbolen (`lilithGlas(in:toenung:)`).
- **Version 0.10.0** (Build 3) mit allen Änderungen der Apple-Fotos-Runde.
