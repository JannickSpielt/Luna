# Lilith – Feinschliff nach dem ersten Test am iPhone

Stand: 12.11.2026 · Status: **umgesetzt am 12.11.2026**, vorher freigegeben (Live Photos bleiben stumm, Bild-in-Bild und AirPlay kommen mit)

Grundlage: deine Rückmeldungen vom Test auf dem iPhone und die Untersuchung des Codes. Die Alben kommen erst danach dran.

## 1. Lücken in der Galerie (schwarze Reihen)

**Ursache:**
- iOS baut Kacheln, kurz bevor sie ins Bild scrollen. Ist der Monat da noch nicht geladen, bekommen sie einen Platzhalter.
- Ist der Monat dann fertig, frischt Lilith nur die Kacheln auf, die schon sichtbar sind. Die vorbereiteten bleiben leer.
- Der Platzhalter ist halb durchsichtig und wirkt auf Schwarz wie ein Loch.

**Lösung:**
- Alle Kacheln eines Monats auffrischen, sobald er geladen ist.
- Direkt vor dem Anzeigen jeder Kachel noch einmal nachsehen, ob ihr Monat inzwischen geladen ist.
- Monate, deren Laden abgebrochen wurde, neu laden, sobald man stehen bleibt.
- Platzhalter in einem deckenden Grau statt fast schwarz.

## 2. Kachel-Zoom flüssig (3 ↔ 4 ↔ 5 pro Reihe)

**Ursache:**
- Bisher passiert erst nach einem Stück Zusammenziehen etwas, und dann springt es auf einmal.
- Danach sind alle Bilder kurz weg, weil der Bildspeicher je Kachelgröße getrennt ist.

**Lösung:**
- Die Kacheln wachsen und schrumpfen live mit den Fingern, wie in Apples Fotos-App.
- Das Foto unter den Fingern bleibt dort stehen. Lässt man früh los, springt es sauber zurück.
- Feste Bildgrößen, damit beim Zoomen nichts leer aufblitzt.

## 3. Zoomen im Foto

**Ursache:** Das Foto wird immer zur Bildmitte hin vergrößert, und Verschieben geht erst, wenn man schon vergrößert hat.

**Lösung:**
- Gezoomt wird mit der Technik von iOS selbst. Das Foto wächst dort, wo die Finger sind, und man kann es beim Zoomen gleichzeitig verschieben.
- Doppeltippen zoomt auf die angetippte Stelle.
- Zum nächsten Foto wischen und nach unten wischen zum Schließen funktionieren weiter.

## 4. Teilen und Menüs schneller

**Ursache:**
- Beim Teilen lädt Lilith zuerst das ganze Original herunter und zeigt erst dann das Menü, und zwar jedes Mal neu.
- Menüs werden bei jedem Upload-Fortschritt neu berechnet.

**Lösung:**
- Das Teilen-Menü öffnet sofort. Das Original lädt im Hintergrund, und iOS zeigt dabei einen Fortschritt.
- Einmal geladene Originale werden wiederverwendet.
- Der Upload-Fortschritt bringt die Leiste und die Menüs nicht mehr ständig zum Neuzeichnen.

## 5. Eigener Videoplayer

**Ursache:** Der Player von Apple hat eigene graue Flächen, die oben und unten abgeschnitten wirken.

**Lösung:** ein eigener, schlichter Player im Stil der Fotoansicht. Er hat:
- Abspielen und Pause
- eine Zeitleiste zum Spulen mit Zeitangabe
- Ton an und aus

Die Bedienelemente sind aus klarem Glas. Ein Tippen blendet sie ein und aus, beim Abspielen verschwinden sie nach etwa 3 Sekunden von selbst.

Dazu kommen Bild-in-Bild (über `AVPictureInPictureController` mit der Player-Ebene, dafür den Hintergrundmodus „audio“) und AirPlay (`AVRoutePickerView` in der Leiste).

## 6. Ton trotz Stummmodus

- Videos spielen ihren Ton auch, wenn das iPhone auf stumm steht.
- Musik aus einer anderen App wird erst beim Abspielen unterbrochen, nicht schon beim Öffnen von Lilith. Danach läuft sie wieder weiter.

## 7. Start: durch den Mond in die App

- Nach dem Laden wird der Mond voll und kommt auf dich zu.
- In seiner Mitte öffnet sich ein Kreis, der immer größer wird, und dahinter erscheint die App.
- Das dauert etwa 0,7 Sekunden.
- Ist „Bewegung reduzieren“ eingeschaltet, wird stattdessen nur weich überblendet.

## 8. Kirschrot statt blassem Rosa

| | Bisher | Neu | Kontrast |
|---|---|---|---|
| Hell | #9E2A50 | **#C8102E** | 5,9 : 1 auf Weiß |
| Dunkel | #E8799A (rosa) | **#FF4D6A** | 6,5 : 1 auf Schwarz |

Die neuen Farben gelten auch für das App-Symbol der Akzentfarbe und die Live-Aktivität.

## Reihenfolge

1. Kirschrot, Ton im Stummmodus, Lücken (klein, sofort spürbar)
2. Zoomen im Foto, Teilen schneller
3. Eigener Videoplayer
4. Kachel-Zoom flüssig
5. Mond-Start

Nach jedem Schritt baue ich die App, prüfe sie im Simulator und zeige sie dir kurz.

## Offene Fragen

- [x] **Live Photos** bleiben im Stummmodus stumm, nur richtige Videos haben Ton.
- [x] **Bild-in-Bild und AirPlay** bleiben erhalten.
