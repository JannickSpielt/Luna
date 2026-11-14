# Luna – Idee 4: Foto-Widget

Stand: 14.11.2026 · Status: **freigegeben am 14.11.2026, gebaut**

## Was du bekommst

Ein Widget für den Home-Bildschirm (und den Mac-Schreibtisch später möglich), das ein Foto aus deiner Bibliothek zeigt – randlos, wie Apples Foto-Widget. Unten links klein das Datum und der Ort. Das Foto wechselt mehrmals am Tag von selbst. Tippen öffnet genau dieses Foto in Luna.

- **Größen:** klein, mittel, groß.
- **Was gezeigt wird** (beim Bearbeiten des Widgets wählbar, wie bei Apple):
  - **Zufällig aus allen Fotos** (Voreinstellung)
  - **Favoriten**
  - **Heute in früheren Jahren** (Fotos vom selben Tag; gibt es keins, zufällig)
  - **Ein Album** (Liste deiner Alben)
- **Wechsel:** etwa alle 3 Stunden. iOS bestimmt selbst, wann genau ein Widget neu lädt – „mehrmals am Tag“ ist realistisch, „jede Minute“ nicht.
- Videos werden als Standbild gezeigt; nur Fotos vom Server (nichts, was nur auf dem iPhone liegt).

## Wie es gebaut wird

1. **Neues Widget in der vorhandenen Widget-Erweiterung** (dort steckt schon die Live-Aktivität fürs Hochladen).
2. **Anmeldung:** wie beim Teilen-Menü über den gemeinsamen Schlüsselbund (`GeteiltesKonto`). Ohne Anmeldung zeigt das Widget „In Luna anmelden“.
3. **Fotos holen:** Immich hat dafür eine eigene Abfrage („zufällige Fotos“, mit Filtern für Favoriten und Alben). Das Widget lädt nur ein kleines Vorschaubild (Widgets haben wenig Speicher) und legt die nächsten Fotos für die kommenden Stunden gleich mit an.
4. **Antippen öffnet das Foto:** Luna bekommt dafür einen eigenen Link (`luna://foto/<id>`); die App öffnet dann die Fotoansicht mit diesem Foto.
5. **Ohne Internet:** Das zuletzt geladene Foto bleibt stehen.

## Was du einmal tun musst

Nichts Besonderes: Die Widget-Erweiterung bekommt dieselbe Schlüsselbund-Fähigkeit wie das Teilen-Menü; Xcode richtet das beim nächsten Bauen auf dein iPhone selbst ein. Danach Widget auf dem Home-Bildschirm hinzufügen (lange drücken → „+“ → Luna).

## Aufwand

Mittel: ein Arbeitsschritt mit Widget, Einstellungen, Link zum Öffnen und Tests. Danach kurz im Simulator zeigen.

## Offene Entscheidungen

- [ ] So bauen?
- [ ] Auswahl wie oben (Zufällig / Favoriten / Heute früher / Album) – oder nur „Zufällig“ zum Start? Vorschlag: alle vier, sie kosten kaum mehr.
