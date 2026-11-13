# Recon map: Apple Fotos (iOS 26, iPhone)

Scope: the look and the flows of the four main areas (Mediathek, Fotoansicht, Sammlungen, Suche), applied to Luna. Luna keeps its own name, colours (Kirschrot, moon) and Immich as the data source.
For: Luna (Jannick's personal Immich app)
Date: 2026-11-13

Clean room: only interaction patterns and layout are copied. No Apple icons, no Apple texts or logos. Luna's own SF Symbols, wording and brand stay. Reference screenshots live in `replica/screens/` (in .gitignore, never shipped).

## Sources

| # | source | where | notes |
| --- | --- | --- | --- |
| 1 | Apple Fotos in the iOS 26 simulator | own device, 6 sample photos | S01–S07, looked at only, nothing changed |
| 2 | Luna today | simulator + code | comparison |

## Core loop

Scroll through your photos, open a photo, swipe between photos, act on it (favourite, share, delete, info).

## Screens (Apple) and how Luna does it today

| ID | screen | Apple | Luna today | gap |
| --- | --- | --- | --- | --- |
| S01 | Mediathek | Large title "Mediathek" top left, under it "6 Fotos"; top right: filter button (≡) and "Auswählen" as its own pill | Pill "3.636 Objekte", glass group with +, ≡, profile picture | **medium**: title/count layout, "Auswählen" as a visible button |
| S02 | Photo view | Background **white in light mode** (black in dark / when tapped away); top: back (circle), date+time (pill), **"…" (circle)**; bottom: **share alone on the left**, pill with heart / info / edit in the middle, **trash alone on the right**; preview strip above it | Always black; bottom everything in one pill; no "…" button; strip ✓ | **large** |
| S03 | "…" menu in the photo | Top row of three icons (Kopieren, Duplizieren, Ausblenden), then Diashow, "Hinzufügen zu ›", "Infos anpassen ›" | missing; rare actions sit in the pill (cover) or are missing | **large** |
| S04 | Info | **No sheet**: the photo slides up, info appears underneath on the same page. Caption field, date + file name, camera + format badge, lens / MP / size, row of exposure values, map with the photo as a pin | Its own sheet (InfoPanel) | **large** |
| S05 | Sammlungen | Large title, top right "…" and profile; sections with a **collapse chevron**; "Angepinnt" (editable); cards with the title on the picture; at the bottom "Sonstige" as a **2-column tile grid** (Ausgeblendet 🔒, Zuletzt gelöscht 🔒, Duplikate, Karte …) | Sections with carousels, "Weitere" as a list, profile in Fotos | **medium** |
| S06 | Suche | Search field **at the bottom** above the keyboard, ✕ next to it; above it "Zuletzt" with picture cards and suggestion chips | own search tab | **small–medium** (check later) |
| S07 | Library menu (≡) | Top segment row: "Hinzugefügt / Aufgenommen" (sort); "Filter:" Alle Objekte, Favoriten, Bearbeitet, Mit dir geteilt, Von mir aufgenommen, In keinem Album, Medienarten ›; "Darstellungsoptionen ›" | Auswählen, Ansicht (Größer/Kleiner), Springen, Neu laden | **medium** |

## Flows

```
F01 Open a photo and close it again
    S01 -> S02 -> (swipe down) S01            Apple 1 tap · Luna 1 tap ✓
F02 Look at info
    S02 -> tap i -> info under the photo      Apple 1 tap, no sheet · Luna 1 tap, sheet
F03 Rare action (e.g. cover, add to album)
    S02 -> "…" -> entry                       Apple 2 taps · Luna: partly missing
F04 Filter the library (e.g. favourites only)
    S01 -> ≡ -> Favoriten                     Apple 2 taps · Luna: via Sammlungen (3+)
F05 Open the hidden area
    S05 -> Sonstige -> Ausgeblendet (Face ID) Apple ✓ · Luna ✓ ("Gesperrt")
```

## Components

| component | Apple | Luna |
| --- | --- | --- |
| Round glass button (44 pt) | back, "…", share, trash | there (lilithGlas circle) |
| Glass pill with icons | middle action group | there |
| Preview strip | under the photo | ✓ (since today) |
| Menu with a top icon row | "…" in the photo, sort in ≡ | missing (SwiftUI: `ControlGroup` in `Menu`) |
| Collapsible section with chevron | Sammlungen | missing |
| Tile grid, 2 columns, icon + name + lock | "Sonstige" | missing (list) |
| Info under the photo | S04 | sheet |

## Data model

Unchanged: Immich supplies everything. Already there and usable: favourite, archive, locked area, albums, people, places, EXIF (camera, lens, exposure), location, description (Immich "description" = caption).

## Out of scope

- Apple's editing (sliders button) as a full editor → idea 5 "Einfaches Bearbeiten" separately
- Rückblicke / memory films, wallpaper suggestions, Apple Intelligence search
- iCloud sharing features (shared albums with comments)
- Apple's own icons and wording

## Size

Screens 7, flows 5. Hard parts: (1) info under the photo instead of a sheet (gesture + layout in the paged view), (2) white background with a smooth switch to black, (3) collapsible Sammlungen sections. Size: **M** (several rounds).
