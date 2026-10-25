#!/bin/bash
# Baut build/MacSwitchController.ipa: die iPhone-App zum Sideloaden (AltStore, Sideloadly, …). Die IPA ist unsigniert: AltStore signiert sie beim Installieren
# mit deiner Apple-ID neu. Braucht Xcode und XcodeGen (brew install xcodegen).
# Mit `./build_ipa.sh sim` entsteht stattdessen build/Simulator/MacSwitchController.app für den iOS-Simulator (zum Ansehen, Bluetooth gibt es dort nicht).
set -euo pipefail
cd "$(dirname "$0")"
B=build
mkdir -p $B
xcodegen generate --spec project.yml --quiet
if [ "${1:-}" = "sim" ]; then
    xcodebuild -project MacSwitchController.xcodeproj -scheme MacSwitchController -configuration Debug -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath $B/derived CODE_SIGNING_ALLOWED=NO build | tail -3
    rm -rf $B/Simulator && mkdir -p $B/Simulator
    cp -R $B/derived/Build/Products/Debug-iphonesimulator/MacSwitchController.app $B/Simulator/
    codesign --force --sign - $B/Simulator/MacSwitchController.app
    echo "Fertig: $B/Simulator/MacSwitchController.app"
    exit 0
fi
xcodebuild -project MacSwitchController.xcodeproj -scheme MacSwitchController -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' -derivedDataPath $B/derived CODE_SIGNING_ALLOWED=NO build | tail -3
rm -rf $B/Payload $B/MacSwitchController.ipa && mkdir -p $B/Payload
cp -R $B/derived/Build/Products/Release-iphoneos/MacSwitchController.app $B/Payload/
(cd $B && zip -qry MacSwitchController.ipa Payload)
rm -rf $B/Payload
echo "Fertig: $(pwd)/$B/MacSwitchController.ipa"
