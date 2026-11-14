# Test plan – Luna (Apple-Photos-style round)

Date: 2026-11-13 · Device: iPhone 13 Pro Max simulator (iOS 26), real Immich server **read-only**: nothing is deleted, moved, archived, hidden or uploaded.

Automated: Swift Testing in `Packages/LilithKit/Tests` (logic). Manual: simulator, one screenshot per step (no Playwright, because this is a native app).

## F01 Open a photo, swipe, close
- F01-H1 Tap a photo → photo view with a light background, back / date / "…" at the top, share / heart+info / trash at the bottom, strip above.
- F01-H2 Swipe sideways → next photo, the strip moves along, the date changes.
- F01-H3 Pull down → back to the grid.
- F01-E1 Tap the photo → controls disappear, background black; tap again → light.
- F01-E2 Dark mode → background stays dark, controls readable.
- F01-E3 Video → no strip, video bar visible, AirPlay + "…" at the top, AirPlay icon visible.

## F02 Info
- F02-H1 Tap i → the photo slides up, cards underneath, i filled in.
- F02-H2 Tap the photo or pull down → info closes.
- F02-E1 Photo without location → no map, no gap.
- F02-E2 Swipe sideways with info open → info follows the new photo.
- F02-E3 Portrait photo → photo area not tiny (orientation).
- Auto: format badge, file line, exposure values, singular "1 Objekt".

## F03 "…" menu (look only)
- F03-H1 Open → row Kopieren/Ausblenden, Zu Album, Link, Archivieren; black icons.
- F03-E1 In an album → "Als Titelbild verwenden" is there.

## F04 Filters in Fotos
- F04-H1 ≡ → Favoriten → title "Favoriten" at the top, only favourites.
- F04-H2 ≡ → Medienarten → Videos → only videos.
- F04-H3 ≡ → Alle Objekte → back to the normal view, newest at the bottom.
- F04-E1 Filter without hits (e.g. RAW) → empty state instead of an empty grid.
- F04-E2 "Auswählen" with a filter active → selection works, "Fertig" ends it.

## F05 Sammlungen
- F05-H1 Title on the same row as "…" and profile.
- F05-H2 Collapse a section → content gone; restart the app → stays collapsed; expand again.
- F05-H3 Tile "Archiv" → opens; "Gesperrt" → PIN screen (do **not** set a PIN).
- F05-E1 Profile → account window opens.

## F06 Preview strip
- F06-H1 Tap a thumbnail → that photo.
- F06-H2 Swipe over the strip → photo follows.
- F06-E1 Swipe far → no end before the start/end of the library.
- Auto: window around the middle, never past the edges.

## F07 Search
- F07-H1 Search tab → field at the bottom, keyboard, suggestions.
- F07-H2 Tap a suggestion → results (read-only).
