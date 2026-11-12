# Lilith – Redesign-Plan

Stand: 12.11.2026 · Status: **freigegeben am 12.11.2026** (Nachtrose bleibt, Titel über den Fotos, Liquid Glass maßvoll)

Grundlage: Apple Human Interface Guidelines (Stand Oktober 2026, u. a. `typography.md`, `color.md`, `branding.md`, `toolbars.md`, `liquid-glass.md`), Slop-Audit (unslop) und Motion-Grundsätze (Emil Kowalski). Vorschau mit vorher/nachher: siehe Bild im Chat.

## Richtung

- **Produkt:** Lilith zeigt und sichert deine Fotos auf deinem eigenen Immich-Server, auf iPhone, iPad und Mac.
- **Charakter:** ruhig, nächtlich, genau.
- **Welt:** Nachthimmel über Fotoabzügen. Die Fotos sind die Farbe, Lilith ist die ruhige Nacht drumherum.
- **Momente:** die Fotos selbst (von Rand zu Rand, bis unter die Leisten) und der Mond beim Backup.
- **Erkennungszeichen:** der Mond, aber nur dort, wo er etwas bedeutet: Backup-Ring, Statuskarte, Start, Vollmond.

## Was heute stört

| Befund | Wo | Regel |
|---|---|---|
| Zwei Schriften gemischt: Serife (New York) für Monate, Alben, Suche, Onboarding; SF für den Rest. Wirkt wie eine Zeitschrift, nicht wie eine Foto-App. | 11 Dateien, u. a. Monatsköpfe im Grid | `typography.md`: wenige Schriften, klare Hierarchie; Serife nur mit Grund |
| Nachtrose (Rot) ist überall: globaler Tint, alle Symbole in Leisten, Schalter, Listen-Symbole. Konkurriert mit roten Fotos. | `RootView` `.tint`, 20 Stellen | `branding.md` › „Apply your app's accent color judiciously“; `color.md` › monochrome Leisten bei bunten Inhalten |
| Graue, undurchsichtige Monats-Bande trennt die Fotos | Monatskopf im Grid | `liquid-glass.md` › Scroll-Edge-Effekt statt fester Hintergründe unter Bedienelementen |
| Zu wenig Liquid Glass: Fotos enden unter einer weißen Fläche statt unter den Leisten | Bibliothek, Alben | `liquid-glass.md` › Inhalte unter Leisten durchlaufen lassen |
| Mond an vielen Stellen; goldener Ring auf Weiß nur 2,2 : 1 | Avatar, Lade-, Leer-Zustände | `color.md` Kontrast; Signatur nur an einer Stelle |

## Neue Regeln (Design-Tokens)

**Schrift:** nur SF mit den iOS-Textstilen (Dynamic Type). Keine Serife mehr, auch nicht in Monaten, Alben, Suche, Onboarding. Großer Titel 34 pt bold, Monat 17 pt semibold, Untertitel 13–15 pt.

**Farbe:**

| Rolle | Hell | Dunkel | Kontrast |
|---|---|---|---|
| Flächen, Text | Systemfarben (`systemBackground`, `label`, `secondaryLabel`) | dito, Grid auf echtem Schwarz | System |
| Akzent Nachtrose | #9E2A50 | #E8799A | 7,2 : 1 auf Weiß, 6,7 : 1 auf Schwarz |
| Mondlicht (nur Mond) | #C9A96A, Ring 3 pt | #EBD9B4 | Ring wird dicker |

Nachtrose nur noch für: gewählten Tab, Auswahl-Haken, Favoriten-Herz, den einen Hauptknopf (z. B. „Jetzt sichern“). Symbole in Leisten und Listen einfarbig.

**Liquid Glass (iOS 26, `glassEffect`, `.buttonStyle(.glass)` / `.glassProminent`):**

- Ja, maßvoll: Leiste oben und Tab-Leiste (macht iOS selbst), Monats-Etikett über den Fotos, Knöpfe in der Fotoansicht (klares Glas), Upload-Anzeige und Auswahl-Leiste, solange sie sichtbar sind.
- Nicht (Wunsch: nicht überladen): Scrubber (schlanker Griff ohne Glas), Hauptknopf „Jetzt sichern“ (normal gefüllt).
- Nein, nie: Listen, Album-Kacheln, Statuskarte – das ist Inhalt, dort macht Glas laut Apple die Hierarchie unruhig.
- Fotos laufen bis ganz nach oben unter die Leisten, mit Scroll-Edge-Effekt.
- iOS 18–25: dieselben Stellen mit den bisherigen Materialien (`ultraThinMaterial`).

**Ecken:** Album-Kacheln 10, Karten 12, Knöpfe 14, Kapseln rund. **Abstände:** 4-pt-Raster, Ränder 16.

**Bewegung:** kurz und ruhig, eine Kurve (ease-out), keine nachfedernden Springs. Glas-Elemente verschmelzen beim Wechsel (`GlassEffectContainer`), sonst nur Ein-/Ausblenden.

## Bildschirme

- **Fotos** (vorher „Bibliothek“): kein großer Titel; oben links eine Glas-Pille mit dem Datum, rechts die Leiste; Neuestes unten wie in Apples Fotos-App; Tab-Leiste verschwindet beim Scrollen.
- **Alben:** normale iOS-Liste (grau statt rot), Albennamen in SF, Kacheln mit 10 pt Ecken.
- **Suche:** SF statt Serife, Vorschläge als Glas-Chips.
- **Fotoansicht:** bleibt fast gleich, Knöpfe als echtes Glas.
- **Konto/Backup:** Standard-Einstellungsseite; Mond-Ring + Statuskarte als einziger „Moment“; „Jetzt sichern“ als getönter Glas-Knopf.
- **Onboarding/Anmeldung:** SF statt Serife, Mond bleibt als Startbild.
- **Mac:** gleiche Schrift- und Farbregeln; Glas auf Toolbar/Seitenleiste macht macOS selbst.

## Etappen

1. Tokens: Farben, Schrift, Akzent-Regeln (ein Commit, sichtbar überall)
2. Bibliothek + Grid (Monats-Glas, Fotos unter Leisten, Scrubber-Glas)
3. Alben, Suche, Konto, Onboarding
4. Fotoansicht, Upload-Anzeige, Auswahl-Leiste in Glas; Feinschliff Bewegung

Nach jeder Etappe kurz anhalten und zeigen.

## Offene Entscheidungen

- [x] **Akzentfarbe:** Nachtrose bleibt.
- [x] **Titel:** entfällt, stattdessen Datums-Pille (siehe ENTSCHEIDUNGEN.md, Abschnitt 13).
