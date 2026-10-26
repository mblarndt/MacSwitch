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

### nxnative aktuell halten

nxnative hat keine Releases, im Repository kommen laufend Änderungen. MacSwitch prüft beim Start einmal im Hintergrund (`git fetch` im nxnative-Ordner), ob der Upstream-Zweig neuer ist,
und zeigt dann oben im Menü „nxnative: N neue Änderungen" (anklicken öffnet „Spiel bauen"). Dort aktualisiert die Zeile **nxnative aktualisieren** per `git pull --ff-only --autostash`
(A; ohne Neues prüft sie erneut). Das Update läuft nur, wenn es gefahrlos geht: Hat man eigene Commits oder lokale Änderungen an Dateien, die das Update ebenfalls ändert, bleibt alles
unverändert und die Zeile nennt den Grund (dann im Ordner committen oder im Terminal aktualisieren). Lokale Änderungen an anderen Dateien bleiben erhalten.
Gebaute Spiele übernehmen die Änderungen erst mit „Neu bauen". Ohne Netz oder ohne Git-Ordner passiert beim Start nichts.

### Update oder DLC nachinstallieren

Bei Spielen, die mit nxnative gebaut wurden, erscheint in der Fußzeile „+ Updates & DLC" (Taste `+` oder anklicken).
Die Seite verlinkt eine Update- oder DLC-Datei in den Arbeitsordner `<Ausgabe>/NxNative-Work/<Spielname>/` neben der App und baut mit „Neu bauen" neu.
Das gilt auch für Apps, die „NxNative Builder" gebaut hat; für alle anderen Apps gibt es die Fußzeile nicht.
Gleicher Name und Pfad: Menüeintrag und Spielstand bleiben. Das Skript übernimmt unveränderte Stufen aus dem letzten Lauf, nur die neue Version wird neu entpackt und umgeschrieben.
Y entfernt eine Datei wieder (nur den Link, nie die Datei selbst).

## iPhone als Controller

Das Dock-Symbol „Controller" öffnet die Seite für den iPhone-Host: A schaltet ihn ein, danach auf dem iPhone die App **MacSwitch Controller** öffnen
(sie verbindet sich per Bluetooth automatisch). Jedes iPhone bekommt einen Spielerplatz (1–4), die Seite zeigt Name und Antwortzeit. Ein wiederkehrendes
iPhone bekommt seinen Platz zurück; die Wahl „An/Aus" merkt sich MacSwitch.

Die Spiele lesen die Plätze über einen DSU-Server (cemuhook) auf `127.0.0.1:26760`, den MacSwitch dafür bereitstellt.
Der nxnative-Host hat dafür einen DSU-Client (`dm/host/dsu_pad.h`, `front_mac.m`): jedes iPhone ist dort ein Spieler wie ein echter Controller, mit analogen Sticks
(`DM_DSU=0` schaltet den Client ab). **Spiele müssen dafür einmal neu gebaut werden** („Neu bauen" in den Spiel-Optionen), damit sie den neuen Host enthalten.

- **Das MacSwitch-Menü steuert das iPhone mit dem niedrigsten Platz mit:** Steuerkreuz oder linker Stick wählen (gehalten wiederholt es), **A** bestätigt, **B** geht zurück
  (Esc), **+** öffnet „Updates & DLC" des gewählten Spiels, **Home** holt MacSwitch nach vorn, auch aus einem laufenden Spiel. Dasselbe gilt in den Seiten
  (Datei-Browser, Spiel bauen, Optionen, Controller). Im Spiel selbst reagiert das Menü nicht; dort gehen die Eingaben an das Spiel.
- Beim ersten Einschalten fragt macOS nach der Bluetooth-Berechtigung. Da `build_app.sh` ad-hoc signiert, fragt es nach jedem neuen Build wieder.
- MacSwitch und der MacHost aus AstrisPhoneController dürfen nicht gleichzeitig laufen (derselbe Port und dieselbe Bluetooth-Kennung); die Seite meldet „Port 26760 ist belegt".
- Der Host gibt keine Tasten aus und kennt keine Belegungen, nur den Weg über DSU. Die iPhone-App schickt auch nur Switch-Tasten und Sticks.
- Der DSU-Server (`DSUServer.swift`) ist eine Kopie aus AstrisPhoneController, ebenso der Lese-Teil des Funkprotokolls (`ControllerProtocol.swift`); die Senderseite
  steht in `iPhoneController/Logic/PadWire.swift`, und `Tests/MacSwitchTests/PadLogicTests.swift` prüft beide gegeneinander.

### Echte Controller (Xbox, PlayStation, Pro Controller …)

Ein Controller am Mac (Bluetooth oder USB-Kabel; Xbox: Pairing-Taste oben etwa 3 s halten, dann in Systemeinstellungen → Bluetooth verbinden) bedient das MacSwitch-Menü
wie das iPhone: Steuerkreuz oder linker Stick wählen, die rechte Fläche (Xbox B, die Switch-„A"-Position) bestätigt, die untere (Xbox A) geht zurück, Menü (+) öffnet
„Updates & DLC", Home (Guide-Knopf) holt MacSwitch nach vorn, auch aus einem laufenden Spiel. Die Controller-Seite zeigt iPhones und Controller als Spieler 1, 2, … in der Reihenfolge, in der sie sich verbunden haben (der erste ist Spieler 1); die Liste scrollt.

In den Spielen liest der nxnative-Host die Controller selbst; jeder ist dort ein Spieler (bis 8), die Tasten gelten nach Lage wie auf der Switch.
Controller dürfen jederzeit, auch im laufenden Spiel, dazukommen oder wegfallen: Ein Spiel für einen Spieler bekommt alle Controller (und das iPhone) zugleich als Spieler 1, man greift also
einfach zum anderen. In Spielen für mehrere gilt die Reihenfolge des Verbindens; ein Controller, der wiederkommt, bekommt seinen Spieler zurück. Die Reihenfolge im laufenden Spiel zu ändern geht nicht.

### iPhone-App „MacSwitch Controller"

Ein Switch-Controller im Querformat: A B X Y, L R ZL ZR, Steuerkreuz, beide Sticks, +, −, Capture, Home und die Stickklicks L3/R3, mit Multitouch
(mehrere Finger gleichzeitig, von Taste zu Taste rutschen). Mehr gibt es nicht: keine Tastenübersetzung, keine Layouts, keine Maus. Der Stick folgt dem Weg des Fingers
ab dem Aufsetzen, die Mitte muss man nicht treffen. Oben in der Mitte steht der Verbindungsstatus („Spieler 2 · 24 ms"). Home und Capture gehen mit,
die Spiele nutzen sie bisher nicht.

IPA bauen (braucht Xcode und `brew install xcodegen`):

```sh
iPhoneController/build_ipa.sh        # → iPhoneController/build/MacSwitchController.ipa
iPhoneController/build_ipa.sh sim    # → .app für den iOS-Simulator (nur zum Ansehen, dort gibt es kein Bluetooth)
```

Die IPA ist unsigniert und läuft ab iOS 16 auf dem iPhone. Zum Sideloaden mit AltStore: die IPA aufs iPhone bringen (AirDrop oder Dateien-App), in AltStore unter „My Apps" mit **+** wählen,
oder am Mac in AltServer „Sideload .ipa …". AltStore signiert sie mit deiner Apple-ID neu (bei einer kostenlosen Apple-ID läuft die App 7 Tage, dann in AltStore erneuern).
Beim ersten Start fragt iOS nach der Bluetooth-Berechtigung.

## Spielstart

MacSwitch deckt den Bildschirm ab, startet die App im Hintergrund und legt sich erst hinter sie, wenn ihr Fenster da ist.
Vollbild-Apps wirken dadurch wie Teil von MacSwitch, kleine Fenster liegen auf schwarzem Hintergrund.
Zurück ins Menü („Home"): ⌘Tab zu MacSwitch, Klick auf den schwarzen Hintergrund oder Spiel beenden.

Beim Start wird das Hauptfenster der App in den nativen Vollbildmodus geschaltet (macOS wechselt dafür in einen eigenen Space).
Das geht nur mit dem Bedienungshilfen-Recht: Beim ersten Spielstart fragt macOS danach (Systemeinstellungen → Datenschutz & Sicherheit →
Bedienungshilfen → MacSwitch). Ohne das Recht startet die App, wie sie will. Da `build_app.sh` ad-hoc signiert, muss das Recht nach
jedem neuen Build ggf. neu erteilt werden (Eintrag entfernen und wieder hinzufügen).

Mac kann fremde Fenster nicht in ein eigenes Fenster einbetten – die App läuft weiter als eigener Prozess.
