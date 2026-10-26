import CoreBluetooth

/// iPhones als Controller: MacSwitch ist der Host der iPhone-App MacSwitch Controller (iPhoneController/; die AstrisPad-App spricht dasselbe Protokoll). Das iPhone verbindet sich per Bluetooth LE,
/// jedes bekommt einen Spielerplatz (1 bis 4), und die Zustände gehen als DSU-Server (cemuhook) auf 127.0.0.1:26760 an die Spiele:
/// der nxnative-Host liest sie dort als Spieler mit analogen Sticks (dm/host/dsu_pad.h). Tastaturausgabe, Ziel-App und Belegungen
/// des MacHost gibt es hier nicht; läuft MacHost selbst, ist der Port belegt und der Status sagt es.
/// Der Zustand gehört der eigenen Warteschlange (Bluetooth und DSU laufen darauf); die Oberfläche bekommt Schnappschüsse.
final class ControllerHost: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let playerCount = DSUServer.slotCount
    private static let enabledKey = "controllerHost"
    private static let savedPlayersKey = "controller.players"
    private static let deviceNamesKey = "controller.names"

    struct Player: Identifiable, Equatable {
        let number: Int
        var name: String? // das iPhone, das hier sitzt oder zuletzt saß
        var connected = false
        var latency: Int? // Antwortzeit hin und zurück in ms, vom iPhone gemessen
        var id: Int { number }
    }

    struct Snapshot: Equatable {
        var status = "Aus"
        var players = (1...ControllerHost.playerCount).map { Player(number: $0) }
        var waiting = 0 // iPhones ohne freien Platz
        var dsu = "aus"
    }

    @Published private(set) var snapshot = Snapshot()
    /// Menü-Tasten vom iPhone (Taste, Wiederholung); wird auf dem Haupt-Thread aufgerufen. Gesetzt von der HomeView.
    var onMenu: ((MenuPad.Key, Bool) -> Void)?
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { start() } else { stop() }
        }
    }

    private let queue = DispatchQueue(label: "MacSwitch.Controller", qos: .userInteractive)
    private let inputID = CBUUID(string: BLEIDs.input)
    private let presenceID = CBUUID(string: BLEIDs.presence)
    private var manager: CBPeripheralManager?
    private var presence: CBMutableCharacteristic?
    private var dsu: DSUServer?
    private var advertising = false
    /// Das iPhone mit dem niedrigsten Platz bedient auch das MacSwitch-Menü.
    private lazy var menuDriver = MenuDriver(queue: queue) { [weak self] key, isRepeat in self?.onMenu?(key, isRepeat) }
    private var bluetooth = "Bluetooth wird vorbereitet …"
    private var activity: NSObjectProtocol? // verhindert App Nap, solange ein iPhone verbunden ist

    private var subscribers = Set<UUID>()
    private var centrals = [UUID: CBCentral]()
    private var deviceOf = [UUID: String]() // Geräte-ID aus dem Hello
    private var playerOf = [UUID: Int]()
    private var assigned = Set<UUID>() // iPhones, die einen Platz haben oder auf einen warten
    private var lastStates = [UUID: GamepadState]()
    private var roundTrips = [UUID: Int]()
    private var pendingNotices = Set<UUID>()
    /// Gespeichert: welches iPhone (Geräte-ID) zuletzt welcher Spieler war, und wie es heißt.
    private var savedPlayers = UserDefaults.standard.dictionary(forKey: ControllerHost.savedPlayersKey) as? [String: Int] ?? [:]
    private var deviceNames = UserDefaults.standard.dictionary(forKey: ControllerHost.deviceNamesKey) as? [String: String] ?? [:]

    override init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        super.init()
        if enabled { start() }
    }

    /// Welchen Platz ein iPhone bekommt: seinen gespeicherten, wenn frei, sonst seinen jetzigen, sonst den kleinsten freien,
    /// den kein anderes bekanntes iPhone für sich hat. nil: alle belegt, es wartet.
    static func choosePlayer(device: String?, current: Int?, saved: [String: Int], taken: Set<Int>) -> Int? {
        let free = (1...playerCount).filter { !taken.contains($0) }
        if let device, let mine = saved[device], free.contains(mine) { return mine }
        if let current, free.contains(current) { return current }
        let reserved = Set(saved.filter { $0.key != device }.map(\.value))
        return free.first { !reserved.contains($0) } ?? free.first
    }

    // MARK: Ein und aus

    private func start() {
        queue.async {
            guard self.manager == nil else { return }
            let server = DSUServer(queue: self.queue)
            server.onClientsChanged = { [weak self] in self?.publish() }
            server.start()
            self.dsu = server
            self.manager = CBPeripheralManager(delegate: self, queue: self.queue) // fragt beim ersten Mal nach der Bluetooth-Berechtigung
            self.publish()
        }
    }

    private func stop() {
        queue.async {
            self.manager?.stopAdvertising()
            self.manager?.removeAllServices()
            self.manager = nil
            self.presence = nil
            self.advertising = false
            self.dsu?.stop()
            self.dsu = nil
            self.resetPhones()
            self.driveMenu()
            self.updateActivity()
            self.publish()
        }
    }

    private func resetPhones() {
        subscribers.removeAll(); centrals.removeAll(); deviceOf.removeAll(); playerOf.removeAll()
        assigned.removeAll(); lastStates.removeAll(); roundTrips.removeAll(); pendingNotices.removeAll()
    }

    // MARK: Bluetooth

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            resetPhones()
            syncDSU()
            presence = nil
            advertising = false
            updateActivity()
            bluetooth = Self.describe(peripheral.state)
            publish()
            return
        }
        let service = CBMutableService(type: CBUUID(string: BLEIDs.service), primary: true)
        let input = CBMutableCharacteristic(type: inputID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let presence = CBMutableCharacteristic(type: presenceID, properties: [.notify], value: nil, permissions: [.readable])
        service.characteristics = [input, presence]
        self.presence = presence
        peripheral.removeAllServices()
        peripheral.add(service)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error { bluetooth = "BLE-Service-Fehler: \(error.localizedDescription)"; return publish() }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLEIDs.service)], CBAdvertisementDataLocalNameKey: "AstrisPad Mac"])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error { bluetooth = "Advertising-Fehler: \(error.localizedDescription)"; return publish() }
        advertising = true
        publish()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == presenceID else { return }
        subscribers.insert(central.identifier)
        centrals[central.identifier] = central
        peripheral.setDesiredConnectionLatency(.low, for: central) // kürzeres Funkintervall; das iPhone muss nicht zustimmen
        if assigned.contains(central.identifier) { notifyPlayer(central.identifier) } // kam das Hello vor dem Abo, erfährt das iPhone seinen Platz erst jetzt
        updateActivity()
        publish()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == presenceID else { return }
        let phone = central.identifier
        subscribers.remove(phone)
        playerOf[phone] = nil; deviceOf[phone] = nil; roundTrips[phone] = nil; lastStates[phone] = nil; centrals[phone] = nil
        assigned.remove(phone); pendingNotices.remove(phone)
        syncDSU()
        for waiting in assigned where playerOf[waiting] == nil { assignPlayer(waiting) } // ein frei gewordener Platz geht an ein wartendes iPhone
        updateActivity()
        publish()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        var result = CBATTError.Code.success
        for req in requests {
            guard req.characteristic.uuid == inputID, let data = req.value else { result = .unlikelyError; continue }
            if let ping = Ping.parseRequest(data) {
                answer(ping.sequence, to: req.central)
                if ping.lastRoundTrip > 0, roundTrips[req.central.identifier] != ping.lastRoundTrip { roundTrips[req.central.identifier] = ping.lastRoundTrip; publish() }
            } else if let hello = Hello(data: data) {
                register(hello, from: req.central)
            } else if let sample = MotionSample(data: data) {
                if let player = playerOf[req.central.identifier] { dsu?.updateMotion(slot: player - 1, sample: sample) }
            } else if let state = GamepadState(data: data) {
                handle(state, from: req.central)
            } else if data.first == 0x4C || data.count == 3 {
                // Layout-Modus und fertige Mac-Tasten (Tastatur-und-Maus-Layouts): MacSwitch gibt keine Tasten aus.
            } else {
                result = .unlikelyError
            }
        }
        peripheral.respond(to: first, withResult: result) // Core Bluetooth erwartet genau eine Antwort pro Aufruf, für die erste Anfrage
    }

    /// Antwortet sofort auf eine Messung. Ist der Sendepuffer voll, fällt diese eine Messung aus.
    private func answer(_ sequence: UInt16, to central: CBCentral) {
        guard let presence, let manager else { return }
        _ = manager.updateValue(Ping.reply(sequence: sequence), for: presence, onSubscribedCentrals: [central])
    }

    // MARK: Spieler

    /// Ein iPhone stellt sich vor. Kennt der Mac es schon, bekommt es seinen gespeicherten Platz zurück.
    private func register(_ hello: Hello, from central: CBCentral) {
        let phone = central.identifier
        centrals[phone] = central
        let device = hello.deviceID.uuidString
        deviceOf[phone] = device
        let name = hello.name.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceNames[device] = name.isEmpty ? "iPhone" : String(name.prefix(40))
        UserDefaults.standard.set(deviceNames, forKey: Self.deviceNamesKey)
        assignPlayer(phone)
    }

    private func handle(_ state: GamepadState, from central: CBCentral) {
        let phone = central.identifier
        centrals[phone] = central
        lastStates[phone] = state
        if !assigned.contains(phone) { assignPlayer(phone) } // ohne Hello bekommt es trotzdem einen Platz
        syncDSU()
    }

    private func assignPlayer(_ phone: UUID) {
        assigned.insert(phone)
        let device = deviceOf[phone]
        let taken = Set(playerOf.filter { $0.key != phone }.map(\.value))
        let player = Self.choosePlayer(device: device, current: playerOf[phone], saved: savedPlayers, taken: taken)
        playerOf[phone] = player
        if let player, let device {
            savedPlayers[device] = player
            UserDefaults.standard.set(savedPlayers, forKey: Self.savedPlayersKey)
        }
        notifyPlayer(phone)
        syncDSU()
        publish()
    }

    private func notifyPlayer(_ phone: UUID) {
        guard let presence, let manager, let central = centrals[phone], subscribers.contains(phone) else { return }
        if manager.updateValue(PlayerMessage.data(player: playerOf[phone]), for: presence, onSubscribedCentrals: [central]) {
            pendingNotices.remove(phone)
        } else {
            pendingNotices.insert(phone)
        }
    }

    /// Der Sendepuffer hat wieder Platz: ausstehende Spielernummern nachreichen.
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        for phone in pendingNotices { notifyPlayer(phone) }
    }

    /// Gibt jedem Spielerplatz mit verbundenem iPhone seinen Zustand an die DSU-Clients (Slot = Spieler − 1).
    private func syncDSU() {
        driveMenu()
        guard let dsu else { return }
        for slot in 0..<Self.playerCount {
            let phone = playerOf.first { $0.value == slot + 1 && subscribers.contains($0.key) }?.key
            dsu.update(slot: slot, state: phone.map { lastStates[$0] ?? .neutral })
        }
    }

    private func driveMenu() {
        let phone = playerOf.filter { subscribers.contains($0.key) }.min { $0.value < $1.value }?.key
        menuDriver.update(phone.flatMap { lastStates[$0] })
    }

    // MARK: Zustand

    private func updateActivity() {
        if !subscribers.isEmpty && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Controller-Eingaben vom iPhone")
        } else if subscribers.isEmpty, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    private func publish() {
        var s = Snapshot()
        if manager == nil {
            s.status = "Aus"
        } else if advertising {
            s.status = subscribers.isEmpty ? "Bereit – auf dem iPhone MacSwitch Controller öffnen" : subscribers.count == 1 ? "1 iPhone verbunden" : "\(subscribers.count) iPhones verbunden"
        } else {
            s.status = bluetooth
        }
        for n in 1...Self.playerCount {
            let phone = playerOf.first { $0.value == n && subscribers.contains($0.key) }?.key
            let device = phone.flatMap { deviceOf[$0] } ?? savedPlayers.first { $0.value == n }?.key
            s.players[n - 1] = Player(number: n, name: phone != nil ? (device.flatMap { deviceNames[$0] } ?? "iPhone") : device.flatMap { deviceNames[$0] },
                                      connected: phone != nil, latency: phone.flatMap { roundTrips[$0] })
        }
        s.waiting = assigned.filter { playerOf[$0] == nil }.count
        s.dsu = dsu.map { $0.isRunning ? "127.0.0.1:\(DSUServer.port) · \($0.clientCount) Spiel(e) verbunden" : ($0.error ?? "gestoppt") } ?? "aus"
        DispatchQueue.main.async { self.snapshot = s }
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOff: "Bluetooth ist ausgeschaltet"
        case .unauthorized: "Bluetooth für MacSwitch nicht erlaubt (Systemeinstellungen → Datenschutz & Sicherheit → Bluetooth)"
        case .unsupported: "Dieser Mac unterstützt Bluetooth LE nicht"
        case .resetting: "Bluetooth wird neu gestartet …"
        default: "Bluetooth wird vorbereitet …"
        }
    }
}
