# Bugs – test round 13.11.2026

Severity: S1 security / data / core flow · S2 feature broken · S3 visibly wrong · S4 cosmetic.

## B1 · S1 · Locked area opened without Face ID / passcode
- **Steps:** Sammlungen → Weitere → "Gesperrt" (on a device where the PIN had been saved before).
- **Expected:** First a visible confirmation (Face ID / passcode), then the photos.
- **Actual:** The photos appeared immediately. The log showed: "PIN true, entsperrt false" → "mit gemerkter PIN geöffnet". The saved PIN was read without a prompt; the keychain's protection alone was not enough (at least not in the simulator).
- **Fix:** `PinSafe.lies` now explicitly asks for Face ID / passcode (`LAContext.evaluatePolicy`) and only then reads the PIN. With no device lock set up, it never hands the PIN out (it has to be typed). Also, an already unlocked server session is locked first.
- **Verified:** The iOS passcode prompt appears; cancelling → PIN entry, no photos. Status: **fixed**.

## B2 · S3 · Light fade washes out the first row of photos
- **Steps:** Fotos → ≡ → Medienarten → RAW (or any other filter).
- **Actual:** The top row of photos looked pale behind the white fade.
- **Fix:** The fade only goes as deep as needed (60 pt with filters, 130 pt in Fotos), with lower opacity. Status: **fixed** (built, look again).

## B3 · S4 · Portrait photos with info take up too much space
- **Steps:** Open a portrait photo → i.
- **Actual:** The photo took 55 % of the height, so the info cards only started low down.
- **Fix:** Portrait max 45 %, landscape max 55 %. Status: **fixed** (built, look again).

## B4 · S4 · Count barely readable over photos (dark mode)
- **Fix:** A light glow behind the title and count. Status: **fixed** (built, look again).

## To check (not reproduced)
- On a real iPhone: does Face ID (not the passcode) appear when opening "Gesperrt"? In the simulator it was the passcode prompt.
- AirPlay with a real Apple TV.

## B5 · S2 · Scrolling the preview strip breaks off at videos
- **Steps:** In the photo view, scroll across the preview strip until a video is in the middle.
- **Actual:** The strip disappeared as soon as a video was current (it was hidden for videos). The gesture broke off; you couldn't scroll any further.
- **Fix:** The strip stays for videos too and sits above the video bar. Status: **fixed, checked in the simulator**.

## B6 · S2 · Video fades the controls out during scrolling
- **Steps:** Open a video, scroll the strip for a few seconds.
- **Actual:** After a moment the video automatically hid all controls, including the strip, in the middle of the gesture.
- **Fix:** While the strip is being scrolled, nothing is hidden automatically (`VorschauLeiste.wischt` → `leisteAktiv`). Status: **fixed, checked in the simulator**.

## To check
- **Order of the strip and of swiping in Fotos:** Newer photos are on the left, older on the right. With Apple it's the other way round (newest at the far right, like in the grid). Not a bug in the strict sense, but different from Apple.
