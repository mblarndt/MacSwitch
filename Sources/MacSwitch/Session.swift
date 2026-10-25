import ApplicationServices
import AppKit
import SwiftUI

/// Startet eine Mac-App so, dass sie wie Teil von MacSwitch wirkt: MacSwitch deckt den ganzen Bildschirm ab (eigenes Fenster
/// oberhalb von allem), startet die App im Hintergrund und legt sich erst hinter sie, wenn ihr Fenster da ist.
/// Echtes Einbetten fremder Fenster gibt macOS nicht her – kleine Fenster liegen daher auf dem schwarzen MacSwitch-Hintergrund.
final class GameSession: ObservableObject {
    enum State { case idle, launching(Game), running(Game) }

    @Published private(set) var state = State.idle
    private weak var window: NSWindow?
    private var app: NSRunningApplication?

    var game: Game? {
        switch state {
        case .idle: nil
        case .launching(let g), .running(let g): g
        }
    }

    var isLaunching: Bool { if case .launching = state { true } else { false } }

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let quit = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, let quit, quit == self.app { self.home() } // Spiel beendet → zurück ins Menü
        }
        let nc = NotificationCenter.default
        // Verlässt man MacSwitch (⌘Tab, Spiel aktiv), muss das Vollbildfenster nach hinten, sonst deckt es andere Apps ab.
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.window?.level = .normal
        }
        // Zurück zu MacSwitch (⌘Tab, Dock, Klick auf den schwarzen Hintergrund) = Home-Taste.
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.home()
        }
    }

    func attach(_ w: NSWindow) {
        guard window == nil else { return }
        window = w
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
        w.isMovable = false
        home()
    }

    func start(_ game: Game) {
        guard case .idle = state else { return }
        state = .launching(game)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false // MacSwitch bleibt aktiv → Dock und Menüleiste bleiben versteckt, bis die App ihr Fenster hat
        NSWorkspace.shared.openApplication(at: game.url.resolvingSymlinksInPath(), configuration: cfg) { app, _ in
            DispatchQueue.main.async {
                guard let app else { NSSound.beep(); self.home(); return } // shortcut: Startfehler nur als Signalton, upgrade: Meldung im Menü
                self.app = app
                self.waitForWindow(until: Date().addingTimeInterval(10))
            }
        }
    }

    /// Zurück ins Menü; eine laufende App bleibt im Hintergrund und wird beim erneuten Start einfach wieder nach vorn geholt.
    func home() {
        app = nil
        state = .idle
        guard let window else { return }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        if let screen = window.screen ?? NSScreen.main { window.setFrame(screen.frame, display: true) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // shortcut: Fenstererkennung per Polling; ohne sichtbares Fenster nach 10 s trotzdem aufdecken.
    private func waitForWindow(until deadline: Date) {
        guard let app, case .launching = state else { return }
        if Date() > deadline || Self.hasWindow(app.processIdentifier) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.reveal() } // erstes Bild der App soll schon gezeichnet sein
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.waitForWindow(until: deadline) }
        }
    }

    private func reveal() {
        guard let app, case .launching(let game) = state else { return }
        state = .running(game)
        window?.level = .normal
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Self.enterFullScreen(app) } // Fenster ist nach dem Aktivieren erst kurz danach "focused"
    }

    /// Schaltet das Hauptfenster der App in den nativen Vollbildmodus. Braucht das Bedienungshilfen-Recht; ohne bleibt das Fenster, wie es ist.
    private static func enterFullScreen(_ app: NSRunningApplication) {
        // "AXTrustedCheckOptionPrompt" = kAXTrustedCheckOptionPrompt: fragt beim ersten Mal nach dem Recht.
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var window: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, attr as CFString, &window) == .success, let window else { continue }
            // shortcut: Fehler (Fenster ohne Vollbild-Knopf) werden ignoriert, upgrade: Fenster stattdessen per AXSize auf Bildschirmgröße ziehen.
            AXUIElementSetAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, kCFBooleanTrue)
            return
        }
    }

    private static func hasWindow(_ pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid, (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return false }
            return r.width > 100 && r.height > 100
        }
    }
}

/// Reicht das NSWindow der SwiftUI-Szene nach außen.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
