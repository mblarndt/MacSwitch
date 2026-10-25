import Foundation

// Der Funk-Teil von AstrisPhoneController/Shared/Protocol.swift, was MacSwitch als Host braucht: Kennungen, Antwortzeit, Controller-Zustand, Bewegung, Vorstellung und Spielernummer.
// Die Definitionen sind dieselben wie dort (die Rohwerte von `PadButton` sind Bitpositionen im Funkprotokoll), nur ohne Tastenkatalog, Belegungen und das Zurückschreiben.

enum BLEIDs {
    static let service = "7A01F7B2-8C45-4F1B-9A33-1B5D0D78A001"
    static let input   = "7A01F7B2-8C45-4F1B-9A33-1B5D0D78A002"
    /// Das iPhone abonniert diese Characteristic. Endet das Abo (Verbindungsabbruch), ist es getrennt.
    static let presence = "7A01F7B2-8C45-4F1B-9A33-1B5D0D78A003"
}

/// Antwortzeit-Messung. Das iPhone schreibt `[0x50, Nummer (2 Byte), letzte Antwortzeit in ms]`,
/// der Mac antwortet sofort über die Presence-Characteristic mit `[0x50, Nummer (2 Byte)]`.
enum Ping {
    static let marker: UInt8 = 0x50

    /// Liest eine Anfrage: Nummer und die vom iPhone zuletzt gemessene Antwortzeit (0 = noch keine).
    static func parseRequest(_ data: Data) -> (sequence: UInt16, lastRoundTrip: Int)? {
        let b = [UInt8](data)
        guard b.count == 4, b[0] == marker else { return nil }
        return (UInt16(b[1]) | UInt16(b[2]) << 8, Int(b[3]))
    }

    static func reply(sequence: UInt16) -> Data {
        Data([marker, UInt8(sequence & 0xFF), UInt8(sequence >> 8)])
    }
}

/// Eingaben eines Switch-Controllers. Die Rohwerte sind Bitpositionen im Funkprotokoll und dürfen sich nicht ändern.
enum PadButton: Int, CaseIterable {
    case a, b, x, y, l, r, zl, zr, minus, plus, l3, r3, home, capture, up, down, left, right
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight
    /// Hardware des iPhones: Lautstärketasten und Tippen auf die Rückseite. DSU kennt dafür keine Taste.
    case volumeUp, volumeDown, backTap

    var bit: UInt32 { 1 << UInt32(rawValue) }
}

/// Vollständiger Controller-Zustand eines iPhones. Neun Bytes: Kennung, Eingabe-Bits (Little Endian), vier Stick-Achsen.
/// Achsen laufen von 0 bis 255 mit 128 als Mitte; bei Y ist 0 oben.
struct GamepadState: Equatable {
    static let marker: UInt8 = 0x47
    static let neutral = GamepadState()

    var buttons: UInt32 = 0
    var leftX: UInt8 = 128
    var leftY: UInt8 = 128
    var rightX: UInt8 = 128
    var rightY: UInt8 = 128

    init() {}

    init?(data: Data) {
        let b = [UInt8](data)
        guard b.count == 9, b[0] == Self.marker else { return nil }
        buttons = UInt32(b[1]) | UInt32(b[2]) << 8 | UInt32(b[3]) << 16 | UInt32(b[4]) << 24
        leftX = b[5]
        leftY = b[6]
        rightX = b[7]
        rightY = b[8]
    }

    func has(_ button: PadButton) -> Bool { buttons & button.bit != 0 }
}

/// Bewegungsdaten des iPhones für das DSU-Protokoll: Beschleunigung in g und Drehrate in Grad pro Sekunde, im Achsensystem
/// eines Controllers (DS4-Anordnung, wie sie DSU-Clients erwarten). Dreizehn Byte: Kennung, sechs Int16 (Little Endian),
/// Beschleunigung in Tausendstel g, Drehrate in 1/16 Grad pro Sekunde.
struct MotionSample: Equatable {
    static let marker: UInt8 = 0x4D

    var accel: SIMD3<Float>
    var gyro: SIMD3<Float>

    init(accel: SIMD3<Float>, gyro: SIMD3<Float>) {
        self.accel = accel
        self.gyro = gyro
    }

    init?(data: Data) {
        let b = [UInt8](data)
        guard b.count == 13, b[0] == Self.marker else { return nil }
        func value(_ i: Int) -> Float { Float(Int16(bitPattern: UInt16(b[1 + 2 * i]) | UInt16(b[2 + 2 * i]) << 8)) }
        accel = SIMD3(value(0), value(1), value(2)) / 1000
        gyro = SIMD3(value(3), value(4), value(5)) / 16
    }
}

/// Erste Nachricht nach dem Verbinden: `[0x48, Geräte-ID (16 Byte), Name (UTF-8)]`.
/// Daran erkennt der Mac ein iPhone wieder und gibt ihm seinen Spielerplatz zurück.
struct Hello {
    static let marker: UInt8 = 0x48

    let deviceID: UUID
    let name: String

    init?(data: Data) {
        let b = [UInt8](data)
        guard b.count >= 17, b[0] == Self.marker else { return nil }
        let u = Array(b[1...16])
        deviceID = UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
                               u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]))
        name = String(decoding: b[17...], as: UTF8.self)
    }
}

/// Mac → iPhone: `[0x53, Spielernummer]`, 0 heißt: kein Platz frei.
enum PlayerMessage {
    static let marker: UInt8 = 0x53

    static func data(player: Int?) -> Data { Data([marker, UInt8(clamping: player ?? 0)]) }
}
