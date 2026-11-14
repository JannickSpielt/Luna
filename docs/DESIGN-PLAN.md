# Luna – Designs zum Auswählen

Stand: 14.11.2026 · Status: **freigegeben und gebaut (14.11.2026)**

## Was du bekommst

Unter **Konto → Design** eine schöne Auswahl. Jedes Design hat eine große Vorschau-Karte: ein kleines, echtes Abbild von Luna mit Raster, Titel und Tab-Leiste in den Farben dieses Designs (kein Bildschirmfoto, sondern live gezeichnet, darum stimmt es immer). Antippen wechselt sofort, mit einem weichen Übergang.

## Die Designs

1. **Standard:** wie jetzt. Hell oder dunkel, wie das iPhone eingestellt ist. Kirschrot als Akzent.
2. **Schwarz:** Echtes Schwarz überall, auch tagsüber. Karten und Flächen sind sehr dunkelgrau. Auf OLED-iPhones spart das Akku, und Fotos leuchten besonders.
3. **Nacht:** der Nachthimmel vom Startbildschirm als Grund. Tiefes Blauschwarz, ein Hauch von Sternen hinter den Sammlungen, Mondlicht (warmes Gold) als Akzent statt Kirschrot.
4. **Weihnachten:** *nur in der Weihnachtszeit* (1. Dezember bis 6. Januar):
   - Es schneit in der App, der Schnee bleibt auf der Tab-Leiste liegen und springt beim Scrollen hoch (ist schon gebaut).
   - „Weihnachten früher“ in den Sammlungen (ist schon gebaut).
   - Tannengrün als zweiter Akzent, Startbildschirm mit Stern und „Frohe Weihnachten“.
   - **Automatisch:** Am 1. Dezember schaltet Luna von selbst auf Weihnachten. Wählst du in der Zeit ein anderes Design, bleibt es dabei. Am 7. Januar geht es zurück zu deinem vorherigen Design. Außerhalb der Weihnachtszeit taucht die Karte in der Auswahl gar nicht auf.

Der bisherige Schalter „Weihnachten“ unter Konto fällt weg, weil die Design-Auswahl ihn ersetzt.

## Wie es gebaut wird

1. **Ein Design ist eine Farbpalette** (Hintergrund, Flächen, Akzent, Zusatzschmuck) im Design-Baustein. Die App liest die Farben überall aus dem gewählten Design, statt sie fest einzutragen.
2. **Wahl merken:** Das gewählte Design wird gespeichert, ebenso das „Vorherige“ für die Rückkehr nach Weihnachten.
3. **Einstellungsseite** mit den Vorschau-Karten, in zwei Spalten auf dem iPhone und in mehreren auf iPad und Mac.
4. **Mac:** dieselbe Auswahl in den Einstellungen.
5. Tests für die Weihnachtsregel (1.12. an, eigene Wahl bleibt, 7.1. zurück).

## Aufwand

Mittel bis groß: Die Farben müssen an vielen Stellen auf das Design umgestellt werden. Ich prüfe jedes Design im Simulator, hell und dunkel, und zeige dir Bildschirmfotos der Auswahl.

## Offene Entscheidungen

- [ ] So bauen?
- [ ] Diese vier Designs, oder andere bzw. weitere? Möglich wären zum Beispiel „Pastell“ oder „Hoher Kontrast“.

## Was gebaut wurde (14.11.2026)

- Konto → Darstellung → Design: Vorschau-Karten in zwei Spalten, live gezeichnet. Antippen wechselt sofort.
- Standard, Schwarz (echtes Schwarz), Nacht (Blauschwarz, Sterne hinter den Sammlungen, Mondgold) und Weihnachten (nur 1.12. bis 6.1.).
- Weihnachtsregel mit Tests: Am 1. Dezember automatisch, eine eigene Wahl bleibt, am 7. Januar zurück zum vorherigen Design.
- Der alte Schalter „Weihnachtszeit“ ist weg.
- Systemlisten wie Konto behalten die Apple-Farben; die eigenen Flächen der App folgen dem Design.
