import Darwin
import XCTest
@testable import MacSwitch

final class ControllerTests: XCTestCase {
    func testChoosePlayerKeepsSavedSlotAndSparesSlotsOfKnownPhones() {
        let choose = ControllerHost.choosePlayer
        XCTAssertEqual(choose("a", nil, [:], []), 1, "erstes iPhone: Spieler 1")
        XCTAssertEqual(choose("b", nil, [:], [1]), 2, "zweites: der nächste freie")
        XCTAssertEqual(choose("a", nil, ["a": 3, "b": 1], [1]), 3, "ein bekanntes iPhone bekommt seinen gespeicherten Platz, wenn frei")
        XCTAssertEqual(choose("c", nil, ["a": 1, "b": 2], []), 3, "ein neues iPhone nimmt keinen Platz, den ein bekanntes für sich hat")
        XCTAssertEqual(choose("c", nil, ["a": 1, "b": 2, "d": 3, "e": 4], []), 1, "sind alle für bekannte iPhones vorgemerkt, nimmt es den ersten freien")
        XCTAssertEqual(choose("a", 2, ["a": 1], [1]), 2, "ist der gespeicherte Platz belegt, bleibt es auf dem jetzigen")
        XCTAssertNil(choose("e", nil, [:], [1, 2, 3, 4]), "alle belegt: es wartet")
    }

    /// Der DSU-Server in MacSwitch antwortet dem C-Client des nxnative-Hosts (dm/host/dsu_pad.h): die Anmeldung stammt Byte für Byte von dort
    /// (tests/t_dsu.c prüft sie), und die Datenpakete haben das Layout, das t_dsu.c liest.
    func testDSUServerAnswersRegistrationFromNxnativeClient() throws {
        let registration: [UInt8] = [0x44, 0x53, 0x55, 0x43, 0xe9, 0x03, 0x0c, 0x00, 0x1c, 0xc2, 0x2c, 0x74, 0xcd, 0xab, 0, 0, 0x02, 0, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(DSUServer.parse(registration), 0x100002)

        let port: UInt16 = 26798 // nicht der echte Port, damit der Test neben einem laufenden Host läuft
        let queue = DispatchQueue(label: "test")
        let server = DSUServer(queue: queue, port: port)
        queue.sync { server.start() }
        defer { queue.sync { server.stop() } }
        XCTAssertTrue(server.isRunning, server.error ?? "")

        var state = GamepadState()
        state.buttons = PadButton.a.bit | PadButton.zl.bit | PadButton.plus.bit | PadButton.up.bit
        state.leftX = 255; state.leftY = 0; state.rightX = 0; state.rightY = 255
        queue.sync { server.update(slot: 1, state: state) } // Spieler 2

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        defer { close(sock) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian; dest.sin_addr.s_addr = inet_addr("127.0.0.1")
        withUnsafePointer(to: &dest) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = sendto(sock, registration, registration.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }

        // Die Anmeldung für alle Slots beantwortet der Server mit einem Paket je Slot, sofort.
        var packets = [Int: [UInt8]]()
        for _ in 0..<DSUServer.slotCount {
            var buffer = [UInt8](repeating: 0, count: 256)
            let n = recv(sock, &buffer, buffer.count, 0)
            XCTAssertEqual(n, 100, "ein Datenpaket hat 100 Byte")
            guard n == 100 else { return }
            packets[Int(buffer[20])] = Array(buffer[0..<100])
        }
        XCTAssertEqual(Set(packets.keys), [0, 1, 2, 3])
        let idle = try XCTUnwrap(packets[0])[20...]
        XCTAssertEqual(idle[idle.startIndex + 11], 0, "Slot 1 ohne iPhone: getrennt")

        let p = try XCTUnwrap(packets[1]), d = Array(p[20...])
        XCTAssertEqual(Array(p[0..<4]), Array("DSUS".utf8))
        XCTAssertEqual(d[11], 1, "Slot 2: verbunden")
        XCTAssertEqual(d[16], 0x08 | 0x10, "+ und Steuerkreuz hoch (Byte 1)")
        XCTAssertEqual(d[17], 0x40 | 0x01, "A (0x40) und ZL (0x01) (Byte 2)")
        XCTAssertEqual(Array(d[20...23]), [255, 255, 0, 0], "Sticks: links rechts/oben, rechts links/unten (Y von oben nach unten umgekehrt)")
    }
}
