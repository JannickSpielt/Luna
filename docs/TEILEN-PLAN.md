# Luna – Idee 3: „In Luna hochladen“ aus anderen Apps

Stand: 13.11.2026 · Status: **freigegeben und gebaut am 13.11.2026**

## Was du bekommst

In jeder App mit Teilen-Knopf (Fotos, WhatsApp, Safari, Dateien …) erscheint **Luna**. Du tippst darauf, ein kleines Fenster zeigt die Fotos, optional ein Album, dann „Hochladen“. Ein Fortschrittsbalken läuft, danach schließt das Fenster. Die Fotos sind danach auf deinem Server.

## Wie es gebaut wird

1. **Neue Teilen-Erweiterung** (eigenes kleines Programm neben der App, nur iPhone/iPad).
2. **Anmeldung teilen:** Die Erweiterung muss wissen, bei welchem Server du angemeldet bist. Dafür legt Luna Serveradresse und Zugang zusätzlich in einen **gemeinsamen Schlüsselbund-Bereich** („Keychain Sharing“). Nur Luna und ihre Erweiterung können ihn lesen. Ohne Anmeldung zeigt die Erweiterung: „Bitte zuerst in Luna anmelden“.
3. **Hochladen** mit dem vorhandenen Upload-Code von Luna (gleiche Prüfung auf Doppelte: Fotos, die schon auf dem Server sind, werden übersprungen).
4. **Album wählen** (optional): Liste deiner Alben, „Kein Album“ ist die Voreinstellung.
5. **Grenzen:** iOS gibt Erweiterungen wenig Speicher und Zeit. Für ein paar bis einige Dutzend Fotos reicht das. Große Videos können abbrechen; dann zeigt Luna einen klaren Hinweis.

## Was du einmal tun musst

Die Erweiterung braucht in Xcode die Fähigkeit „Keychain Sharing“. Das trage ich in die Projektdatei ein. Beim ersten Bauen auf dein iPhone erstellt Xcode die Profile dafür selbst (geht auch mit kostenlosem Apple-Konto). Du musst Luna danach **einmal neu anmelden**, damit der Zugang in den gemeinsamen Bereich wandert.

## Mac

Auf dem Mac erst einmal nicht (dort fehlt die passende Signatur). Später möglich.

## Offene Entscheidungen

- [ ] So bauen?
- [ ] Neu anmelden einmal okay, oder soll Luna den Zugang beim nächsten Start selbst umziehen? (Vorschlag: selbst umziehen, ohne neu anmelden.)
