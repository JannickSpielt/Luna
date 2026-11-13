# Luna – Runde 3: Fehler, Feinschliff und neue Wünsche

Stand: 13.11.2026 · Status: **freigegeben am 13.11.2026** (Weihnachten automatisch + abschaltbar, PIN hinter Face ID)

## A. Fehler und kleine Wünsche (zuerst)

1. **Backup-Text im Konto:** Statt immer „3.608 …“: „Alles gesichert“, wenn nichts fehlt. Kommen neue Fotos, zählt der Text nur diese: „1 von 3 gesichert“.
2. **Mond in der Upload-Anzeige:** Bisher ein voller Kreis mit einem Kreis dahinter (sah nach Fehler aus). Neu: echter Mond, der mit dem Fortschritt zunimmt (Sichel → Vollmond), ohne zweiten Kreis.
3. **Tab-Leiste in „Fotos“ wieder immer sichtbar** (kein Ausblenden beim Scrollen mehr).
4. **Sammlungen von oben nach unten:** Alben, Personen, Medienarten, Orte, Weitere zeigen das Neueste oben. Nur „Fotos“ bleibt wie bei Apple (Neuestes unten).
5. **Video ohne Ton nach dem Drehen:** Beim Drehen baut iOS die Ansicht neu auf, Luna schaltet dabei den Ton ab und nicht wieder an. Wird behoben (auch beim Öffnen im Querformat).
6. **Flüssiger:** Obere Leiste in der Fotoansicht genauso weich ein- und ausblenden wie die Video-Leiste; allgemein einheitliche, weiche Übergänge.
7. **Foto zum Schließen nach unten ziehen:** weniger Widerstand, schon kurzes Ziehen mit Schwung schließt.

## B. Neue Funktionen

8. **Titelbild wählen:** Bei einem Foto „Als Albumtitelbild“ (im Album) und „Als Bild für Person“ (bei Personen). Immich kann beides.
9. **Löschen auch vom iPhone:** Liegt ein gelöschtes Foto auch in der iPhone-Mediathek, fragt Luna: „Auch vom iPhone löschen?“. iOS fragt danach selbst noch einmal (Sicherheit). Ohne Bestätigung bleibt es auf dem iPhone.
10. **Gesperrter Bereich:** Immichs „gesperrter Ordner“: Fotos dort tauchen nirgends sonst auf. In Luna unter Sammlungen → Weitere → „Gesperrt“, Öffnen mit Face ID. Immich schützt den Bereich mit einer eigenen PIN; Luna fragt sie einmal ab und legt sie geschützt (nur mit Face ID lesbar) im Schlüsselbund ab. Fotos lassen sich in den gesperrten Bereich verschieben und wieder heraus.
11. **Weihnachten:** Vom 1. Dezember bis 6. Januar automatisch (abschaltbar unter Konto): leichter Schneefall beim Start, ein kleiner Stern am Mond, festlicher Akzent (Tannengrün zum Kirschrot), Begrüßung „Frohe Weihnachten“ im Startbildschirm. Fotos selbst bleiben unverändert.

## C. Frage: Live-Aktivität auf dem Sperrbildschirm

Gibt es schon (seit Backup Etappe 4), aber mit einer Grenze: iOS lässt Luna im Hintergrund nur kurz rechnen. Die Uploads selbst laufen weiter (iOS übernimmt sie), die Anzeige auf dem Sperrbildschirm wird aber nur aktualisiert, wenn iOS Luna kurz weckt – also in Sprüngen. Durchgehend live geht nur, solange Luna offen ist, oder mit „Jetzt sichern“ (iOS 26), bei dem iOS selbst einen Fortschritt im System zeigt. Eine dauerhaft laufende Anzeige ohne App würde Push-Nachrichten vom Server brauchen, das kann Immich nicht.

## Reihenfolge

A (alles) → 8 → 9 → 11 → 10. Nach A und nach jeder Funktion kurz zeigen.

## Offene Entscheidungen

- [ ] Weihnachten automatisch im Zeitraum **und** abschaltbar (Vorschlag) – oder nur per Schalter?
- [ ] Gesperrter Bereich: PIN wie oben im Schlüsselbund hinter Face ID (Vorschlag)?
