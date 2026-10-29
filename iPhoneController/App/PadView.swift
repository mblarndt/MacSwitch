import UIKit

/// Der Controller auf dem Bildschirm: zeichnet das Layout (PadLayout) und reicht die Finger an dessen Zustandsberechnung weiter.
/// Es gibt nur Switch-Tasten und Sticks: was gedrückt ist, geht als `PadState` hinaus, mehr nicht.
final class PadView: UIView {
    var onState: ((PadState) -> Void)?
    /// Verbindungsanzeige oben in der Mitte.
    var badge = "" { didSet { setNeedsDisplay() } }

    private var layout = PadLayout(bounds: .zero)
    private var state = PadState()
    private var order = [ObjectIdentifier]() // in der Reihenfolge, in der die Finger aufgesetzt haben
    private var fingers = [ObjectIdentifier: PadLayout.Touch]()

    private let background = UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    private let key = UIColor(red: 0.21, green: 0.22, blue: 0.24, alpha: 1)
    private let ring = UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1)
    private let accent = UIColor(red: 0.04, green: 0.74, blue: 0.90, alpha: 1)
    private let ink = UIColor(white: 0.92, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = background
    }

    required init?(coder: NSCoder) { fatalError("nur im Code") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layout = PadLayout(bounds: bounds.inset(by: safeAreaInsets))
        setNeedsDisplay()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    // MARK: Finger

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t), p = t.location(in: self)
            fingers[id] = PadLayout.Touch(origin: p, point: p)
            order.append(id)
        }
        update()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { fingers[ObjectIdentifier(t)]?.point = t.location(in: self) }
        update()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches { fingers[ObjectIdentifier(t)] = nil }
        order.removeAll { fingers[$0] == nil }
        update()
    }

    /// Lässt alles los, etwa wenn die App in den Hintergrund geht.
    func releaseAll() {
        fingers.removeAll()
        order.removeAll()
        update()
    }

    private func update() {
        let next = layout.state(for: order.compactMap { fingers[$0] })
        guard next != state else { return }
        state = next
        onState?(next)
        setNeedsDisplay()
    }

    // MARK: Zeichnen

    override func draw(_ rect: CGRect) {
        for key in layout.keys { draw(key) }
        drawDPad()
        for stick in layout.sticks { draw(stick) }
        drawBadge()
    }

    private func draw(_ k: PadLayout.Key) {
        let on = state.has(k.button)
        (on ? accent : key).setFill()
        let path: UIBezierPath
        switch k.shape {
        case .circle(let c, let r): path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .pill(let rect): path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        }
        path.fill()
        let center = k.shape.center, u = layout.unit
        switch k.button {
        case .home: symbol("house.fill", at: center, size: u * 0.085, on: on)
        case .capture: symbol("camera.fill", at: center, size: u * 0.08, on: on)
        default: label(Self.text(k.button), at: center, size: Self.fontSize(k.button) * u, on: on)
        }
    }

    private static func text(_ b: SwitchButton) -> String {
        switch b {
        case .minus: "−"
        case .plus: "+"
        default: "\(b)".uppercased()
        }
    }

    private static func fontSize(_ b: SwitchButton) -> CGFloat {
        switch b {
        case .a, .b, .x, .y: 0.10
        case .minus, .plus: 0.095
        case .l3, .r3: 0.05
        default: 0.065
        }
    }

    private func drawDPad() {
        let c = layout.dpad.center, r = layout.dpad.radius, t = r * 0.62
        let arms: [(SwitchButton, CGRect)] = [
            (.up, CGRect(x: c.x - t / 2, y: c.y - r, width: t, height: r - t / 2)),
            (.down, CGRect(x: c.x - t / 2, y: c.y + t / 2, width: t, height: r - t / 2)),
            (.left, CGRect(x: c.x - r, y: c.y - t / 2, width: r - t / 2, height: t)),
            (.right, CGRect(x: c.x + t / 2, y: c.y - t / 2, width: r - t / 2, height: t)),
        ]
        key.setFill()
        UIBezierPath(roundedRect: CGRect(x: c.x - t / 2, y: c.y - t / 2, width: t, height: t), cornerRadius: 4).fill()
        for (button, rect) in arms {
            (state.has(button) ? accent : key).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        }
    }

    private func draw(_ stick: PadLayout.Stick) {
        let c = stick.center, base = stick.travel * 1.2, knob = stick.travel * 0.62
        let axes = stick.side == .left ? (state.leftX, state.leftY) : (state.rightX, state.rightY)
        let dx = (CGFloat(axes.0) - 128) / 127 * stick.travel, dy = (CGFloat(axes.1) - 128) / 127 * stick.travel
        UIColor(white: 0.13, alpha: 1).setFill()
        ring.setStroke()
        let b = UIBezierPath(ovalIn: CGRect(x: c.x - base, y: c.y - base, width: 2 * base, height: 2 * base))
        b.lineWidth = 3
        b.fill(); b.stroke()
        (dx != 0 || dy != 0 ? accent : key).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x + dx - knob, y: c.y + dy - knob, width: 2 * knob, height: 2 * knob)).fill()
    }

    private func drawBadge() {
        guard let zl = layout.keys.first(where: { $0.button == .zl }), case .pill(let rect) = zl.shape else { return }
        label(badge, at: CGPoint(x: bounds.inset(by: safeAreaInsets).midX, y: rect.midY), size: layout.unit * 0.055, on: false, color: UIColor(white: 0.55, alpha: 1))
    }

    private func label(_ s: String, at p: CGPoint, size: CGFloat, on: Bool, color: UIColor? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color ?? (on ? UIColor.black : ink)]
        let text = NSAttributedString(string: s, attributes: attributes), box = text.size()
        text.draw(at: CGPoint(x: p.x - box.width / 2, y: p.y - box.height / 2))
    }

    private func symbol(_ name: String, at p: CGPoint, size: CGFloat, on: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(on ? .black : ink, renderingMode: .alwaysOriginal) else { return }
        image.draw(at: CGPoint(x: p.x - image.size.width / 2, y: p.y - image.size.height / 2))
    }
}
