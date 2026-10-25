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

Beim Start wird das Hauptfenster der App in den nativen Vollbildmodus geschaltet (macOS wechselt dafür in einen eigenen Space).
Das geht nur mit dem Bedienungshilfen-Recht: Beim ersten Spielstart fragt macOS danach (Systemeinstellungen → Datenschutz & Sicherheit →
Bedienungshilfen → MacSwitch). Ohne das Recht startet die App, wie sie will. Da `build_app.sh` ad-hoc signiert, muss das Recht nach
jedem neuen Build ggf. neu erteilt werden (Eintrag entfernen und wieder hinzufügen).

Mac kann fremde Fenster nicht in ein eigenes Fenster einbetten – die App läuft weiter als eigener Prozess.
