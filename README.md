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

## Spiele bauen (nxnative)

Die Kachel „Spiel bauen" (neben „Apps hinzufügen") macht mit [nxnative](https://github.com/seedds/nxnative) aus Switch-Dateien eine Mac-App
und legt sie ins Menü – dieselben Schritte wie die Fenster-App „NxNative Builder", nur für Mac-Builds und mit dem Datei-Browser statt Dateidialog.

Die Seite fragt der Reihe nach: nxnative-Ordner (Standard `~/GitHub/nxnative`), Hauptspiel (NSP/XCI/NSZ/XCZ), Update (optional), DLCs, `prod.keys`
(Browser startet in `~/.switch`) und Ausgabeordner. In der Ordner-Auswahl wählt die Leertaste (+) den aktuellen Ordner. Die Pfade merkt sich MacSwitch.
„Mac-App bauen" startet `scripts/build_ipa_from_nsp.py --platform mac` und danach `scripts/make_mac_app.py`; Fortschritt und Restzeit stehen auf der Seite,
Esc blendet sie aus (der Build läuft weiter, die Kachel zeigt den Stand), X bricht ab. Fertig ist die App `<Ausgabe>/<Spielname>.app`, sie landet automatisch im Menü.

- Die Skripte laufen über eine Login-Shell: `python3` dort braucht `lz4`, `capstone` und `fonttools`, Homebrew-Tools (xcodegen, spirv-cross, glslang, dotnet) wie in der nxnative-README.
- Beide Skripte müssen im nxnative-Ordner liegen (`make_mac_app.py` fehlt in einem frischen Klon). Ohne sie bleibt „Mac-App bauen" gesperrt.
- Die Dateien werden nur verlinkt, Zwischenergebnisse liegen in `<Ausgabe>/NxNative-Work/<Spielname>/` (ein zweiter Build geht schneller; danach löschbar).
- Der erste Build braucht 30–60 Minuten und etwa das Doppelte der NSP-Größe plus 10 GB frei.

### Update oder DLC nachinstallieren

Bei Spielen, die mit nxnative gebaut wurden, erscheint in der Fußzeile „+ Updates & DLC" (Taste `+` oder anklicken).
Die Seite verlinkt eine Update- oder DLC-Datei in den Arbeitsordner `<Ausgabe>/NxNative-Work/<Spielname>/` neben der App und baut mit „Neu bauen" neu.
Das gilt auch für Apps, die „NxNative Builder" gebaut hat; für alle anderen Apps gibt es die Fußzeile nicht.
Gleicher Name und Pfad: Menüeintrag und Spielstand bleiben. Das Skript übernimmt unveränderte Stufen aus dem letzten Lauf, nur die neue Version wird neu entpackt und umgeschrieben.
Y entfernt eine Datei wieder (nur den Link, nie die Datei selbst).

## Spielstart

MacSwitch deckt den Bildschirm ab, startet die App im Hintergrund und legt sich erst hinter sie, wenn ihr Fenster da ist.
Vollbild-Apps wirken dadurch wie Teil von MacSwitch, kleine Fenster liegen auf schwarzem Hintergrund.
Zurück ins Menü („Home"): ⌘Tab zu MacSwitch, Klick auf den schwarzen Hintergrund oder Spiel beenden.

Beim Start wird das Hauptfenster der App in den nativen Vollbildmodus geschaltet (macOS wechselt dafür in einen eigenen Space).
Das geht nur mit dem Bedienungshilfen-Recht: Beim ersten Spielstart fragt macOS danach (Systemeinstellungen → Datenschutz & Sicherheit →
Bedienungshilfen → MacSwitch). Ohne das Recht startet die App, wie sie will. Da `build_app.sh` ad-hoc signiert, muss das Recht nach
jedem neuen Build ggf. neu erteilt werden (Eintrag entfernen und wieder hinzufügen).

Mac kann fremde Fenster nicht in ein eigenes Fenster einbetten – die App läuft weiter als eigener Prozess.
