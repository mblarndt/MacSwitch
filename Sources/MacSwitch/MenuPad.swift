import AppKit

/// Das MacSwitch-Menü per iPhone: aus dem Zustand eines Controllers werden Menü-Tasten, die wie Tastaturereignisse ins Menü gehen.
/// Steuerkreuz und linker Stick wählen (gehalten wiederholt es), A bestätigt, B geht zurück, + öffnet die Optionen eines Spiels,
/// Home bringt MacSwitch nach vorn (auch aus einem laufenden Spiel).
struct MenuPad {
    enum Key: CaseIterable {
        case up, down, left, right, confirm, back, options, home

        var repeats: Bool { self == .up || self == .down || self == .left || self == .right }

        private var stroke: (characters: String, code: UInt16, flags: NSEvent.ModifierFlags)? {
            func arrow(_ function: Int, _ code: UInt16) -> (String, UInt16, NSEvent.ModifierFlags) {
                (String(Character(UnicodeScalar(UInt16(function))!)), code, [.numericPad, .function])
            }
            switch self {
            case .up: return arrow(NSUpArrowFunctionKey, 126)
            case .down: return arrow(NSDownArrowFunctionKey, 125)
            case .left: return arrow(NSLeftArrowFunctionKey, 123)
            case .right: return arrow(NSRightArrowFunctionKey, 124)
            case .confirm: return ("\r", 36, [])
            case .back: return ("\u{1B}", 53, [])
            case .options: return ("+", 24, [])
            case .home: return nil // keine Taste: MacSwitch holt sich selbst nach vorn
            }
        }

        /// Das Tastenereignis, das die Menüs (`onKeyPress`) wie von einer Tastatur lesen.
        func event(windowNumber: Int, isRepeat: Bool) -> NSEvent? {
            stroke.flatMap {
                NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: $0.flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                                 context: nil, characters: $0.characters, charactersIgnoringModifiers: $0.characters, isARepeat: isRepeat, keyCode: $0.code)
            }
        }
    }

    static let firstRepeat = 0.4
    static let repeatEvery = 0.11
    /// Ab so viel Stickauslenkung (von 0 bis 255, Mitte 128) zählt die Richtung.
    static let stickThreshold = 64

    /// Taste → wann sie wieder auslöst (unendlich: nie, sie wiederholt nicht).
    private var held = [Key: TimeInterval]()

    static func keys(in s: GamepadState) -> Set<Key> {
        var keys = Set<Key>()
        let lo = UInt8(128 - stickThreshold), hi = UInt8(128 + stickThreshold)
        if s.has(.up) || s.leftY < lo { keys.insert(.up) }
        if s.has(.down) || s.leftY > hi { keys.insert(.down) }
        if s.has(.left) || s.leftX < lo { keys.insert(.left) }
        if s.has(.right) || s.leftX > hi { keys.insert(.right) }
        if s.has(.a) { keys.insert(.confirm) }
        if s.has(.b) { keys.insert(.back) }
        if s.has(.plus) { keys.insert(.options) }
        if s.has(.home) { keys.insert(.home) }
        return keys
    }

    /// Der neue Zustand (nil: kein Controller). Liefert die Tasten, die jetzt auslösen: neu gedrückte und fällige Wiederholungen.
    mutating func update(_ state: GamepadState?, now: TimeInterval) -> [(key: Key, isRepeat: Bool)] {
        let pressed = state.map(Self.keys) ?? []
        for key in held.keys where !pressed.contains(key) { held[key] = nil }
        var fired = [(key: Key, isRepeat: Bool)]()
        for key in Key.allCases where pressed.contains(key) {
            if let due = held[key] {
                if due <= now { held[key] = now + Self.repeatEvery; fired.append((key, true)) }
            } else {
                held[key] = key.repeats ? now + Self.firstRepeat : .infinity
                fired.append((key, false))
            }
        }
        return fired
    }

    /// Wann `update` ohne neuen Zustand wieder etwas auslöst; nil, wenn nichts wiederholt.
    var nextRepeat: TimeInterval? { held.values.filter { $0.isFinite }.min() }
}

/// Macht aus den Zuständen einer Quelle (iPhone, Controller) Menü-Tasten samt Wiederholung für gehaltene Richtungen.
/// Alles läuft auf `queue`; `deliver` bekommt die Tasten auf dem Haupt-Thread.
final class MenuDriver {
    private var pad = MenuPad()
    private var timer: DispatchWorkItem?
    private let queue: DispatchQueue
    private let deliver: (MenuPad.Key, Bool) -> Void

    init(queue: DispatchQueue, deliver: @escaping (MenuPad.Key, Bool) -> Void) {
        self.queue = queue
        self.deliver = deliver
    }

    /// Der aktuelle Zustand der Quelle (nil: keiner). Muss auf `queue` aufgerufen werden.
    func update(_ state: GamepadState?) {
        let now = ProcessInfo.processInfo.systemUptime
        for (key, isRepeat) in pad.update(state, now: now) {
            DispatchQueue.main.async { self.deliver(key, isRepeat) }
        }
        timer?.cancel()
        timer = nil
        if let due = pad.nextRepeat {
            let item = DispatchWorkItem { [weak self] in self?.update(state) } // derselbe Zustand: nur die fälligen Wiederholungen
            timer = item
            queue.asyncAfter(deadline: .now() + max(0, due - now), execute: item)
        }
    }
}
