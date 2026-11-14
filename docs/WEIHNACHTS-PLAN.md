# Luna – Weihnachtszeit ausbauen

Stand: 14.11.2026 · Status: **freigegeben (1 bis 4) und gebaut, mit Änderungen siehe unten**

## Was es schon gibt

- Läuft automatisch vom **1. Dezember bis 6. Januar** und lässt sich unter Konto abschalten.
- **Startbildschirm:** leiser Schnee vor dem Nachthimmel, ein kleiner Stern am Mond und „Frohe Weihnachten“.
- **Sammlungen:** ein Hauch Schnee ganz oben, der nach unten ausblendet.
- Ein Tannengrün als Farbe ist schon angelegt, wird aber noch nirgends benutzt.

Heute (14.11.) sieht man davon nichts, weil der Zeitraum noch nicht begonnen hat.

## Vorschlag: was dazukommt

Grundregel: festlich, aber leise. Die Fotos bleiben die Hauptsache. Auf Fotos selbst und in der Vollbildansicht fällt nie Schnee.

1. **Schnee auch im Tab „Fotos“:** wie in den Sammlungen ein leichter Schneefall oben hinter dem großen Titel „Fotos“, der nach unten ausblendet. Beim Scrollen bleibt er oben stehen und liegt nie über dem Raster.
2. **Schnee bleibt liegen:** Auf den Glas-Knöpfen oben (≡ und „Auswählen“) und auf der Tab-Leiste unten liegt eine schmale Schneekante, wie Schnee auf einem Fensterbrett. Sie ist gezeichnet und klein, und die Knöpfe sind normal bedienbar.
3. **Sammlung „Weihnachten früher“:** Im Tab Sammlungen gibt es ganz oben eine Karte mit euren Fotos vom 24. bis 26. Dezember aus allen früheren Jahren, nach Jahr gruppiert. Sie zeigt nur, was schon auf dem Server liegt, und ändert dort nichts.
4. **Mac:** Der Schnee kommt auch in die Mac-Version (Fotos und Sammlungen).
5. **Widget (optional):** Im Dezember fällt ganz leichter Schnee über das Foto-Widget, und unten steht neben dem Datum ein kleiner Stern.

Rücksicht:
- Ist „Bewegung reduzieren“ an, steht der Schnee still.
- Der Schalter unter Konto schaltet alles auf einmal ab.
- Der Schnee braucht kaum Akku: wenige Flocken, höchstens 30 Bilder pro Sekunde, und er pausiert, solange ein Foto offen ist.

## So zeige ich es dir vorher

Mit einem Testschalter, den es nur in der Entwickler-Version gibt, lässt sich die Weihnachtszeit im Simulator schon jetzt einschalten. Du bekommst Bildschirmfotos von Start, Fotos, Sammlungen und Widget.

## Aufwand

Klein bis mittel: Schritte 1, 2 und 4 sind schnell gemacht. Schritt 3 braucht eine neue Abfrage plus Tests. Schritt 5 ist optional.

## Offene Entscheidungen

- [ ] So bauen?
- [ ] Alle fünf Punkte oder nur einen Teil? Vorschlag: 1 bis 4, das Widget nur wenn du magst.

## Was tatsächlich gebaut wurde (14.11.2026)

- Auf dem iPhone fällt der Schnee über die ganze App, als eigene Ebene über allem außer der Fotoansicht.
- Der Schnee bleibt oben auf der Tab-Leiste liegen. Beim Scrollen und beim Tab-Wechsel springt er hoch und fällt mit kräftiger Schwerkraft zurück. Wird es zu viel, rutscht er an den runden Enden herunter. Fährt die Leiste weg, fällt der Schnee hinterher.
- Auf Texte und Knöpfe kommt kein Schnee. Auf Apples System-Knöpfe ließ er sich ohnehin nicht sauber legen.
- „Weihnachten früher“: je Jahr eine Karte mit den Fotos vom 24. bis 26. Dezember, und eine Gesamtansicht nach Jahren.
- Mac: Schnee in „Fotos“ und in den Sammlungen, ohne Tab-Leiste.
- Fehler behoben: Die Flocken wurden erst nachträglich angelegt und waren darum unsichtbar, auch auf dem Startbildschirm.
- Weiter geht es im Design-Plan (`docs/DESIGN-PLAN.md`): Dort wird Weihnachten zu einem Design, das nur in der Weihnachtszeit wählbar ist und dann automatisch angeht.
