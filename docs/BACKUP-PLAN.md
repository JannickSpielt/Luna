# Lilith – Plan für Upload & Backup

Stand: 12.11.2026 · Status: **freigegeben am 12.11.2026** (offene Entscheidungen: jeweils der Vorschlag)

Ziel: Fotos und Videos von iPhone, iPad und Mac auf deinen Immich-Server bringen. Manuell, wann du willst, und auf iPhone/iPad auch automatisch im Hintergrund. Ohne Duplikate und ohne dass etwas verloren geht.

---

## 1. Was der Server (Immich v3.3.5) vorgibt

| Thema | So funktioniert es |
|---|---|
| Upload | `POST /assets` als Multipart: Datei, `fileCreatedAt`, `fileModifiedAt` (mit Zeitzone), optional Dateiname, Videodauer (ms), Favorit, Archiv. Antwort: „neu angelegt“ oder „Duplikat“ mit der ID des vorhandenen Fotos. |
| Duplikate vorab erkennen | `POST /assets/bulk-upload-check` mit SHA1-Prüfsummen (Base64). Der Server sagt pro Foto „hochladen“ oder „schon da“, auch ob es im Papierkorb liegt. |
| Live Photos | Erst das kurze Video hochladen (versteckt), dann das Foto mit Verweis auf das Video – genau wie die offizielle Immich-App. |
| Album | Kein Feld beim Upload. Danach mit der vorhandenen Funktion „Zu Album“ hinzufügen. |
| Große Videos | Kein Weiterladen nach Abbruch: Jede Datei geht in einem Stück. Grenzen setzt dein Reverse-Proxy (z. B. Größe, 60-Sekunden-Timeout). Lilith erklärt solche Fehler verständlich. |
| Geändert in v3 | Es gibt keine Geräte-Kennung (`deviceAssetId`) mehr. Welches lokale Foto welchem Server-Foto entspricht, merkt sich Lilith selbst über die Prüfsumme. |

## 2. Wo das Backup in der App lebt

- **Kein neuer Tab.** Backup ist eine Hintergrundfunktion. Es lebt im **Konto-Bereich** (Kreis oben rechts) als eigener Abschnitt mit Statuskarte.
- **Der Kreis oben rechts bekommt einen Mond-Ring:** Er füllt sich vom Neumond (nichts gesichert) bis zum Vollmond (alles gesichert). Pausiert: Wolke vor dem Mond. Fehler: dünner granatroter Rand.
- **Einrichten in drei Schritten:** kurze Erklärung („Deine Fotos gehen nur an deinen Server“) → Zugriff auf die Fotomediathek → Umfang (alle Fotos oder ausgewählte Alben, Videos ja/nein, „Nur WLAN“ ist voreingestellt).
- **Ein Hinweis-Banner in der Bibliothek** nur zweimal: einmal als Einladung („Fotos von diesem iPhone sichern?“) und bei Fehlern, die du selbst beheben musst.
- **Statuszeile, immer mit konkretem Grund:** „8.412 von 9.030 gesichert“, „Sichert 12 Objekte …“, „Wartet auf WLAN“, „Wartet auf Strom“, „3 Objekte nicht gesichert – Details“, „Alles gesichert · zuletzt 21:14“.
- **„Vollmond“-Moment:** Ist das erste komplette Backup fertig, geht der Mond einmal auf: „Alles sicher. Gute Nacht.“ Nur einmal.

## 3. Manueller Upload

- **iPhone/iPad:** „+“-Knopf in Bibliothek und Album. Öffnet Apples Foto-Auswahl, die keinen Vollzugriff braucht. Aus einem Album heraus landen die Fotos direkt in diesem Album.
- **Mac:** Dateien oder Ordner ins Fenster ziehen. Auf ein Album in der Seitenleiste gezogen, landen sie dort. Zusätzlich „Ablage › Importieren …“ (⌘I).
- **Fortschritt** in der Leiste oben, nicht als Fenster, das alles blockiert.
- **Live Activity** (Sperrbildschirm, Dynamic Island) nur bei großen manuellen Uploads ab etwa 20 Fotos oder 200 MB.

## 4. Automatisches Backup (iPhone/iPad)

- **Neue Fotos erkennen:** Beim ersten Mal liest Lilith nur die Liste deiner Fotos (Datum, Art) – bei 50.000 Fotos dauert das Sekunden bis wenige Minuten. Danach fragt sie iOS nur noch „Was hat sich seit dem letzten Mal geändert?“.
- **Prüfsummen wie die offizielle Immich-App:** Lilith berechnet die Prüfsumme genauso (SHA1 der aktuellen Version, Base64). Hast du schon mit der Immich-App gesichert, erkennt Lilith diese Fotos als „schon da“ und lädt sie nicht noch einmal hoch.
- **Reihenfolge:** Prüfsumme berechnen → beim Server nachfragen (500 auf einmal) → nur Fehlendes hochladen. Bei einer großen Bibliothek, die schon auf dem Server ist, spart das fast das ganze Datenvolumen.
- **Im Hintergrund:** iOS entscheidet, wann Lilith arbeiten darf – meist nachts, am Ladekabel, im WLAN. Lilith nutzt dafür:
  - Uploads, die iOS selbst weiterführt, auch wenn die App geschlossen ist,
  - nächtliche Läufe für die aufwendige Arbeit (Prüfsummen, iCloud-Originale laden),
  - kurze Läufe zwischendurch für ein paar neue Fotos,
  - ab iOS 26 einen „Jetzt sichern“-Knopf, der beim Verlassen der App mit Fortschrittsanzeige weiterläuft.
- **Beim Öffnen der App** holt Lilith immer nach, was fehlt. Das ist der zuverlässigste Weg.
- **Fotos nur in iCloud** („Speicher optimieren“): Das Original wird bei Bedarf geladen, höchstens zwei gleichzeitig, nur wenn genug Platz frei ist. Abschaltbar.
- **Eingeschränkter Zugriff** auf die Fotos: Dann wird nur die freigegebene Auswahl gesichert, mit klarem Hinweis und Knopf „Auswahl ändern“.

**Einstellungen:** Backup an/aus · Nur WLAN (Videos auch mobil?) · Nur beim Laden · Videos einbeziehen · Alle Alben oder ausgewählte · iCloud-Originale laden.

**Ehrlich in der App erklärt** (Hilfeseite „So funktioniert das Backup“): kein fester Takt; zuverlässig nachts am Ladekabel im WLAN; Stromsparmodus und Beenden der App im App-Umschalter pausieren; das erste Backup einer großen Bibliothek kann mehrere Nächte dauern.

## 5. Technik

- **Datenbank (GRDB) wird jetzt eingeführt.** Sie merkt sich pro Foto: Prüfsumme, Zustand (wartet → wird vorbereitet → wird hochgeladen → fertig / Duplikat / Fehler), Anzahl Versuche, Server-ID. Dazu den Stand der Änderungsabfrage und die Albenauswahl. Dieselbe Datenbank wird später auch für den Offline-Speicher der Timeline genutzt.
- **Nichts doppelt, nichts verloren:** Jeder Schritt wird gespeichert. Nach einem Absturz oder Neustart gleicht Lilith Datenbank, laufende Uploads und vorbereitete Dateien ab und macht dort weiter. Ein doppelt gesendeter Upload ist harmlos, weil der Server ihn als Duplikat erkennt. Fehler werden mit wachsendem Abstand wiederholt, nach 5 Versuchen erscheint das Foto in der Fehlerliste.
- **Speicher schonen:** Prüfsummen werden stückweise berechnet, Videos nie ganz in den Speicher geladen. Vorbereitete Upload-Dateien belegen höchstens etwa 1 GB.
- **Neue Module:** `Persistence` (Datenbank) und `Backup` (Erkennen, Prüfen, Hochladen). Der vorhandene `ImmichClient` bekommt Upload und Duplikat-Prüfung.

## 6. Etappen

| # | Etappe | Was du danach hast |
|---|---|---|
| 1 | Datenbank, Upload-Dienst mit Duplikat-Prüfung, Foto-Auswahl (iOS), Drag & Drop und Import (Mac), Upload ins Album | Fotos per Hand hochladen, mit Fortschritt, ohne Duplikate – auf allen Geräten |
| 2 | Zugriff auf die Fotomediathek, Erkennen neuer Fotos, Statuskarte mit Mond-Ring, Backup bei geöffneter App | „12.340 von 50.000 gesichert“ und alles nachholen, solange die App offen ist |
| 3 ✔ | Hintergrund-Uploads, nächtliche Läufe, Einstellungen (WLAN, Laden, Videos, Alben), iCloud-Originale | Backup läuft nachts von selbst |
| 4 | „Jetzt sichern“ (iOS 26), Live Activity, Fehlerliste, Hilfeseite, Vollmond-Moment | Fortschritt auch außerhalb der App sichtbar, Fehler einzeln lösbar |

Jede Etappe wird einzeln gebaut, geprüft und dir vor dem Commit gezeigt.

**Später (nicht Teil dieses Plans):** Share Extension („In Lilith hochladen“ aus anderen Apps), Ordnerwächter auf dem Mac, Menüleisten-Symbol, bearbeitete und unbearbeitete Version getrennt sichern.

## 7. Größte Risiken

1. **iOS bremst Hintergrundarbeit** – Erwartung „wie iCloud“ ist nicht erfüllbar. Gegenmittel: ehrliche Erklärung, Nachholen beim Öffnen, „Jetzt sichern“ ab iOS 26.
2. **Erstes Backup einer großen Bibliothek mit iCloud-Originalen** kostet Zeit, Akku, Datenvolumen und Speicher. Gegenmittel: Grenzen für Downloads und Speicher, nur WLAN als Voreinstellung.
3. **Abbrüche mitten im Upload** – Datenbank und laufende Uploads müssen nach dem Neustart wieder zusammenpassen. Gegenmittel: Abgleich beim Start, mit Tests.
4. **Dein Reverse-Proxy** begrenzt eventuell Größe oder Dauer von Uploads (große Videos). Gegenmittel: verständliche Fehlermeldung mit dem Hinweis, was am Server einzustellen ist.
5. **Live Photos, Serienbilder, Zeitlupe** haben mehrere Dateien pro Foto. Zuerst nur Original und Live-Paar, Sonderfälle werden als „nicht unterstützt“ angezeigt statt still übersprungen.

## 8. Offene Entscheidungen für dich

- [ ] **Hast du schon mit der offiziellen Immich-App vom iPhone gesichert?** (Wenn ja: Lilith erkennt diese Fotos über die Prüfsumme und lädt sie nicht neu hoch – deshalb rechnet Lilith genau wie die Immich-App.)
- [ ] **Mac auch automatisch aus der Fotos-Mediathek sichern?** Vorschlag: nein, auf dem Mac nur per Hand (Drag & Drop, Import). Automatisch sichert das iPhone.
- [ ] **„Gesicherte Fotos vom iPhone entfernen“** (Speicher freigeben, als einmalige Aktion mit Prüfung und Vorschau) – Vorschlag: nicht in diesem Plan, sondern später.
- [ ] **Reihenfolge der Etappen** so okay? Vorschlag: mit Etappe 1 starten und nach jeder Etappe kurz anhalten.

---

## 9. Erweiterung vom 12.11.2026 (freigegeben am 12.11.2026: Server-Alben als Schalter, zuerst B)

### A) Nicht gesicherte Fotos in der Bibliothek zeigen (iPhone/iPad)

- Fotos vom iPhone, die noch **nicht auf dem Server** sind, erscheinen in der Bibliothek an ihrem Datum zwischen den Server-Fotos – wie in der offiziellen Immich-App.
- **Symbol unten rechts auf der Kachel:**
  - Wolke durchgestrichen = nur auf diesem iPhone
  - Pfeil nach oben = wird gerade hochgeladen
  - Ausrufezeichen = Hochladen gescheitert
- Das Vorschaubild kommt direkt vom iPhone (schnell, ohne Internet).
- **Antippen** öffnet das Foto wie gewohnt. Favorit, Album und Löschen gehen erst, wenn es gesichert ist. Dafür gibt es dort den Knopf „Jetzt sichern“.
- Im Ansicht-Menü: „Nicht gesicherte zeigen“ an/aus (an, sobald das Backup eingeschaltet ist).
- Gezeigt werden nur Fotos, die laut Albenauswahl (B) gesichert werden sollen – ausgeschlossene (z. B. Screenshots) nicht.

### B) Alben fürs Backup auswählen (aus Etappe 3 vorgezogen)

- In der Backup-Karte: **„Alben auswählen“** mit allen Alben der Mediathek (auch „Screenshots“, „Selfies“, „Videos“), jeweils mit Vorschaubild und Anzahl.
- **Wie in der Immich-App:** Antippen = sichern (Haken), noch mal antippen = ausschließen (rot), noch mal = neutral.
- Voreinstellung: „Alle Fotos“ (Zuletzt) wird gesichert.
- Ein Foto wird gesichert, wenn es in **mindestens einem gewählten** und **keinem ausgeschlossenen** Album liegt.
- Die Auswahl wird gespeichert, Änderungen wirken beim nächsten Durchgang.

### Technik in Kürze

- Die Timeline bekommt eine zweite Quelle: Lilith mischt die lokalen Fotos (aus der Datenbank von Etappe 2) monatsweise in die Server-Monate. Jede Kachel weiß, ob sie vom Server oder vom iPhone kommt.
- Die Albenauswahl wird in der Datenbank gespeichert. Beim Abgleich zählt nur noch, was laut Auswahl gesichert werden soll.
- Tests mit nachgebauter Mediathek wie in Etappe 2.

### Offene Entscheidungen

- [ ] **Alben auch auf dem Server anlegen?** Wird ein Foto aus dem iPhone-Album „Urlaub“ gesichert, landet es auf dem Server auch im Album „Urlaub“. Vorschlag: ja, als Schalter, aus als Voreinstellung.
- [ ] **Reihenfolge:** Vorschlag: zuerst B (Albenauswahl), dann A (Anzeige), weil A die Auswahl braucht.
