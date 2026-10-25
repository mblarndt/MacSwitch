import Foundation

// Das Funkprotokoll der iPhone-App, die Senderseite. Der Mac-Host (Sources/MacSwitch/ControllerProtocol.swift) liest dasselbe Format;
// Tests/MacSwitchTests/PadLogicTests.swift prüft beide Seiten gegeneinander. Dienst und Characteristics sind die von AstrisPad,
// MacSwitch spricht also auch mit dessen iPhone-App.

enum PadBLE {
    static let service = "7A01F7B2-8C45-4F1B-9A33-1B5D0D78A001"
    /// Das iPhone schreibt hier Zustand, Vorstellung und Antwortzeit-Messungen.
    static let input = "7A01F7B2-8C45-4F1B-9A33-1B5D0D78A002"
    /// Das iPhone abonniert sie: Spielernummer und Antworten des Macs. Endet das Abo, ist das iPhone getrennt.
    static let presence = "7A01F7B2-8C45-4F1B-9A33-1B5D0D78A003"
}

/// Die Tasten eines Switch-Controllers. Die Rohwerte sind Bitpositionen im Funkprotokoll und dürfen sich nicht ändern
/// (beim Mac: `PadButton`). Die Sticks gehen als Achsen, nicht als Tasten.
enum SwitchButton: Int, CaseIterable {
    case a, b, x, y, l, r, zl, zr, minus, plus, l3, r3, home, capture, up, down, left, right

    var bit: UInt32 { 1 << UInt32(rawValue) }
}

/// Vollständiger Zustand des Controllers. Neun Bytes: Kennung 0x47, Tasten-Bits (Little Endian), vier Achsen.
/// Achsen laufen von 0 bis 255 mit 128 als Mitte; bei Y ist 0 oben.
struct PadState: Equatable {
    static let marker: UInt8 = 0x47

    var buttons: UInt32 = 0
    var leftX: UInt8 = 128, leftY: UInt8 = 128
    var rightX: UInt8 = 128, rightY: UInt8 = 128

    mutating func press(_ button: SwitchButton) { buttons |= button.bit }
    func has(_ button: SwitchButton) -> Bool { buttons & button.bit != 0 }

    /// Rechnet eine Auslenkung von −1 bis 1 in einen Achsenwert um.
    static func axis(_ value: Double) -> UInt8 { UInt8(min(255, max(0, (128 + value * 127).rounded()))) }

    var data: Data {
        Data([Self.marker,
              UInt8(buttons & 0xFF), UInt8((buttons >> 8) & 0xFF), UInt8((buttons >> 16) & 0xFF), UInt8(buttons >> 24),
              leftX, leftY, rightX, rightY])
    }
}

/// Die übrigen Nachrichten: Vorstellung, Antwortzeit-Messung, Spielernummer.
enum PadWire {
    /// Erste Nachricht nach dem Verbinden: `[0x48, Geräte-ID (16 Byte), Name (UTF-8)]`. Daran erkennt der Mac das iPhone wieder
    /// und gibt ihm seinen Spielerplatz zurück. Der Name wird zeichenweise gekürzt, damit die Nachricht in ein Funkpaket passt.
    static func hello(deviceID: UUID, name: String, maxLength: Int) -> Data {
        var d = Data([0x48])
        var uuid = deviceID.uuid
        withUnsafeBytes(of: &uuid) { d.append(contentsOf: $0) }
        for character in name {
            let bytes = Array(String(character).utf8)
            guard d.count + bytes.count <= maxLength else { break }
            d.append(contentsOf: bytes)
        }
        return d
    }

    /// Antwortzeit-Messung: `[0x50, Nummer (2 Byte), letzte gemessene Antwortzeit in ms]`. Der Mac antwortet sofort mit `[0x50, Nummer]`.
    static func ping(sequence: UInt16, lastRoundTrip: Int?) -> Data {
        Data([0x50, UInt8(sequence & 0xFF), UInt8(sequence >> 8), UInt8(clamping: lastRoundTrip ?? 0)])
    }

    /// Die Nummer, wenn es die Antwort auf eine Messung ist.
    static func pingReply(_ data: Data) -> UInt16? {
        let b = [UInt8](data)
        guard b.count == 3, b[0] == 0x50 else { return nil }
        return UInt16(b[1]) | UInt16(b[2]) << 8
    }

    /// `[0x53, Spielernummer]` vom Mac; 0 heißt: kein Platz frei. Nil, wenn es keine Spieler-Nachricht ist.
    static func player(_ data: Data) -> Int? {
        let b = [UInt8](data)
        guard b.count == 2, b[0] == 0x53 else { return nil }
        return Int(b[1])
    }
}
