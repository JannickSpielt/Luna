# Luna – Plan für schnelleres, gleichmäßiges Laden

Stand: 13.11.2026 · Status: **freigegeben am 13.11.2026**

## Warum es mal schnell und mal langsam ist

1. **Backup und Uploads laden alles neu.** Jedes Mal, wenn die App aktiv wird, startet ein Backup-Durchgang. Jeder Durchgang und jeder fertige Upload meldet „etwas hat sich geändert“. Daraufhin wirft die Timeline alle geladenen Monate weg und lädt sie neu (Kacheln werden kurz grau), und die Sammlungen holen alle Daten neu. Je nachdem, wann das passiert, wirkt die App mal flink, mal träge. **Das ist die Hauptursache.**
2. **Nichts wird zwischen zwei Starts gespeichert.** Bei jedem Start wartet die App erst auf die Monatsliste vom Server und dann auf den ersten Monat.
3. **Kleine Bremsen:** 120 ms Wartezeit vor jedem Monat (auch wenn man gar nicht scrollt), Fehler werden nicht neu versucht (graue Kacheln bis zu 15 s), Datumsangaben werden sehr umständlich gelesen (bei 1000 Fotos bis 0,2 s), einiges läuft auf dem Haupt-Thread und lässt die Oberfläche kurz stocken.
4. **Bilder:** Auf der Festplatte liegen nur die Originaldaten, beim Zurückscrollen wird jedes Bild neu verkleinert. Die Fotoansicht nutzt das schon geladene Rasterbild nicht.
5. **Sammlungen** laden bei jedem Öffnen Alben, Kürzlich, Personen und alle Kartenpunkte neu.

## Lösung in drei Schritten

**Schritt 1 – schnelle Verbesserungen (wenig Risiko)** ✔
- Neu laden nur noch, was sich wirklich geändert hat: Monate mit gleicher Anzahl bleiben stehen. Meldungen vom Backup werden gebündelt (höchstens alle 2 s), und reine Änderungen auf dem Gerät mischen nur die lokalen Fotos neu.
- Keine 120 ms Wartezeit, wenn man nicht scrollt; erster Monat startet gleichzeitig mit der Monatsliste.
- Fehlgeschlagene Monate automatisch erneut laden (nach 0,5 s und 2 s).
- Datum schnell lesen (feste Formate statt drei Formatierer pro Foto).
- Schwere Arbeit (Datenbank, Zusammenfügen) weg vom Haupt-Thread.
- Bilder: verkleinerte Bilder auch auf der Festplatte speichern; Fotoansicht zeigt sofort das Rasterbild.

**Schritt 2 – Sofortstart** ✔ (als JSON-Datei statt Datenbank-Tabelle)
- Monatsliste und die neuesten Monate in der Datenbank speichern. Beim Start sofort anzeigen, im Hintergrund mit dem Server abgleichen.

**Schritt 3 – Sammlungen ohne Warten** ✔
- Daten der Sammlungen merken und sofort zeigen, im Hintergrund auffrischen; Kartenpunkte erst laden, wenn „Orte“ sichtbar ist.

## Messen

Zeitmarken (Signposts) für Monatsliste, Monat, Zusammenfügen und Sammlungen, dazu eine Meldung bei jedem Neu-Laden durch das Backup. Vorher und nachher vergleichen, mit Backup an und aus.

Nach jedem Schritt kurz anhalten und zeigen.
