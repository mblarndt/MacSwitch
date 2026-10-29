#!/bin/bash
# Baut build/MacSwitch.app (ad-hoc signiert, nicht sandboxed – nötig für den Games-Ordner und das Starten fremder Apps).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/MacSwitch.app
# Läuft noch eine alte Instanz, holt `open` nur diese nach vorn (gleiche Bundle-ID) statt die neue zu starten.
pkill -x MacSwitch || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/MacSwitch" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"

# App-Icon: aus der 1024er-PNG ein .icns bauen (sips/iconutil gibt es auf jedem Mac).
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Support/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Support/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Gebaut aus Commit $(git rev-parse --short HEAD 2>/dev/null || echo '?') – Fertig: open $APP"
