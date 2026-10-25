import CoreGraphics
import Foundation

/// Wo die Bedienelemente des Switch-Controllers liegen und was ein Finger an einer Stelle bedient. Rein geometrisch, ohne UIKit:
/// die App zeichnet das Layout und gibt ihm die Finger, der Test prüft beides.
struct PadLayout: Equatable {
    enum Shape: Equatable {
        case circle(center: CGPoint, radius: CGFloat)
        case pill(CGRect) // Schultertasten: Rechteck mit halbrunden Enden

        var center: CGPoint {
            switch self {
            case .circle(let c, _): c
            case .pill(let r): CGPoint(x: r.midX, y: r.midY)
            }
        }

        /// nil, wenn der Punkt außerhalb liegt (mit etwas Spielraum für den Daumen); sonst je kleiner, desto näher an der Mitte.
        func score(_ p: CGPoint) -> CGFloat? {
            switch self {
            case .circle(let c, let r):
                let d = hypot(p.x - c.x, p.y - c.y)
                return d <= r * 1.15 + 4 ? d / r : nil
            case .pill(let rect):
                let big = rect.insetBy(dx: -6, dy: -6)
                guard big.contains(p) else { return nil }
                return max(abs(p.x - rect.midX) / (rect.width / 2), abs(p.y - rect.midY) / (rect.height / 2))
            }
        }
    }

    struct Key: Equatable {
        let button: SwitchButton
        let shape: Shape
    }

    enum Side { case left, right }

    /// `travel`: Weg des Fingers bis zum vollen Ausschlag. `zone`: wo ein Finger den Stick greift.
    struct Stick: Equatable {
        let side: Side
        let center: CGPoint
        let travel: CGFloat
        let zone: CGFloat
    }

    struct DPad: Equatable {
        let center: CGPoint
        let radius: CGFloat
    }

    let keys: [Key]
    let sticks: [Stick]
    let dpad: DPad
    /// Einheit des Layouts: alle Maße sind Bruchteile davon.
    let unit: CGFloat

    /// `bounds`: die nutzbare Fläche (der Bildschirm ohne Notch und Home-Indikator).
    init(bounds b: CGRect) {
        let s = min(b.height, b.width / 2.2)
        let top = b.minY + max(0, (b.height - s) / 2)
        func at(_ x: CGFloat, _ y: CGFloat, fromRight: Bool = false) -> CGPoint { CGPoint(x: (fromRight ? b.maxX - x * s : b.minX + x * s), y: top + y * s) }
        func circle(_ c: CGPoint, _ r: CGFloat) -> Shape { .circle(center: c, radius: r * s) }

        var keys = [Key]()
        // Flächentasten wie auf der Switch: A rechts, B unten, X oben, Y links.
        let face = at(0.30, 0.45, fromRight: true), o = 0.165 * s
        keys += [Key(button: .a, shape: circle(CGPoint(x: face.x + o, y: face.y), 0.095)),
                 Key(button: .b, shape: circle(CGPoint(x: face.x, y: face.y + o), 0.095)),
                 Key(button: .x, shape: circle(CGPoint(x: face.x, y: face.y - o), 0.095)),
                 Key(button: .y, shape: circle(CGPoint(x: face.x - o, y: face.y), 0.095))]
        // Schultertasten oben: ZL, L links, R, ZR rechts.
        let w = 0.30 * s, h = 0.13 * s
        keys += [Key(button: .zl, shape: .pill(CGRect(x: b.minX, y: top, width: w, height: h))),
                 Key(button: .l, shape: .pill(CGRect(x: b.minX + 0.32 * s, y: top, width: w, height: h))),
                 Key(button: .r, shape: .pill(CGRect(x: b.maxX - 0.32 * s - w, y: top, width: w, height: h))),
                 Key(button: .zr, shape: .pill(CGRect(x: b.maxX - w, y: top, width: w, height: h)))]
        // Mitte: Minus und Plus, darunter Capture und Home, darunter die Stickklicks.
        let mx = b.midX, dx = 0.17 * s, rc = 0.065
        let rows: [(CGFloat, SwitchButton, SwitchButton)] = [(0.30, .minus, .plus), (0.52, .capture, .home), (0.74, .l3, .r3)]
        for (y, left, right) in rows {
            keys += [Key(button: left, shape: circle(CGPoint(x: mx - dx, y: top + y * s), rc)),
                     Key(button: right, shape: circle(CGPoint(x: mx + dx, y: top + y * s), rc))]
        }
        self.keys = keys
        // Wie beim Pro Controller: links der Stick oben und das Steuerkreuz darunter, rechts die Flächentasten oben und der Stick darunter.
        sticks = [Stick(side: .left, center: at(0.30, 0.45), travel: 0.14 * s, zone: 0.22 * s),
                  Stick(side: .right, center: at(0.62, 0.78, fromRight: true), travel: 0.14 * s, zone: 0.22 * s)]
        dpad = DPad(center: at(0.62, 0.78), radius: 0.17 * s)
        unit = s
    }

    // MARK: Finger

    /// Ein Finger: wo er aufgesetzt hat und wo er jetzt ist.
    struct Touch: Equatable {
        var origin: CGPoint
        var point: CGPoint
    }

    /// Die Taste unter dem Punkt; liegen mehrere in Reichweite, die mit der nächsten Mitte.
    func key(at p: CGPoint) -> SwitchButton? {
        keys.compactMap { k in k.shape.score(p).map { (k.button, $0) } }.min { $0.1 < $1.1 }?.0
    }

    /// Die Richtungen des Steuerkreuzes unter dem Punkt: eine, in den Ecken zwei. Genau in der Mitte keine.
    func dpadDirections(at p: CGPoint) -> [SwitchButton] {
        let dx = p.x - dpad.center.x, dy = p.y - dpad.center.y, d = hypot(dx, dy)
        guard d <= dpad.radius * 1.15, d > dpad.radius * 0.22 else { return [] }
        var out = [SwitchButton]()
        if dy < -0.38 * d { out.append(.up) }
        if dy > 0.38 * d { out.append(.down) }
        if dx < -0.38 * d { out.append(.left) }
        if dx > 0.38 * d { out.append(.right) }
        return out
    }

    /// Der Stick, den ein Finger greift, der hier aufsetzt: nur, wenn dort keine Taste und kein Steuerkreuz ist.
    func stick(at origin: CGPoint) -> Stick? {
        guard key(at: origin) == nil, dpadDirections(at: origin).isEmpty else { return nil }
        return sticks.first { hypot(origin.x - $0.center.x, origin.y - $0.center.y) <= $0.zone }
    }

    /// Der Controller-Zustand zu allen Fingern, in der Reihenfolge, in der sie aufgesetzt haben. Ein Finger, der einen Stick gegriffen hat, steuert ihn
    /// bis zum Loslassen (die Auslenkung ist der Weg vom Aufsetzpunkt, der Daumen muss die Mitte nicht treffen); jeder andere drückt, was unter ihm liegt,
    /// und kann von Taste zu Taste rutschen.
    func state(for touches: [Touch]) -> PadState {
        var state = PadState()
        var taken = Set<Side>()
        for t in touches {
            if let stick = stick(at: t.origin) {
                guard taken.insert(stick.side).inserted else { continue }
                var vx = (t.point.x - t.origin.x) / stick.travel, vy = (t.point.y - t.origin.y) / stick.travel
                let m = hypot(vx, vy)
                if m > 1 { vx /= m; vy /= m }
                let (x, y) = (PadState.axis(Double(vx)), PadState.axis(Double(vy))) // Y: oben ist 0, wie auf dem Bildschirm
                if stick.side == .left { state.leftX = x; state.leftY = y } else { state.rightX = x; state.rightY = y }
            } else {
                if let button = key(at: t.point) { state.press(button) }
                for direction in dpadDirections(at: t.point) { state.press(direction) }
            }
        }
        return state
    }
}
