#!/usr/bin/env bash
# Baut die Mac-App (Release, universell, ad-hoc signiert) und packt sie als DMG mit
# „Programme“-Verknüpfung und Hintergrund. Ergebnis: build/Luna-<Version>.dmg
#   scripts/mac-release.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/App/project.yml" | sed -E 's/.*"(.*)".*/\1/')
DD=/tmp/luna-release
AUS="$ROOT/build"; ARBEIT=$(mktemp -d)
mkdir -p "$AUS"

echo "Baue Luna $VERSION für den Mac …"
(cd "$ROOT/App" && xcodegen -q)
xcodebuild -project "$ROOT/App/Lilith.xcodeproj" -scheme Lilith -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DD" build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet

INHALT="$ARBEIT/inhalt"; mkdir -p "$INHALT/.hintergrund"
ditto "$DD/Build/Products/Release/Lilith.app" "$INHALT/Luna.app"
ln -s /Applications "$INHALT/Programme"
swift "$ROOT/scripts/dmg-hintergrund.swift" "$INHALT/.hintergrund/hintergrund.png" 2>/dev/null

# Beschreibbares Abbild anlegen, Fenster einrichten, dann komprimieren.
RW="$ARBEIT/luna-rw.dmg"
hdiutil create -quiet -srcfolder "$INHALT" -volname "Luna" -fs HFS+ -format UDRW -size 80m "$RW"
GERAET=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
sleep 1
osascript <<APPLESCRIPT || echo "Hinweis: Fensterlayout konnte nicht gesetzt werden (Finder-Berechtigung). Das DMG funktioniert trotzdem."
tell application "Finder"
  tell disk "Luna"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".hintergrund:hintergrund.png"
    set position of item "Luna.app" of container window to {150, 200}
    set position of item "Programme" of container window to {450, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$GERAET"
rm -f "$AUS/Luna-$VERSION.dmg"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$AUS/Luna-$VERSION.dmg"
rm -rf "$ARBEIT"
echo "Fertig: $AUS/Luna-$VERSION.dmg"
