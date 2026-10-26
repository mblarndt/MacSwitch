import AppKit

/// Baut mit nxnative aus Switch-Dateien (NSP/XCI/NSZ/XCZ + prod.keys) eine Mac-App und legt sie ins Menü.
/// Das ist die Mac-Seite der Fenster-App "NxNative Builder" (nxnative/scripts/NxNativeBuilder.swift): dieselben Skripte, derselbe Ablauf.
/// Die Dateien werden nicht kopiert, sondern nach <Ausgabe>/NxNative-Work/<Spielname>/ verlinkt; dort liegen auch die Zwischenergebnisse,
/// ein zweiter Build desselben Spiels geht damit schneller.
final class GameBuilder: ObservableObject {
    /// Eine Zeile von `build_ipa_from_nsp.py --progress json`.
    private struct Event: Decodable {
        var ev: String
        var k: Int?, n: Int?, name: String?, step: String?, note: String?, msg: String?
        var frac: Double?, eta: Double?
    }

    private struct Failure: LocalizedError { var errorDescription: String? }

    /// Teilt einen Byte-Strom in Zeilen; gefüttert wird nur von der Queue der Pipe.
    private final class Lines: @unchecked Sendable {
        private var buf = Data()
        func feed(_ d: Data) -> [String] {
            buf.append(d)
            var out: [String] = []
            while let i = buf.firstIndex(of: 10) { out.append(String(decoding: buf[..<i], as: UTF8.self)); buf.removeSubrange(...i) }
            return out
        }
    }

    static let extensions = ["nsp", "xci", "nsz", "xcz"]
    private static let scripts = ["build_ipa_from_nsp.py", "make_mac_app.py"]

    @Published var repo = GameBuilder.saved("nxRepo") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("GitHub/nxnative") { didSet { Self.save("nxRepo", repo) } }
    @Published var rom: URL?
    @Published var update: URL?
    @Published var dlcs: [URL] = []
    @Published var keys = GameBuilder.saved("nxKeys") { didSet { Self.save("nxKeys", keys) } }
    @Published var out = GameBuilder.saved("nxOut") { didSet { Self.save("nxOut", out) } }
    @Published private(set) var running = false
    @Published private(set) var overall = 0.0
    @Published private(set) var status = "" // leer = kein Lauf zu zeigen
    @Published private(set) var detail = ""
    @Published private(set) var error = ""
    @Published private(set) var log: [String] = []
    private var process: Process?, activity: NSObjectProtocol?, onDone: ((URL) -> Void)?
    private var target = URL(fileURLWithPath: "/"), name = ""
    private var runCommand = "", lastError = "", making = false
    private var k = 1, n = 1, stageName = "", stepName = "", frac = 0.0

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel() }
    }

    private static func saved(_ key: String) -> URL? { UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0) } }
    private static func save(_ key: String, _ url: URL?) { UserDefaults.standard.set(url?.path, forKey: key) }

    /// Der nxnative-Ordner enthält beide Skripte. make_mac_app.py fehlt in einem frischen Klon: sonst scheiterte der Lauf erst nach dem Build.
    var repoValid: Bool { Self.scripts.allSatisfy { FileManager.default.fileExists(atPath: script($0)) } }
    var canRebuild: Bool { keys != nil && repoValid && !running }
    var ready: Bool { rom != nil && out != nil && canRebuild }

    /// Wo der Browser für prod.keys anfängt: dort, wo zuletzt eine lag, sonst ~/.switch.
    var keysStart: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser, switchDir = home.appendingPathComponent(".switch")
        return keys?.deletingLastPathComponent() ?? (FileManager.default.fileExists(atPath: switchDir.path) ? switchDir : home)
    }

    /// <Ausgabe>/NxNative-Work/<Spielname> neben der .app: dort liegen die verlinkten NSPs, egal ob MacSwitch oder NxNative Builder die App gebaut hat.
    /// nil bei Apps, die nicht so gebaut wurden – für die gibt es keine Updates oder DLC.
    static func workFolder(of game: Game) -> URL? {
        let app = game.url.resolvingSymlinksInPath()
        let dir = app.deletingLastPathComponent().appendingPathComponent("NxNative-Work/\(app.deletingPathExtension().lastPathComponent)")
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Eine mit nxnative gebaute App (sie enthält den Host): nur für die gibt es Einstellungen.
    static func isNxnative(_ game: Game) -> Bool {
        FileManager.default.fileExists(atPath: game.url.resolvingSymlinksInPath().appendingPathComponent("Contents/Resources/dmhost").path)
    }

    /// Die Spieldateien im Arbeitsordner (Basisspiel, Updates, DLC); die Ordner daneben (<id>_build/) sind Zwischenstände.
    static func installedFiles(in work: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Verknüpft eine Update-/DLC-Datei in den Arbeitsordner, ohne die vorhandenen Links anzufassen. Das Skript erkennt selbst, was Update und was DLC ist.
    static func install(_ file: URL, into work: URL) throws {
        let fm = FileManager.default, ext = file.pathExtension.lowercased()
        guard extensions.contains(ext) else { throw Failure(errorDescription: "\(file.lastPathComponent) ist keine NSP-/XCI-/NSZ-/XCZ-Datei.") }
        let base = file.deletingPathExtension().lastPathComponent + "." + ext
        var n = 0
        while true {
            let link = work.appendingPathComponent((n == 0 ? "" : "\(n)-") + base)
            if (try? fm.attributesOfItem(atPath: link.path)) == nil { return try fm.createSymbolicLink(at: link, withDestinationURL: file) }
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == file.path { return } // dieselbe Datei nochmal: nichts zu tun
            n += 1 // anderer Inhalt unter gleichem Namen (zwei DLC-Ordner)
        }
    }

    private func script(_ name: String) -> String { repo.appendingPathComponent("scripts/\(name)").path }

    /// Der Spielname für App und Arbeitsordner: Dateiname der Basisdatei ohne [Title-ID]- und (Versions-)Tags.
    static func name(_ rom: URL) -> String {
        let s = rom.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"\s*[\[(][^\])]*[\])]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[/:"$`\\]"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "Game" : s
    }

    /// `done` bekommt die fertige .app (im Menü: zur Library hinzufügen).
    func start(done: @escaping (URL) -> Void) {
        guard ready, let rom, let out else { return }
        name = Self.name(rom)
        target = out.appendingPathComponent(name + ".app")
        do { try begin(link(into: out.appendingPathComponent("NxNative-Work/\(name)"), [rom] + [update].compactMap { $0 } + dlcs), done) } catch { fail(error.localizedDescription) }
    }

    /// Baut ein vorhandenes Spiel aus seinem Arbeitsordner neu (nach einem installierten Update oder DLC): gleicher Name, gleicher Pfad, die Spielstände bleiben.
    /// Was sich nicht geändert hat, übernimmt das Skript aus dem letzten Lauf.
    func rebuild(_ game: Game, done: @escaping (URL) -> Void) {
        guard canRebuild, let work = Self.workFolder(of: game) else { return }
        target = game.url.resolvingSymlinksInPath()
        name = target.deletingPathExtension().lastPathComponent
        begin(work, done)
    }

    private func begin(_ nsp: URL, _ done: @escaping (URL) -> Void) {
        guard let keys else { return }
        onDone = done
        running = true; error = ""; lastError = ""; runCommand = ""; making = false; log = []; overall = 0
        k = 1; n = 1; frac = 0; stageName = ""; stepName = ""; status = "Starte …"; detail = ""
        do {
            try launch([script("build_ipa_from_nsp.py"), nsp.path, "-k", keys.path, "--progress", "json", "--platform", "mac"])
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Spiel wird gebaut")
        } catch { fail(error.localizedDescription) }
    }

    func cancel() { process?.interrupt() } // SIGINT: das Skript stoppt seine Tools und endet mit 130; der nächste Lauf nutzt das Fertige weiter

    /// Zurück zur Auswahl, nachdem ein Lauf zu Ende ist.
    func reset() { status = ""; detail = ""; error = ""; overall = 0 }

    /// Läuft über eine Login-Shell: sie hat den PATH des Terminals (python3 mit lz4, capstone, fonttools), den eine GUI-App sonst nicht hat.
    private func launch(_ args: [String]) throws {
        let p = Process(), o = Pipe(), e = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", #"exec python3 "$@""#, "python3"] + args
        p.standardOutput = o; p.standardError = e
        p.terminationHandler = { p in
            let code = p.terminationReason == .uncaughtSignal ? 130 : p.terminationStatus // ein vom Abbruch getötetes Python
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.finish(code) } // die letzten Zeilen kommen noch an
        }
        try p.run()
        process = p
        read(o) { self.handle($0) }
        read(e) { self.log.append($0); self.lastError = $0 }
    }

    /// Ruft `on` je Zeile auf, sobald sie ankommt (FileHandle.bytes.lines hält Zeilen zurück, bis der Puffer voll ist).
    private func read(_ pipe: Pipe, _ on: @escaping (String) -> Void) {
        let lines = Lines()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { return h.readabilityHandler = nil } // Ende der Ausgabe
            let ls = lines.feed(d)
            DispatchQueue.main.async { ls.forEach(on) }
        }
    }

    private func fail(_ m: String) { error = m; status = "Fehlgeschlagen"; running = false }

    /// <dir> enthält genau die gewählten Dateien als Links (so benannt, wie das Skript sie sucht); die Ordner daneben (<id>_build/) bleiben für den nächsten Lauf.
    private func link(into dir: URL, _ files: [URL]) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for old in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey]) where (try? old.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { try fm.removeItem(at: old) }
        var used = Set<String>()
        for f in files {
            let ext = f.pathExtension.lowercased()
            guard Self.extensions.contains(ext) else { throw Failure(errorDescription: "\(f.lastPathComponent) ist keine NSP-/XCI-/NSZ-/XCZ-Datei.") }
            var name = f.deletingPathExtension().lastPathComponent + "." + ext
            if used.contains(name) { name = "\(used.count)-" + name } // zwei DLC-Ordner können denselben Dateinamen haben
            used.insert(name)
            try fm.createSymbolicLink(at: dir.appendingPathComponent(name), withDestinationURL: f)
        }
        return dir
    }

    private func handle(_ line: String) {
        guard let e = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else { return log.append(line) }
        switch e.ev {
        case "stage": k = e.k ?? k; n = max(e.n ?? n, 1); stageName = e.name ?? ""; stepName = e.step ?? ""; frac = 0; detail = ""
        case "step": stepName = e.step ?? ""; frac = 0; detail = ""
        case "progress":
            stepName = e.step ?? stepName; frac = e.frac ?? frac
            detail = [e.note ?? "", e.frac.map { "\(Int($0 * 100)) %" } ?? "", e.eta.map { "noch etwa \(Self.clock($0))" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        case "stage_end": frac = 1
        case "say":
            log.append(e.msg ?? "")
            if let m = e.msg, m.hasPrefix("[RED]") { error = String(m.dropFirst(6)) }
            if let m = e.msg, m.hasPrefix("cd ") { runCommand = m } // letzte Zeile eines Mac-Builds: der Befehl, der das Spiel startet
        default: break
        }
        status = "[\(k)/\(n)] \(stageName)" + (stepName.isEmpty ? "" : " · \(stepName)")
        overall = min((Double(k - 1) + frac) / Double(n + 1), 1) // die App ist eine Stufe mehr als die n des Skripts
    }

    /// Nach dem Build folgt make_mac_app.py, das aus dem Ergebnis die eigenständige .app macht.
    private func finish(_ code: Int32) {
        if code == 0, !making {
            guard !runCommand.isEmpty else { return end(1, "Der Build hat den Startbefehl des Spiels nicht ausgegeben.") }
            making = true; status = "[\(n + 1)/\(n + 1)] Mac-App"; detail = "\(target.lastPathComponent) wird angelegt"; overall = Double(n) / Double(n + 1)
            do { try launch([script("make_mac_app.py"), target.path, name, runCommand]) } catch { fail(error.localizedDescription) }
            return
        }
        end(code)
    }

    private func end(_ code: Int32, _ message: String? = nil) {
        running = false; process = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        switch code {
        case 0:
            overall = 1; status = "Fertig"; detail = "\(name) ist jetzt im Menü"
            onDone?(target)
        case 130:
            status = "Abgebrochen"; error = ""
        default:
            status = "Fehlgeschlagen"
            if let message { error = message } else if error.isEmpty { error = lastError.isEmpty ? "Der Build ist mit Code \(code) abgebrochen; siehe Log." : lastError }
        }
    }

    static func clock(_ s: Double) -> String { let s = Int(s); return s >= 3600 ? "\(s / 3600) h \(s % 3600 / 60) min" : s >= 60 ? "\(s / 60) min" : "\(s) s" }
}
