import CoreBluetooth
import QuartzCore
import UIKit

/// Die Verbindung zu MacSwitch: sucht den Bluetooth-Dienst des Mac-Hosts, stellt dieses iPhone vor, schickt den Controller-Zustand
/// und misst die Antwortzeit. Alles läuft auf dem Haupt-Thread.
final class PadClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// Kurzer Text für die Anzeige im Controller.
    var onStatus: ((String) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var input: CBCharacteristic?
    private var writes = [Data]()
    private var lastState: PadState?
    private var connected = false
    private var bluetooth = "Bluetooth wird vorbereitet …"
    private var player: Int?
    private var noFreeSlot = false
    private var roundTrip: Int?
    private var smoothedRoundTrip: Double?
    private var pingTimer: Timer?
    private var pingSequence: UInt16 = 0
    private var pingsInFlight = [UInt16: CFTimeInterval]()
    private var waitingForWriteResponse = false
    private let serviceID = CBUUID(string: PadBLE.service)
    private let inputID = CBUUID(string: PadBLE.input)
    private let presenceID = CBUUID(string: PadBLE.presence)

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func publish() {
        if connected {
            let ping = roundTrip.map { " · \($0) ms" } ?? ""
            onStatus?(player.map { "Spieler \($0)\(ping)" } ?? (noFreeSlot ? "Kein Platz frei" : "Verbunden"))
        } else {
            onStatus?(bluetooth)
        }
    }

    // MARK: Verbindung

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            peripheral = nil
            resetLink()
            bluetooth = Self.describe(central.state)
            return publish()
        }
        // Besteht schon eine Systemverbindung zum Mac, wird sie direkt genutzt.
        if let known = central.retrieveConnectedPeripherals(withServices: [serviceID]).first { connect(known) } else { scan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        bluetooth = "Mac gefunden …"
        publish()
        p.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        peripheral = nil
        resetLink()
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        peripheral = nil
        resetLink()
        scan()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == serviceID }) else {
            central.cancelPeripheralConnection(p) // MacSwitch läuft nicht (mehr): trennen und warten, bis es wieder sendet
            return
        }
        p.discoverCharacteristics([inputID, presenceID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        input = service.characteristics?.first { $0.uuid == inputID }
        if let presence = service.characteristics?.first(where: { $0.uuid == presenceID }) { p.setNotifyValue(true, for: presence) }
        connected = input != nil
        bluetooth = connected ? "Verbunden" : "Eingabe-Kanal nicht gefunden"
        publish()
        if connected {
            sendHello()
            startPinging()
        }
        flushWrites()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == presenceID, let data = characteristic.value else { return }
        if let sequence = PadWire.pingReply(data) {
            guard let sent = pingsInFlight.removeValue(forKey: sequence) else { return }
            let measured = (CACurrentMediaTime() - sent) * 1000
            let smoothed = smoothedRoundTrip.map { $0 * 0.7 + measured * 0.3 } ?? measured
            smoothedRoundTrip = smoothed
            let rounded = Int(smoothed.rounded())
            if rounded != roundTrip { roundTrip = rounded; publish() }
        } else if let number = PadWire.player(data) {
            player = number > 0 ? number : nil
            noFreeSlot = number == 0
            publish()
        }
    }

    /// Startet MacSwitch neu oder wird der Host aus- und eingeschaltet, ändert sich sein Dienst: dann neu verbinden.
    func peripheral(_ p: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard invalidatedServices.contains(where: { $0.uuid == serviceID }) || input == nil else { return }
        resetLink()
        bluetooth = "MacSwitch neu gestartet – verbinde …"
        publish()
        p.discoverServices([serviceID])
    }

    private func scan() {
        guard central.state == .poweredOn else { return }
        bluetooth = "Suche MacSwitch …"
        publish()
        central.scanForPeripherals(withServices: [serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        bluetooth = "Verbinde …"
        publish()
        central.connect(p)
    }

    private func resetLink() {
        connected = false
        input = nil
        writes.removeAll()
        lastState = nil
        player = nil
        noFreeSlot = false
        waitingForWriteResponse = false
        pingTimer?.invalidate()
        pingTimer = nil
        pingsInFlight.removeAll()
        smoothedRoundTrip = nil
        roundTrip = nil
        publish()
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOff: "Bluetooth ist ausgeschaltet"
        case .unauthorized: "Bluetooth nicht erlaubt (Einstellungen → MacSwitch Controller)"
        case .unsupported: "Bluetooth LE wird nicht unterstützt"
        case .resetting: "Bluetooth wird neu gestartet …"
        default: "Bluetooth wird vorbereitet …"
        }
    }

    // MARK: Senden

    /// Schickt den Controller-Zustand. Wartet noch ein älterer Zustand mit denselben Tasten (nur die Sticks haben sich bewegt), wird er ersetzt:
    /// für Sticks zählt nur die neueste Stellung. Ein Tastenwechsel wird nie ersetzt, sonst ginge ein sehr kurzer Tipp verloren,
    /// wenn die Funkverbindung gerade ausgelastet ist.
    func send(_ state: PadState) {
        guard connected, state != lastState else { return }
        lastState = state
        let data = state.data
        if let last = writes.last, last.first == PadState.marker, last.dropFirst().prefix(4) == data.dropFirst().prefix(4) {
            writes[writes.count - 1] = data
        } else {
            writes.append(data)
        }
        flushWrites()
    }

    /// Stellt dieses iPhone dem Mac vor: Geräte-ID und Name. Daran erkennt er es wieder und gibt ihm seinen Platz zurück.
    private func sendHello() {
        guard let peripheral else { return }
        let key = "deviceID"
        let id = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        writes.append(PadWire.hello(deviceID: id, name: UIDevice.current.name, maxLength: max(20, peripheral.maximumWriteValueLength(for: .withoutResponse))))
    }

    /// Einmal pro Sekunde, und nur wenn keine Taste auf das Senden wartet: Messungen sollen nie eine Eingabe aufhalten.
    private func startPinging() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.connected, self.writes.isEmpty else { return }
            let now = CACurrentMediaTime()
            self.pingsInFlight = self.pingsInFlight.filter { now - $0.value < 3 }
            self.pingSequence &+= 1
            self.pingsInFlight[self.pingSequence] = now
            self.writes.append(PadWire.ping(sequence: self.pingSequence, lastRoundTrip: self.roundTrip))
            self.flushWrites()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        waitingForWriteResponse = false
        flushWrites()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { flushWrites() }

    /// Ohne Antwort schreiben, wo möglich: das spart pro Tastendruck eine Funk-Runde. Die Reihenfolge bleibt erhalten.
    private func flushWrites() {
        guard let peripheral, let input, connected else { return }
        if input.properties.contains(.writeWithoutResponse) {
            while peripheral.canSendWriteWithoutResponse && !writes.isEmpty {
                peripheral.writeValue(writes.removeFirst(), for: input, type: .withoutResponse)
            }
        } else if !waitingForWriteResponse, !writes.isEmpty {
            waitingForWriteResponse = true
            peripheral.writeValue(writes.removeFirst(), for: input, type: .withResponse)
        }
    }
}
