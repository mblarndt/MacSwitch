import CoreGraphics
import XCTest
@testable import MacSwitch
@testable import PadLogic

/// Die iPhone-Seite (PadLogic) gegen den Mac-Host (ControllerProtocol.swift) und das Layout gegen Finger.
final class PadWireTests: XCTestCase {
    func testStateIsReadBackByTheMacHost() throws {
        for b in SwitchButton.allCases {
            XCTAssertEqual(PadButton(rawValue: b.rawValue).map { String(describing: $0) }, "\(b)", "Taste \(b): gleicher Name an gleicher Bitposition wie am Mac")
        }
        XCTAssertEqual([PadBLE.service, PadBLE.input, PadBLE.presence], [BLEIDs.service, BLEIDs.input, BLEIDs.presence])

        var s = PadState()
        s.press(.a); s.press(.zr); s.press(.right); s.press(.capture)
        s.leftX = PadState.axis(1); s.leftY = PadState.axis(-1); s.rightX = 7
        let g = try XCTUnwrap(GamepadState(data: s.data))
        XCTAssertEqual(g.buttons, s.buttons)
        XCTAssertTrue(g.has(.a) && g.has(.zr) && g.has(.right) && g.has(.capture) && !g.has(.b) && !g.has(.l3))
        XCTAssertEqual([g.leftX, g.leftY, g.rightX, g.rightY], [255, 1, 7, 128])
        XCTAssertEqual(PadState().data.count, 9)
        XCTAssertEqual(GamepadState(data: PadState().data), .neutral)
    }

    func testHelloPingAndPlayerMessages() throws {
        let id = UUID()
        let hello = try XCTUnwrap(Hello(data: PadWire.hello(deviceID: id, name: "Bens iPhone", maxLength: 100)))
        XCTAssertEqual(hello.deviceID, id)
        XCTAssertEqual(hello.name, "Bens iPhone")
        XCTAssertEqual(Hello(data: PadWire.hello(deviceID: id, name: "Bens iPhone", maxLength: 17 + 4))?.name, "Bens", "der Name wird gekürzt")
        XCTAssertEqual(Hello(data: PadWire.hello(deviceID: id, name: "ab😀", maxLength: 17 + 3))?.name, "ab", "nie mitten in einem Zeichen")

        let request = try XCTUnwrap(Ping.parseRequest(PadWire.ping(sequence: 513, lastRoundTrip: 300)))
        XCTAssertEqual(request.sequence, 513)
        XCTAssertEqual(request.lastRoundTrip, 255, "Antwortzeit passt in ein Byte")
        XCTAssertEqual(Ping.parseRequest(PadWire.ping(sequence: 1, lastRoundTrip: nil))?.lastRoundTrip, 0)
        XCTAssertEqual(PadWire.pingReply(Ping.reply(sequence: 513)), 513)
        XCTAssertNil(PadWire.pingReply(Data([0x50, 1])))

        XCTAssertEqual(PadWire.player(PlayerMessage.data(player: 3)), 3)
        XCTAssertEqual(PadWire.player(PlayerMessage.data(player: nil)), 0, "kein Platz frei")
        XCTAssertNil(PadWire.player(Data([0x53])))
    }
}

final class PadLayoutTests: XCTestCase {
    /// Nutzbare Flächen: iPhone 15 (Notch und Home-Indikator abgezogen), ein kleines iPhone ohne Notch, ein großes.
    private let areas = [CGRect(x: 59, y: 0, width: 734, height: 372), CGRect(x: 0, y: 0, width: 667, height: 375), CGRect(x: 59, y: 0, width: 814, height: 409)]
    private let area = CGRect(x: 59, y: 0, width: 734, height: 372)

    func testEveryControlLiesInsideAndIsFoundAtItsOwnCenter() {
        for bounds in areas {
            let layout = PadLayout(bounds: bounds), fit = bounds.insetBy(dx: -1, dy: -1)
            XCTAssertEqual(Set(layout.keys.map(\.button)), Set(SwitchButton.allCases).subtracting([.up, .down, .left, .right]), "alle Tasten, das Steuerkreuz getrennt")
            for key in layout.keys {
                XCTAssertEqual(layout.key(at: key.shape.center), key.button, "\(key.button) in \(bounds)")
                switch key.shape {
                case .circle(let c, let r): XCTAssertTrue(fit.contains(CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), "\(key.button) liegt im Bild")
                case .pill(let rect): XCTAssertTrue(fit.contains(rect), "\(key.button) liegt im Bild")
                }
            }
            for stick in layout.sticks {
                XCTAssertTrue(fit.contains(CGRect(x: stick.center.x - stick.zone, y: stick.center.y - stick.zone, width: 2 * stick.zone, height: 2 * stick.zone)), "Stick \(stick.side) liegt im Bild")
                XCTAssertNil(layout.key(at: stick.center), "unter der Mitte eines Sticks liegt keine Taste")
                XCTAssertNotNil(layout.stick(at: stick.center))
            }
            let d = layout.dpad
            XCTAssertTrue(fit.contains(CGRect(x: d.center.x - d.radius, y: d.center.y - d.radius, width: 2 * d.radius, height: 2 * d.radius)), "Steuerkreuz liegt im Bild")
        }
    }

    func testButtonsMultitouchAndSliding() throws {
        let layout = PadLayout(bounds: area)
        func finger(_ key: SwitchButton) -> PadLayout.Touch {
            let c = layout.keys.first { $0.button == key }!.shape.center
            return PadLayout.Touch(origin: c, point: c)
        }
        XCTAssertEqual(layout.state(for: []), PadState())
        var a = PadState(); a.press(.a)
        XCTAssertEqual(layout.state(for: [finger(.a)]), a)

        var both = PadState(); both.press(.a); both.press(.zl)
        XCTAssertEqual(layout.state(for: [finger(.a), finger(.zl)]), both, "zwei Finger, zwei Tasten")

        var slid = finger(.a)
        slid.point = finger(.b).point
        var b = PadState(); b.press(.b)
        XCTAssertEqual(layout.state(for: [slid]), b, "ein Finger rutscht von A auf B")
        slid.point = CGPoint(x: area.midX, y: area.maxY - 2)
        XCTAssertEqual(layout.state(for: [slid]), PadState(), "und daneben ins Leere: losgelassen")
    }

    func testDPadDirectionsAndCorners() {
        let layout = PadLayout(bounds: area), c = layout.dpad.center, r = layout.dpad.radius
        func pressed(_ dx: CGFloat, _ dy: CGFloat) -> Set<SwitchButton> {
            let p = CGPoint(x: c.x + dx * r, y: c.y + dy * r)
            return Set(SwitchButton.allCases.filter { layout.state(for: [.init(origin: p, point: p)]).has($0) })
        }
        XCTAssertEqual(pressed(0, -0.7), [.up])
        XCTAssertEqual(pressed(0, 0.7), [.down])
        XCTAssertEqual(pressed(-0.7, 0), [.left])
        XCTAssertEqual(pressed(0.7, 0), [.right])
        XCTAssertEqual(pressed(0.55, -0.55), [.up, .right], "Ecke: zwei Richtungen")
        XCTAssertEqual(pressed(-0.55, 0.55), [.down, .left])
        XCTAssertEqual(pressed(0.05, 0.05), [], "genau in der Mitte nichts")
    }

    func testSticksFollowTheFingerFromWhereItLanded() {
        let layout = PadLayout(bounds: area), left = layout.sticks[0], right = layout.sticks[1]
        func moved(_ stick: PadLayout.Stick, from: CGPoint, by v: CGVector) -> PadLayout.Touch {
            PadLayout.Touch(origin: from, point: CGPoint(x: from.x + v.dx * stick.travel, y: from.y + v.dy * stick.travel))
        }
        var s = layout.state(for: [moved(left, from: left.center, by: CGVector(dx: 1, dy: 0))])
        XCTAssertEqual([s.leftX, s.leftY, s.rightX, s.rightY, UInt8(s.buttons)], [255, 128, 128, 128, 0], "voll nach rechts")
        s = layout.state(for: [moved(left, from: left.center, by: CGVector(dx: 0, dy: -2))])
        XCTAssertEqual([s.leftX, s.leftY], [128, 1], "über den Weg hinaus: voller Ausschlag nach oben (Y: oben ist klein)")
        s = layout.state(for: [moved(right, from: right.center, by: CGVector(dx: -1, dy: 0))])
        XCTAssertEqual([s.leftX, s.rightX, s.rightY], [128, 1, 128], "der rechte Stick")

        // Aufgesetzt neben der Mitte, aber in der Zone: der Weg von dort zählt, kein Sprung.
        let off = CGPoint(x: left.center.x + 0.2 * layout.unit, y: left.center.y)
        XCTAssertNil(layout.key(at: off))
        s = layout.state(for: [moved(left, from: off, by: CGVector(dx: 0, dy: 0.5))])
        XCTAssertEqual(s.leftX, 128)
        XCTAssertEqual(Double(s.leftY), 192, accuracy: 1, "halber Weg nach unten")

        // Beide Sticks und eine Taste zugleich; ein zweiter Finger in derselben Zone zählt nicht.
        let a = layout.keys.first { $0.button == .a }!.shape.center
        s = layout.state(for: [moved(left, from: left.center, by: CGVector(dx: 1, dy: 0)), moved(right, from: right.center, by: CGVector(dx: 0, dy: 1)),
                               PadLayout.Touch(origin: a, point: a), moved(left, from: off, by: CGVector(dx: -1, dy: 0))])
        XCTAssertEqual([s.leftX, s.leftY, s.rightX, s.rightY], [255, 128, 128, 255])
        XCTAssertTrue(s.has(.a))

        // Ein Finger, der einen Stick gegriffen hat, drückt unterwegs nichts.
        let zl = layout.keys.first { $0.button == .zl }!.shape.center
        s = layout.state(for: [PadLayout.Touch(origin: left.center, point: zl)])
        XCTAssertEqual(s.buttons, 0)
    }
}
