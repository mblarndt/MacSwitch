import XCTest
@testable import MacSwitch

/// Das MacSwitch-Menü per iPhone: Controller-Zustand → Menü-Tasten.
final class MenuPadTests: XCTestCase {
    private func state(_ buttons: PadButton..., leftX: UInt8 = 128, leftY: UInt8 = 128) -> GamepadState {
        var s = GamepadState()
        for b in buttons { s.buttons |= b.bit }
        s.leftX = leftX; s.leftY = leftY
        return s
    }

    private func keys(_ fired: [(key: MenuPad.Key, isRepeat: Bool)]) -> [String] { fired.map { "\($0.key)\($0.isRepeat ? "*" : "")" } }

    func testDirectionFiresOnceThenRepeatsWhileHeld() {
        var pad = MenuPad()
        let right = state(.right)
        XCTAssertEqual(keys(pad.update(right, now: 0)), ["right"])
        XCTAssertEqual(pad.nextRepeat ?? 0, MenuPad.firstRepeat, accuracy: 1e-9)
        XCTAssertEqual(keys(pad.update(right, now: 0.39)), [], "vor der Wartezeit nichts")
        XCTAssertEqual(keys(pad.update(right, now: 0.41)), ["right*"], "erste Wiederholung")
        XCTAssertEqual(keys(pad.update(right, now: 0.45)), [])
        XCTAssertEqual(keys(pad.update(right, now: 0.53)), ["right*"], "danach im Takt")
        XCTAssertEqual(keys(pad.update(nil, now: 0.6)), [], "kein Controller: losgelassen")
        XCTAssertNil(pad.nextRepeat)
        XCTAssertEqual(keys(pad.update(right, now: 0.7)), ["right"], "erneut gedrückt: wieder ein erstes Auslösen")
    }

    func testButtonsFireOnceAndDoNotRepeat() {
        var pad = MenuPad()
        XCTAssertEqual(keys(pad.update(state(.a), now: 0)), ["confirm"])
        XCTAssertNil(pad.nextRepeat, "A wiederholt sich nicht")
        XCTAssertEqual(keys(pad.update(state(.a), now: 5)), [])
        XCTAssertEqual(keys(pad.update(state(), now: 6)), [])
        XCTAssertEqual(keys(pad.update(state(.b, .plus), now: 7)), ["back", "options"])
        XCTAssertEqual(keys(pad.update(state(.home), now: 8)), ["home"])
    }

    func testLeftStickActsAsDirectionsAndMergesWithDPad() {
        let c = MenuPad.keys
        XCTAssertEqual(c(state(leftX: 255)), [.right])
        XCTAssertEqual(c(state(leftX: 0)), [.left])
        XCTAssertEqual(c(state(leftY: 0)), [.up], "Y: 0 ist oben")
        XCTAssertEqual(c(state(leftY: 255)), [.down])
        XCTAssertEqual(c(state(leftX: 128 + 40, leftY: 128 - 40)), [], "kleine Auslenkung zählt nicht")
        XCTAssertEqual(c(state(.right, leftX: 255)), [.right], "Steuerkreuz und Stick in dieselbe Richtung: eine Taste")
        XCTAssertEqual(c(state(.up, leftX: 255)), [.up, .right], "Diagonale: beide")
    }

    func testMenuKeysBecomePageKeys() {
        XCTAssertTrue(MenuPad.Key.up.pageKey(isRepeat: false).key == .upArrow && MenuPad.Key.up.pageKey(isRepeat: false).isDown)
        XCTAssertTrue(MenuPad.Key.down.pageKey(isRepeat: true).key == .downArrow && !MenuPad.Key.down.pageKey(isRepeat: true).isDown, "Wiederholung: nicht .down")
        XCTAssertTrue(MenuPad.Key.confirm.pageKey(isRepeat: false).key == .return)
        XCTAssertTrue(MenuPad.Key.back.pageKey(isRepeat: false).key == .escape)
        XCTAssertEqual(MenuPad.Key.options.pageKey(isRepeat: false).characters, "+")
    }
}
