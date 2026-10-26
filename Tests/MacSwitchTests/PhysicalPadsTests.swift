import XCTest
@testable import MacSwitch

/// Echte Controller im MacSwitch-Menü: Zustand wie im nxnative-Host (nach Lage), mehrere Controller wie einer, Treiber mit Wiederholung.
final class PhysicalPadsTests: XCTestCase {
    func testButtonsAreMappedByPositionLikeTheGameHost() {
        func pressed(_ edit: (inout PadSnapshot) -> Void) -> [PadButton] {
            var s = PadSnapshot(); edit(&s)
            let state = GamepadState(s)
            return PadButton.allCases.filter { state.has($0) }
        }
        XCTAssertEqual(pressed { $0.right = true }, [.a], "Xbox B (rechts) ist Switch A")
        XCTAssertEqual(pressed { $0.bottom = true }, [.b], "Xbox A (unten) ist Switch B")
        XCTAssertEqual(pressed { $0.top = true }, [.x])
        XCTAssertEqual(pressed { $0.left = true }, [.y])
        XCTAssertEqual(pressed { $0.menu = true }, [.plus])
        XCTAssertEqual(pressed { $0.view = true }, [.minus])
        XCTAssertEqual(pressed { $0.zl = true; $0.r = true; $0.l3 = true; $0.home = true }, [.r, .zl, .l3, .home])
        XCTAssertEqual(pressed { $0.up = true; $0.dpadRight = true }, [.up, .right])
        XCTAssertEqual(pressed { _ in }, [])
    }

    func testAxesRunFromTopToBottomAsInTheWireProtocol() {
        var s = PadSnapshot()
        XCTAssertEqual([GamepadState(s).leftX, GamepadState(s).leftY], [128, 128])
        s.lx = 1; s.ly = 1; s.rx = -1; s.ry = -1 // rechts/oben und links/unten
        let g = GamepadState(s)
        XCTAssertEqual([g.leftX, g.leftY, g.rightX, g.rightY], [255, 1, 1, 255], "oben ist bei Y klein")
    }

    func testMergingControllersTakesAllButtonsAndTheStrongerStick() {
        var a = GamepadState(), b = GamepadState()
        a.buttons = PadButton.a.bit; a.leftX = 200
        b.buttons = PadButton.b.bit; b.leftX = 10; b.rightY = 130
        let m = GamepadState.merged([a, b])
        XCTAssertTrue(m.has(.a) && m.has(.b))
        XCTAssertEqual(m.leftX, 10, "|10−128| ist größer als |200−128|")
        XCTAssertEqual(m.rightY, 130)
        XCTAssertEqual(GamepadState.merged([]), .neutral)
    }

    func testMenuKeysFromAnXboxLikePad() {
        var s = PadSnapshot(); s.right = true
        XCTAssertEqual(MenuPad.keys(in: GamepadState(s)), [.confirm], "die rechte Fläche bestätigt, wie A auf der Switch")
        s = PadSnapshot(); s.bottom = true; s.ly = -1
        XCTAssertEqual(MenuPad.keys(in: GamepadState(s)), [.back, .down])
    }

    func testDriverRepeatsAHeldDirectionOnItsQueueAndStopsOnRelease() {
        let queue = DispatchQueue(label: "driver-test")
        var keys = [String]() // deliver läuft auf dem Haupt-Thread, wie der Test
        let driver = MenuDriver(queue: queue) { key, isRepeat in keys.append("\(key)\(isRepeat ? "*" : "")") }
        func wait(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        var right = GamepadState(); right.buttons = PadButton.right.bit
        queue.sync { driver.update(right) }
        wait(0.75) // 0,4 s Wartezeit, dann alle 0,11 s
        queue.sync { driver.update(nil) }
        wait(0.2)
        let seen = keys
        XCTAssertEqual(seen.first, "right")
        XCTAssertGreaterThanOrEqual(seen.filter { $0 == "right*" }.count, 2, "mehrere Wiederholungen: \(seen)")
        wait(0.4)
        XCTAssertEqual(keys, seen, "nach dem Loslassen kommt nichts mehr")
    }
}

final class ControllerSeatsTests: XCTestCase {
    func testSeatsFollowTheOrderOfConnecting() {
        let t = Date(timeIntervalSince1970: 1000)
        let xbox = PhysicalPads.Device(name: "Xbox Wireless Controller", since: t)
        var phone = ControllerHost.Player(number: 1, name: "Bens iPhone", connected: true, latency: 24, since: t.addingTimeInterval(5))
        var seats = ControllerView.seats(phones: [phone], pads: [xbox])
        XCTAssertEqual(seats.map(\.name), ["Xbox Wireless Controller", "Bens iPhone"], "der Xbox-Controller war zuerst da: Spieler 1")
        XCTAssertEqual(seats.map(\.detail), ["Controller", "24 ms"])

        phone.since = t.addingTimeInterval(-5)
        seats = ControllerView.seats(phones: [phone], pads: [xbox])
        XCTAssertEqual(seats.map(\.name), ["Bens iPhone", "Xbox Wireless Controller"], "war das iPhone zuerst, ist es Spieler 1")

        phone.connected = false
        XCTAssertEqual(ControllerView.seats(phones: [phone], pads: [xbox]).map(\.name), ["Xbox Wireless Controller"], "nicht verbundene iPhones belegen keinen Platz")
        let twin = PhysicalPads.Device(name: "Pro Controller", since: t)
        XCTAssertEqual(ControllerView.seats(phones: [], pads: [xbox, twin]).map(\.name), ["Xbox Wireless Controller", "Pro Controller"], "gleiche Zeit: Reihenfolge bleibt")
    }
}
