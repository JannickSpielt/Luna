# Luna – Plan für „Sammlungen“ (Alben-Bereich wie in Apples Fotos-App)

Stand: 12.11.2026 · Status: **freigegeben am 12.11.2026** (Tab heißt „Sammlungen“, Selfies und Bildschirmfotos mit Erkennung über Namen)

## Ziel

Der Tab „Alben“ wird zu einer langen Seite mit Abschnitten, wie „Sammlungen“ in Apples Fotos-App. Jeder Abschnitt hat eine Überschrift mit „›“ (alle anzeigen) und darunter eine Reihe zum seitlich Wischen oder eine kurze Liste.

## Abschnitte

| Abschnitt | Inhalt | Woher (Immich) |
|---|---|---|
| Kürzlich hinzugefügt | große Karten je Tag (Heute, Gestern …), nach Hochladedatum | Timeline nach `createdAt` (ersetzt die bisherige 30-Tage-Suche, keine Grenze von 1000 Fotos mehr) |
| Alben | eigene Alben, große Kacheln | wie bisher |
| Geteilte Alben | mit „Von …“ | wie bisher, getrennt |
| Personen **neu** | runde Gesichter, Namen | `getAllPeople`, Timeline mit `personId` |
| Orte **neu** | Karte mit Punkten, darunter Städte | `getMapMarkers`, `getExploreData`, Timeline mit Kartenausschnitt |
| Medienarten | Videos, Live Photos, Selfies, Bildschirmfotos, RAW | Suche mit Filter (Selfies und Bildschirmfotos über Kamera- und Dateinamen) |
| Weitere | Favoriten, Doppelte Fotos **neu**, Ordner **neu**, Archiv, Papierkorb | `getAssetDuplicates`, `getUniqueOriginalPaths` |

Nicht möglich: Porträts und Panoramen (Immich kann danach nicht filtern). Erinnerungen bleiben für später.

## Aussehen

- Karten 12 pt Ecken, Personen rund, Listen wie in den iOS-Einstellungen
- Liquid Glass nur auf Leisten und dem Etikett auf der Karte, nicht auf den Karten (Inhalt)
- Kirschrot nur für Auswahl und den gewählten Tab
- Tab-Name: „Sammlungen“ statt „Alben“ (wie bei Apple)

## Technik in Kürze

- Neue Immich-Endpunkte in den generierten Client aufnehmen: Personen, Karte, Orte, Duplikate, Ordner.
- Neue Filter für die vorhandene Timeline: Person, Ort, Medienart, Ordner. Alles öffnet sich in derselben Fotoansicht wie heute (Zoom, Auswahl, Detail).
- Doppelte Fotos: eigene Ansicht mit Gruppen und Vorschlag, welches bleibt (Löschen nur nach Rückfrage).
- Ordner: eigene Ansicht wie im Dateien-Browser.

## Etappen

1. ✔ Neue Seite mit Kürzlich hinzugefügt, Alben, Geteilte Alben, Weitere (ohne Neues vom Server)
2. ✔ Personen und Medienarten
3. Orte mit Karte
4. Doppelte Fotos und Ordner

Nach jeder Etappe kurz anhalten und zeigen.

## Offene Entscheidungen

- [ ] Tab „Sammlungen“ nennen (Vorschlag) oder „Alben“ lassen?
- [ ] Selfies und Bildschirmfotos zeigen, obwohl sie nur über Kamera- und Dateinamen erkannt werden? Vorschlag: ja.
