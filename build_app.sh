#!/bin/bash
# Baut build/MacSwitch.app (ad-hoc signiert, nicht sandboxed – nötig für unzip und den Games-Ordner).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/MacSwitch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MacSwitch" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Fertig: open $APP"
