# MacSwitch

Native macOS-App (SwiftUI) im Look des Nintendo-Switch-Home-Menüs. Normale Mac-Apps erscheinen als Kacheln und starten aus dem Menü heraus.

## Bauen & starten

Voraussetzung: macOS 14+, Xcode bzw. Command Line Tools (Swift 5.9+).

```sh
./build_app.sh
open build/MacSwitch.app
```

MacSwitch startet im Vollbild (rahmenlos, ohne Dock und Menüleiste). Beenden: Power-Symbol unten rechts oder ⌘Q.

## Apps hinzufügen

- Regler-Symbol unten → „Spiel hinzufügen…" öffnet den Datei-Browser (startet in `/Applications`).
  ↑ ↓ wählen, → / Enter öffnet Ordner bzw. fügt die App hinzu, ← geht einen Ordner hoch, Esc schließt.
- Oder eine `.app` aufs Fenster ziehen.

Hinzugefügt wird als Symlink in `~/Library/Application Support/MacSwitch/Games` (nichts wird kopiert).
Entfernen: Symlink dort löschen („Games-Ordner öffnen" im Menü).

## Spielstart

MacSwitch deckt den Bildschirm ab, startet die App im Hintergrund und legt sich erst hinter sie, wenn ihr Fenster da ist.
Vollbild-Apps wirken dadurch wie Teil von MacSwitch, kleine Fenster liegen auf schwarzem Hintergrund.
Zurück ins Menü („Home"): ⌘Tab zu MacSwitch, Klick auf den schwarzen Hintergrund oder Spiel beenden.

Mac kann fremde Fenster nicht in ein eigenes Fenster einbetten – die App läuft weiter als eigener Prozess.
