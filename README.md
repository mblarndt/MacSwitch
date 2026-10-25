# MacSwitch

Native macOS-App (SwiftUI) im Look des Nintendo-Switch-Home-Menüs. IPA-Dateien im Games-Ordner erscheinen als Kacheln.

## Bauen & starten

Voraussetzung: macOS 14+, Xcode bzw. Command Line Tools (Swift 5.9+).

```sh
./build_app.sh
open build/MacSwitch.app
```

## Spiele hinzufügen

Games-Ordner: `~/Library/Application Support/MacSwitch/Games`

- IPA-Dateien dorthin kopieren, **oder**
- IPA aufs Fenster ziehen, **oder**
- Systemeinstellungen (Regler-Symbol unten) → „Spiel hinzufügen…" / „Games-Ordner öffnen".

Titel und Icon werden aus der IPA gelesen.

## Bedienung

← → wählen, ↓ / ↑ wechselt zwischen Spielen und Menüleiste, Enter/Leertaste startet, Mausklick geht auch.

## Spiele starten

Ein Spiel wird per `open` ans System übergeben. iOS-Apps laufen nur auf Apple-Silicon-Macs, und die IPA muss dafür
von einer App geöffnet werden können (z. B. [PlayCover](https://playcover.io) als Standard-App für `.ipa`).
Die App selbst führt keine IPAs aus.
