// Kopie von AstrisPhoneController/MacHost/DSUServer.swift, unverändert: Änderungen dort bitte hierher übernehmen.
import Foundation
import Darwin

/// DSU-Server (cemuhook-Protokoll, https://v1993.github.io/cemuhook-protocol/) auf 127.0.0.1:26760.
/// Astris ab 1.0.32 verbindet sich als Client und liest daraus Controller. Jeder Spielerplatz (1 … 4) ist ein Slot (0 … 3).
/// Alle Methoden laufen auf der übergebenen Warteschlange (der der `HostEngine`).
final class DSUServer {
    static let port: UInt16 = 26760
    static let slotCount = 4
    private static let version: UInt16 = 1001
    /// Clients melden sich regelmäßig neu an. Wer länger still ist, bekommt nichts mehr.
    private static let clientTimeout: TimeInterval = 8

    private struct Client {
        var address: sockaddr_in
        /// Nil: alle Slots.
        var slots: Set<Int>?
        var expires: TimeInterval
    }

    private let queue: DispatchQueue
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var keepAlive: DispatchSourceTimer?
    private let serverID = UInt32.random(in: 1...UInt32.max)
    /// Mindestdauer eines Tastendrucks. Kommen Drücken und Loslassen im selben Funkpaket an, liegen sie am Mac Mikrosekunden
    /// auseinander. Astris liest den Zustand nur im eigenen Takt und sähe den Tipp sonst nicht.
    static let minimumHold: TimeInterval = 0.08
    /// Ohne Änderung wird der Zustand so oft erneuert, damit Clients den Controller nicht für getrennt halten.
    private static let idleInterval: TimeInterval = 0.1
    /// Tick: Stick-Bewegungen werden gesammelt und höchstens so oft gesendet. Tastenwechsel gehen sofort raus.
    private static let tickInterval: TimeInterval = 1.0 / 60

    /// Was die Clients sehen (mit Mindestdauer) und was das iPhone zuletzt gemeldet hat.
    private var states = [GamepadState?](repeating: nil, count: DSUServer.slotCount)
    private var desired = [GamepadState?](repeating: nil, count: DSUServer.slotCount)
    private var heldUntil = [[PadButton: TimeInterval]](repeating: [:], count: DSUServer.slotCount)
    /// Letzte Bewegungsdaten pro Slot mit Eingangszeit.
    private var motion = [(sample: MotionSample, at: TimeInterval)?](repeating: nil, count: DSUServer.slotCount)
    /// Ohne neue Bewegungsdaten werden nach so langer Zeit Nullen gesendet.
    private static let motionTimeout: TimeInterval = 0.5
    private var dirty = Set<Int>()
    private var lastSent = [TimeInterval](repeating: 0, count: DSUServer.slotCount)
    private var numbers = [UInt32](repeating: 0, count: DSUServer.slotCount)
    private var clients = [UInt64: Client]()
    private var sentCount = 0
    private var receivedCount = 0
    private var lastStats = ProcessInfo.processInfo.systemUptime

    /// Läuft der Server nicht, steht hier der Grund.
    private(set) var error: String?
    var isRunning: Bool { fd >= 0 }
    var clientCount: Int { clients.count }
    /// Mitschnitt für die Fehlersuche: eine Zeile pro Anfrage eines Clients.
    var trace: ((String) -> Void)?
    /// Wird aufgerufen, wenn sich die Zahl der Clients ändert.
    var onClientsChanged: (() -> Void)?

    private let port: UInt16

    init(queue: DispatchQueue, port: UInt16 = DSUServer.port) {
        self.queue = queue
        self.port = port
    }

    // MARK: Start und Stopp

    func start() {
        guard fd < 0 else { return }
        let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else { error = "Socket nicht möglich"; return }
        // Nur lokal erreichbar. Ohne SO_REUSEADDR scheitert das Binden, wenn ein anderer DSU-Server den Port belegt.
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(socketFD)
            error = "Port \(port) ist belegt (läuft ein anderer DSU-Server?)"
            return
        }
        _ = fcntl(socketFD, F_SETFL, fcntl(socketFD, F_GETFL) | O_NONBLOCK)
        fd = socketFD
        error = nil
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in self?.readPackets() }
        source.resume()
        self.source = source
        // Auch ohne Änderung regelmäßig senden: Clients erkennen so, dass der Controller noch da ist.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        keepAlive = timer
    }

    func stop() {
        source?.cancel()
        source = nil
        keepAlive?.cancel()
        keepAlive = nil
        if fd >= 0 { close(fd); fd = -1 }
        if !clients.isEmpty { clients.removeAll(); onClientsChanged?() }
    }

    // MARK: Zustand

    /// Setzt den Zustand eines Slots. Nil: kein iPhone auf diesem Platz.
    func update(slot: Int, state: GamepadState?) {
        guard states.indices.contains(slot), desired[slot] != state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let state {
            for button in PadButton.allCases where state.has(button) && !(desired[slot]?.has(button) ?? false) {
                heldUntil[slot][button] = now + Self.minimumHold
            }
        } else {
            heldUntil[slot].removeAll()
            motion[slot] = nil
        }
        desired[slot] = state
        apply(slot)
    }

    /// Neue Bewegungsdaten für einen Slot. Sie gehen mit dem nächsten Takt raus, nicht einzeln.
    func updateMotion(slot: Int, sample: MotionSample?) {
        guard states.indices.contains(slot) else { return }
        motion[slot] = sample.map { ($0, ProcessInfo.processInfo.systemUptime) }
        if states[slot] != nil { dirty.insert(slot) }
    }

    private func freshMotion(_ slot: Int) -> MotionSample? {
        guard let entry = motion[slot], ProcessInfo.processInfo.systemUptime - entry.at < Self.motionTimeout else { return nil }
        return entry.sample
    }

    /// Berechnet, was die Clients sehen: der gemeldete Zustand, aber Tasten bleiben mindestens `minimumHold` gedrückt.
    private func apply(_ slot: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        var visible = desired[slot]
        if var state = visible {
            for (button, until) in heldUntil[slot] {
                if until > now { state.buttons |= button.bit } else { heldUntil[slot][button] = nil }
            }
            visible = state
        }
        if let next = heldUntil[slot].values.min() {
            queue.asyncAfter(deadline: .now() + max(0, next - now) + 0.001) { [weak self] in self?.apply(slot) }
        }
        guard visible != states[slot] else { return }
        let buttonsChanged = visible?.buttons != states[slot]?.buttons || (visible == nil) != (states[slot] == nil)
        states[slot] = visible
        numbers[slot] &+= 1
        if buttonsChanged {
            trace?(String(format: "Tasten Slot %d: 0x%05X", slot, visible?.buttons ?? 0))
            dirty.remove(slot)
            send(slot: slot)
        } else {
            dirty.insert(slot)
        }
    }

    private func tick() {
        pruneClients()
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStats >= 1 {
            if let trace, sentCount + receivedCount > 0 {
                trace(String(format: "Statistik: empfangen %d/s, gesendet %d/s, Clients %d", receivedCount, sentCount, clients.count))
            }
            sentCount = 0; receivedCount = 0; lastStats = now
        }
        for slot in states.indices where states[slot] != nil && (dirty.contains(slot) || now - lastSent[slot] >= Self.idleInterval) {
            numbers[slot] &+= 1
            send(slot: slot)
        }
        dirty.removeAll()
    }

    private func pruneClients() {
        let now = ProcessInfo.processInfo.systemUptime
        let before = clients.count
        clients = clients.filter { $0.value.expires > now }
        if clients.count != before { onClientsChanged?() }
    }

    // MARK: Empfangen

    private func readPackets() {
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            if count <= 0 { return }
            receivedCount += 1
            handle(Array(buffer[0..<count]), from: from)
        }
    }

    private func handle(_ packet: [UInt8], from address: sockaddr_in) {
        // Lokale Pakete, aber trotzdem prüfen: Kennung, Länge und Prüfsumme.
        guard let type = Self.parse(packet) else { trace?("ungültiges Paket (\(packet.count) Byte)"); return }
        trace?(String(format: "Anfrage 0x%X von Port %d, %d Byte", type, Int(UInt16(bigEndian: address.sin_port)), packet.count) + (type == 0x100002 ? " Anmeldung: " + packet.dropFirst(20).prefix(8).map { String($0) }.joined(separator: ",") : (type == 0x100001 ? " Slots: " + packet.dropFirst(20).map { String($0) }.joined(separator: ",") : "")))
        switch type {
        case 0x100000:
            reply(to: address, type: type, payload: Self.le16(Self.version))
        case 0x100001:
            guard packet.count >= 24 else { return }
            let count = min(Self.slotCount, max(0, Int(Self.int32(packet, 20))))
            guard packet.count >= 24 + count else { return }
            for index in 0..<count {
                let slot = Int(packet[24 + index])
                guard states.indices.contains(slot) else { continue }
                reply(to: address, type: type, payload: header(slot: slot) + [0])
            }
        case 0x100002:
            register(packet, from: address)
        default:
            break
        }
    }

    private func register(_ packet: [UInt8], from address: sockaddr_in) {
        guard packet.count >= 22 else { return }
        let flags = packet[20]
        var slots: Set<Int>?
        if flags != 0 {
            var wanted = Set<Int>()
            if flags & 1 != 0 { wanted.insert(Int(packet[21])) }
            // Unsere Adressen sind 00:00:00:00:00:<Slot+1>.
            if flags & 2 != 0, packet.count >= 28, packet[22..<27].allSatisfy({ $0 == 0 }), packet[27] >= 1 { wanted.insert(Int(packet[27]) - 1) }
            slots = wanted
        }
        let key = UInt64(address.sin_addr.s_addr) << 16 | UInt64(address.sin_port)
        let isNew = clients[key] == nil
        // Astris meldet jeden Slot einzeln an, einmal pro Sekunde. Die Anmeldungen eines Clients sammeln sich, sie ersetzen sich nicht.
        var merged = slots
        if let existing = clients[key], let known = existing.slots {
            merged = slots.map { known.union($0) }
        }
        clients[key] = Client(address: address, slots: merged, expires: ProcessInfo.processInfo.systemUptime + Self.clientTimeout)
        if isNew { onClientsChanged?() }
        // Sofort den aktuellen Zustand liefern, damit der Client nicht auf die nächste Änderung wartet.
        for slot in states.indices where slots?.contains(slot) ?? true { send(slot: slot, only: key) }
    }

    // MARK: Senden

    private func send(slot: Int, only key: UInt64? = nil) {
        lastSent[slot] = ProcessInfo.processInfo.systemUptime
        guard !clients.isEmpty else { return }
        let packet = Self.build(type: 0x100002, serverID: serverID, payload: dataPayload(slot: slot))
        for (clientKey, client) in clients where key == nil || key == clientKey {
            if client.slots?.contains(slot) ?? true { transmit(packet, to: client.address) }
        }
    }

    private func reply(to address: sockaddr_in, type: UInt32, payload: [UInt8]) {
        transmit(Self.build(type: type, serverID: serverID, payload: payload), to: address)
    }

    private func transmit(_ packet: [UInt8], to address: sockaddr_in) {
        sentCount += 1
        var address = address
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    // MARK: Paketaufbau

    /// Gemeinsamer Kopf eines Controllers: Slot, Zustand, Modell, Verbindung, MAC, Akku (11 Byte).
    private func header(slot: Int) -> [UInt8] {
        let connected = states[slot] != nil
        // Modell 2: mit Gyro, wenn Bewegungsdaten ankommen, sonst 1. Verbindung 2: Bluetooth. Akku 5: voll.
        return [UInt8(slot), connected ? 2 : 0, connected ? (freshMotion(slot) != nil ? 2 : 1) : 0, connected ? 2 : 0, 0, 0, 0, 0, 0, UInt8(slot + 1), connected ? 5 : 0]
    }

    /// Controller-Daten (80 Byte nach der Nachrichtenart).
    func dataPayload(slot: Int) -> [UInt8] {
        let state = states[slot] ?? GamepadState.neutral
        func on(_ button: PadButton, _ mask: UInt8) -> UInt8 { state.has(button) ? mask : 0 }
        func analog(_ button: PadButton) -> UInt8 { state.has(button) ? 255 : 0 }
        // Bits wie beim DS4: Share, L3, R3, Options, Hoch, Rechts, Runter, Links. Dann L2, R2, L1, R1, X, A, B, Y.
        let buttons1 = on(.minus, 0x01) | on(.l3, 0x02) | on(.r3, 0x04) | on(.plus, 0x08)
            | on(.up, 0x10) | on(.right, 0x20) | on(.down, 0x40) | on(.left, 0x80)
        // Astris liest die Flächentasten nach der Xbox-Benennung: unten = A, rechts = B, links = X, oben = Y. Die Spezifikation
        // nennt sie nach Nintendo (Y links, B unten, A rechts, X oben). Darum sind A mit B und X mit Y vertauscht.
        let buttons2 = on(.zl, 0x01) | on(.zr, 0x02) | on(.l, 0x04) | on(.r, 0x08)
            | on(.y, 0x10) | on(.b, 0x20) | on(.a, 0x40) | on(.x, 0x80)
        var p = header(slot: slot)
        p.append(states[slot] != nil ? 1 : 0)
        p += Self.le32(numbers[slot])
        p += [buttons1, buttons2, state.has(.home) ? 1 : 0, state.has(.capture) ? 1 : 0]
        // Unsere Y-Achse zählt von oben nach unten, DSU von unten nach oben.
        p += [state.leftX, 255 - state.leftY, state.rightX, 255 - state.rightY]
        p += [analog(.left), analog(.down), analog(.right), analog(.up)]
        p += [analog(.x), analog(.a), analog(.b), analog(.y), analog(.r), analog(.l), analog(.zr), analog(.zl)]
        p += [UInt8](repeating: 0, count: 12)   // zwei Touch-Punkte, unbenutzt
        if let m = freshMotion(slot) {
            // Zeitstempel in Mikrosekunden, dann Beschleunigung (g) und Drehrate (Grad pro Sekunde) als Float.
            let micros = UInt64(motion[slot]!.at * 1_000_000)
            p += Self.le32(UInt32(micros & 0xFFFF_FFFF)) + Self.le32(UInt32(micros >> 32))
            for value in [m.accel.x, m.accel.y, m.accel.z, m.gyro.x, m.gyro.y, m.gyro.z] { p += Self.le32(value.bitPattern) }
        } else {
            p += [UInt8](repeating: 0, count: 8 + 12 + 12)
        }
        return p
    }

    /// Kopf (16 Byte, mit Prüfsumme), Nachrichtenart (4 Byte), Nutzdaten.
    static func build(type: UInt32, serverID: UInt32, payload: [UInt8]) -> [UInt8] {
        var p = Array("DSUS".utf8) + le16(version) + le16(UInt16(payload.count + 4)) + [0, 0, 0, 0] + le32(serverID) + le32(type) + payload
        let crc = crc32(p)
        p.replaceSubrange(8..<12, with: le32(crc))
        return p
    }

    /// Prüft Kennung "DSUC", Länge und Prüfsumme eines Client-Pakets und liefert die Nachrichtenart.
    static func parse(_ packet: [UInt8]) -> UInt32? {
        guard packet.count >= 20, packet[0..<4].elementsEqual("DSUC".utf8) else { return nil }
        let declared = Int(packet[6]) | Int(packet[7]) << 8
        guard declared + 16 <= packet.count else { return nil }
        var checked = Array(packet[0..<(16 + declared)])
        let sent = UInt32(checked[8]) | UInt32(checked[9]) << 8 | UInt32(checked[10]) << 16 | UInt32(checked[11]) << 24
        checked.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        guard crc32(checked) == sent else { return nil }
        return UInt32(packet[16]) | UInt32(packet[17]) << 8 | UInt32(packet[18]) << 16 | UInt32(packet[19]) << 24
    }

    private static func int32(_ b: [UInt8], _ at: Int) -> Int32 {
        Int32(bitPattern: UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24)
    }
    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { c, _ in c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        ~bytes.reduce(~UInt32(0)) { crcTable[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}
