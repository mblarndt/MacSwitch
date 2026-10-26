import Foundation

/// Hat nxnative ein "Rezept" (Spielprofil, dm/games/<Title-ID>/game.tsv) für ein Spiel? Nur dafür sind Build und Einstellungen getestet;
/// für andere schreibt das Skript eine Übersicht und versucht es trotzdem, die App startet dann vielleicht nicht.
enum Recipe {
    enum Result: Equatable {
        case found(name: String, versions: [String]) // Profil im nxnative-Ordner; getestete Versionen
        case upstreamOnly // erst im offiziellen Repository: nxnative aktualisieren
        case missing(titleID: String)
        case unknown // Titel-ID nicht erkennbar

        var text: String {
            switch self {
            case .found(let name, let versions): "vorhanden: \(name)" + (versions.isEmpty ? "" : " (getestet: \(versions.prefix(4).joined(separator: ", ")))")
            case .upstreamOnly: "erst im offiziellen Repository: nxnative aktualisieren"
            case .missing(let id): "keins für \(id): nxnative versucht es trotzdem, die App startet vielleicht nicht"
            case .unknown: "Titel-ID nicht erkennbar"
            }
        }

        var good: Bool { if case .found = self { true } else { false } }
    }

    /// Die Titel-ID des Basisspiels: das `[16 Hex-Ziffern]` im Dateinamen, sonst der Ticket-Name in der NSP (die ersten 16 Ziffern der Rights-ID). Ein Update (…800) zählt als sein Basisspiel.
    static func titleID(of rom: URL) -> String? {
        let name = rom.lastPathComponent
        var id = name.range(of: #"\[([0-9A-Fa-f]{16})\]"#, options: .regularExpression).map { String(name[$0].dropFirst().dropLast()) }
        if id == nil, ["nsp", "nsz"].contains(rom.pathExtension.lowercased()) {
            id = ticketNames(in: rom).first { $0.range(of: #"^[0-9A-Fa-f]{32}\.tik$"#, options: .regularExpression) != nil }.map { String($0.prefix(16)) }
        }
        guard var tid = id.map({ String($0.prefix(16)).uppercased() }), tid.count == 16 else { return nil }
        if tid.hasSuffix("800") { tid = String(tid.dropLast(3)) + "000" }
        return tid
    }

    /// Die Dateinamen im Kopf einer NSP (PFS0): Kennung, Anzahl, Größe der Namenstabelle, dann 24 Byte je Datei, dann die Namen.
    static func ticketNames(in nsp: URL) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: nsp) else { return [] }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 16), head.count == 16, head.prefix(4) == Data("PFS0".utf8) else { return [] }
        func u32(_ at: Int) -> Int { Int(head[at]) | Int(head[at + 1]) << 8 | Int(head[at + 2]) << 16 | Int(head[at + 3]) << 24 }
        let count = u32(4), table = u32(8)
        guard count < 4096, table < 1 << 20, let rest = try? h.read(upToCount: count * 24 + table), rest.count == count * 24 + table else { return [] }
        let names = rest.suffix(table)
        return names.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    }

    static func lookup(rom: URL, repo: URL) -> Result {
        guard let tid = titleID(of: rom) else { return .unknown }
        let path = "dm/games/\(tid)/game.tsv"
        if let text = try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8) {
            var name = tid, versions = [String]()
            for line in text.split(separator: "\n") where !line.hasPrefix("#") {
                let c = line.split(separator: "\t").map(String.init)
                if c.first == "name", c.count > 1 { name = c[1] }
                if c.first == "build", c.count > 2 { versions.append(c[2]) }
            }
            return .found(name: name, versions: versions)
        }
        if NxnativeUpdater.git(["cat-file", "-e", "@{u}:\(path)"], in: repo, timeout: 10).status == 0 { return .upstreamOnly }
        return .missing(titleID: tid)
    }
}
