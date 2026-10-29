import Foundation

/// Eine Einstellung eines nxnative-Spiels (dm/games/settings.tsv): eine Umgebungsvariable, die der Host beim Start liest.
struct GameSetting: Identifiable {
    enum Kind {
        case choice([(value: String, label: String)])
        case range(low: Double, high: Double, step: Double) // als Prozent angezeigt
        case toggle(on: String, off: String)
    }

    let env: String
    let section: String
    let label: String
    let note: String
    let kind: Kind
    var id: String { env }

    /// Der Wert nach einem Schritt vor (+1) oder zurück (−1) ab `current` (oder dem Standard): Auswahl und Schalter wechseln, Regler gehen einen Schritt und halten an den Enden.
    func stepped(from current: String?, by direction: Int, wrap: Bool = false) -> String {
        switch kind {
        case .choice(let options):
            let i = options.firstIndex { $0.value == current } ?? (direction > 0 ? -1 : options.count)
            return options[(i + direction + options.count) % options.count].value
        case .toggle(let on, let off):
            return current == on ? off : on
        case .range(let low, let high, let step):
            var v = (Double(current ?? "") ?? high) + Double(direction) * step
            if v > high + 1e-9 { v = wrap ? low : high }
            if v < low - 1e-9 { v = low }
            return Self.format((v * 1000).rounded() / 1000)
        }
    }

    static func format(_ v: Double) -> String { v == v.rounded() ? String(format: "%.1f", v) : "\(v)" }

    /// Anzeige für einen Wert (nil: nichts gesetzt und kein Standard bekannt).
    func text(for value: String?) -> String {
        guard let value else { return "Standard" }
        switch kind {
        case .choice(let options): return options.first { $0.value == value }?.label ?? value
        case .toggle(let on, _): return value == on ? "An" : "Aus"
        case .range: return Double(value).map { "\(Int(($0 * 100).rounded())) %" } ?? value
        }
    }
}

/// Die Teile des Spielprofils, die bestimmen, welche Einstellungen es für ein Spiel gibt und was ihr Standard ist.
struct GameProfile {
    var values = [String: String]() // game.tsv des Spiels im nxnative-Ordner (key<TAB>value)
    var fixups = Set<String>() // Schlüssel der Umschreibtabelle (main.fixups.tsv) in der App
    var nvn = true // Metal-Bibliotheken b-<Kette>: der NVN-Weg; Vulkan- und GL-Spiele haben die Leistungs-Einstellungen nicht

    init() {}

    init(game: Game, repo: URL) {
        let app = game.url.resolvingSymlinksInPath()
        let res = app.appendingPathComponent("Contents/Resources")
        if let id = Bundle(url: app)?.bundleIdentifier, let tid = id.range(of: "[0-9A-Fa-f]{16}$", options: .regularExpression).map({ String(id[$0]).uppercased() }),
           let text = try? String(contentsOf: repo.appendingPathComponent("dm/games/\(tid)/game.tsv"), encoding: .utf8) {
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let c = line.split(separator: "\t", maxSplits: 1).map(String.init)
                if c.count == 2, values[c[0]] == nil { values[c[0]] = c[1].split(separator: " ").first.map(String.init) ?? "" }
            }
        }
        for path in ["patched/main.fixups.tsv", "dm/main.fixups.tsv"] {
            guard let text = try? String(contentsOf: res.appendingPathComponent(path), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.hasPrefix("# ") {
                if let key = line.dropFirst(2).split(separator: "\t").first, line.contains("\t") { fixups.insert(String(key)) }
            }
        }
        if let msl = try? FileManager.default.contentsOfDirectory(atPath: res.appendingPathComponent("msl").path) { nvn = msl.contains { $0.hasPrefix("b-") } }
    }
}

enum GameSettings {
    static let catalog: [GameSetting] = [
        .init(env: "DM_FPS_TARGET", section: "Spiel", label: "Bildrate", note: "30 spart Strom, 60 läuft flüssiger.", kind: .choice([("30", "30 fps"), ("60", "60 fps")])),
        .init(env: "DM_RENDER_SCALE", section: "Spiel", label: "Renderauflösung", note: "Unter 100 % ist das 3D-Bild kleiner und die dynamische Auflösung des Spiels aus.", kind: .range(low: 0.5, high: 1.0, step: 0.05)),
        .init(env: "DM_OPMODE", section: "Spiel", label: "Konsolenmodus", note: "Docked rendert wie am Fernseher, Handheld kleiner.", kind: .choice([("1", "Docked"), ("0", "Handheld")])),
        .init(env: "DM_PRESENT_UPSCALE", section: "Spiel", label: "Hochskalierung", note: "MetalFX schärft Kanten und Text, braucht mehr GPU-Zeit.", kind: .choice([("off", "Standard"), ("metalfx", "MetalFX")])),
        .init(env: "DM_SHOW_FPS", section: "Spiel", label: "Bildraten-Anzeige", note: "", kind: .toggle(on: "1", off: "0")),
        .init(env: "DM_RUMBLE", section: "Steuerung", label: "Spiel-Vibration", note: "Auf Controllern mit Vibration.", kind: .toggle(on: "1", off: "0")),
        .init(env: "DM_RUMBLE_GAIN", section: "Steuerung", label: "Vibrationsstärke", note: "", kind: .range(low: 0, high: 3, step: 0.1)),
        .init(env: "DM_PRESENT_SNAP", section: "Leistung", label: "Bildpufferung", note: "Bis zu ein Bild mehr Verzögerung.", kind: .toggle(on: "1", off: "0")),
        .init(env: "DM_PSO_MTL4", section: "Leistung", label: "Metal-4-Pipelines", note: "Legt ein Pipeline-Archiv an, braucht mehr Speicher.", kind: .toggle(on: "1", off: "0")),
        .init(env: "DM_PSO_PREBUILD", section: "Leistung", label: "Pipelines vorab bauen", note: "Der erste Start wartet dafür einige Minuten, einmal.", kind: .toggle(on: "1", off: "0")),
        .init(env: "DM_NVN_ENC_THREAD", section: "Leistung", label: "Encode-Thread", note: "", kind: .toggle(on: "1", off: "0")),
        .init(env: "DM_FPS_HOLD", section: "Leistung", label: "Bilder bei Verspätung halten", note: "", kind: .toggle(on: "on", off: "off")),
        .init(env: "DM_METAL_HUD", section: "Leistung", label: "Leistungsanzeige (Metal-HUD)", note: "", kind: .toggle(on: "1", off: "0")),
    ]

    /// Die Einstellungen, die es für dieses Spiel gibt (wie die Bedingungen in settings.tsv). Ohne Profil: nur die, die immer gelten.
    static func available(for p: GameProfile) -> [GameSetting] {
        catalog.filter { s in
            switch s.env {
            case "DM_FPS_TARGET": (p.values["fps_target"] ?? "0") != "0"
            case "DM_FPS_HOLD": (p.values["fps_target"] ?? "0") != "0" && p.nvn
            case "DM_RENDER_SCALE": p.fixups.contains("RENDER_SCALE")
            case "DM_PRESENT_SNAP", "DM_PSO_MTL4", "DM_PSO_PREBUILD", "DM_NVN_ENC_THREAD": p.nvn
            default: true
            }
        }
    }

    /// Was der Host ohne Eingriff tut (Profil und Mac-Vorgaben); nil, wenn unbekannt.
    static func defaultValue(_ s: GameSetting, _ p: GameProfile) -> String? {
        switch s.env {
        case "DM_FPS_TARGET": p.values["fps_target"].flatMap { $0 == "0" ? nil : $0 }
        case "DM_RENDER_SCALE": "1.0"
        case "DM_OPMODE": (p.values["op_mode"] ?? "console") == "console" ? "1" : "0"
        case "DM_PRESENT_UPSCALE": "off"
        case "DM_RUMBLE": "1"
        case "DM_RUMBLE_GAIN": "1.0"
        case "DM_PRESENT_SNAP": (p.values["present_snap"] ?? "off") == "on" ? "1" : "0"
        case "DM_PSO_MTL4", "DM_PSO_PREBUILD", "DM_NVN_ENC_THREAD": "1" // auf dem Mac standardmäßig an
        case "DM_FPS_HOLD": (p.values["fps_hold"] ?? "on")
        case "DM_METAL_HUD": "0"
        default: nil
        }
    }
}

/// Die gewählten Werte je Spiel (Schlüssel: Name der App im Menü), als JSON in Application Support. Gespeichert wird nur, was vom Standard abweicht.
enum GameSettingsStore {
    static var file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacSwitch/settings.json")

    private static func load() -> [String: [String: String]] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
    }

    private static func save(_ all: [String: [String: String]]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: file, options: .atomic)
    }

    static func values(for key: String) -> [String: String] { load()[key] ?? [:] }

    static func set(_ env: String, _ value: String?, for key: String) {
        var all = load(), mine = all[key] ?? [:]
        mine[env] = value
        all[key] = mine.isEmpty ? nil : mine
        save(all)
    }

    static func reset(for key: String) {
        var all = load()
        all[key] = nil
        save(all)
    }
}
