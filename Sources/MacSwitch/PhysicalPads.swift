import GameController

/// Was ein echter Controller (Xbox, PlayStation, Pro Controller …) gerade zeigt, unabhängig vom Framework: Flächentasten nach Lage, Achsen von −1 bis 1.
struct PadSnapshot {
    var right = false, bottom = false, top = false, left = false // Xbox: B, A, Y, X
    var l = false, r = false, zl = false, zr = false
    var menu = false, view = false, l3 = false, r3 = false, home = false
    var up = false, down = false, dpadLeft = false, dpadRight = false
    var lx: Float = 0, ly: Float = 0, rx: Float = 0, ry: Float = 0 // Y: oben ist positiv, wie im GameController-Framework

    init() {}

    init(_ g: GCExtendedGamepad) {
        right = g.buttonB.isPressed; bottom = g.buttonA.isPressed; top = g.buttonY.isPressed; left = g.buttonX.isPressed
        l = g.leftShoulder.isPressed; r = g.rightShoulder.isPressed; zl = g.leftTrigger.isPressed; zr = g.rightTrigger.isPressed
        menu = g.buttonMenu.isPressed; view = g.buttonOptions?.isPressed ?? false
        l3 = g.leftThumbstickButton?.isPressed ?? false; r3 = g.rightThumbstickButton?.isPressed ?? false; home = g.buttonHome?.isPressed ?? false
        up = g.dpad.up.isPressed; down = g.dpad.down.isPressed; dpadLeft = g.dpad.left.isPressed; dpadRight = g.dpad.right.isPressed
        lx = g.leftThumbstick.xAxis.value; ly = g.leftThumbstick.yAxis.value; rx = g.rightThumbstick.xAxis.value; ry = g.rightThumbstick.yAxis.value
    }
}

extension GamepadState {
    /// Wie im nxnative-Host (front_mac.m): die Tasten nach Lage wie auf der Switch, rechts A, unten B, oben X, links Y; Menü ist +, Ansicht −.
    init(_ s: PadSnapshot) {
        self.init()
        let pairs: [(Bool, PadButton)] = [(s.right, .a), (s.bottom, .b), (s.top, .x), (s.left, .y), (s.l, .l), (s.r, .r), (s.zl, .zl), (s.zr, .zr),
                                          (s.menu, .plus), (s.view, .minus), (s.l3, .l3), (s.r3, .r3), (s.home, .home),
                                          (s.up, .up), (s.down, .down), (s.dpadLeft, .left), (s.dpadRight, .right)]
        for (on, button) in pairs where on { buttons |= button.bit }
        func axis(_ v: Float) -> UInt8 { UInt8(min(255, max(0, (128 + v * 127).rounded()))) }
        leftX = axis(s.lx); leftY = axis(-s.ly) // Y von oben nach unten, wie im Funkprotokoll
        rightX = axis(s.rx); rightY = axis(-s.ry)
    }

    /// Mehrere Controller wie einer: Tasten zusammen, bei den Achsen gewinnt die größere Auslenkung.
    static func merged(_ states: [GamepadState]) -> GamepadState {
        func stronger(_ a: UInt8, _ b: UInt8) -> UInt8 { abs(Int(a) - 128) >= abs(Int(b) - 128) ? a : b }
        return states.reduce(GamepadState()) { m, s in
            var r = m
            r.buttons |= s.buttons
            r.leftX = stronger(m.leftX, s.leftX); r.leftY = stronger(m.leftY, s.leftY)
            r.rightX = stronger(m.rightX, s.rightX); r.rightY = stronger(m.rightY, s.rightY)
            return r
        }
    }
}

/// Echte Controller am Mac (Bluetooth oder Kabel): bedienen das MacSwitch-Menü wie das iPhone (MenuPad) und erscheinen auf der Controller-Seite.
/// In den Spielen liest sie der nxnative-Host selbst (jeder Controller ein Spieler); hier geht es nur um das Menü.
final class PhysicalPads: ObservableObject {
    struct Device: Equatable {
        let name: String
        let since: Date
    }

    /// Die verbundenen Controller mit dem Zeitpunkt, seit dem sie verbunden sind (beim Start des Programms schon verbundene: mit dem Start).
    @Published private(set) var devices = [Device]()
    private var since = [ObjectIdentifier: Date]()
    /// Menü-Tasten (Taste, Wiederholung) auf dem Haupt-Thread. Gesetzt von der HomeView.
    var onMenu: ((MenuPad.Key, Bool) -> Void)?
    private lazy var driver = MenuDriver(queue: .main) { [weak self] key, isRepeat in self?.onMenu?(key, isRepeat) }

    init() {
        // Auch im Hintergrund lesen: so holt Home MacSwitch aus einem laufenden Spiel nach vorn. Menü-Tasten gelten nur, wenn MacSwitch vorn ist (HomeView).
        GCController.shouldMonitorBackgroundEvents = true
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    private func pads() -> [GCController] { GCController.controllers().filter { $0.extendedGamepad != nil } }

    private func refresh() {
        let all = pads(), now = Date()
        for pad in all where since[ObjectIdentifier(pad)] == nil { since[ObjectIdentifier(pad)] = now }
        since = since.filter { key, _ in all.contains { ObjectIdentifier($0) == key } }
        devices = all.map { Device(name: $0.vendorName ?? "Controller", since: since[ObjectIdentifier($0)] ?? now) }
        for pad in all {
            pad.extendedGamepad?.valueChangedHandler = { [weak self] _, _ in self?.changed() }
            pad.extendedGamepad?.buttonHome?.preferredSystemGestureState = .disabled // der Home-Knopf gehört MacSwitch, nicht dem System
        }
        changed()
    }

    private func changed() {
        let states = pads().compactMap { $0.extendedGamepad }.map { GamepadState(PadSnapshot($0)) }
        driver.update(states.isEmpty ? nil : GamepadState.merged(states))
    }
}
