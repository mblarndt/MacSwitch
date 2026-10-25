import AppKit
import UniformTypeIdentifiers

struct Game: Identifiable {
    let url: URL
    let title: String
    let icon: NSImage?
    var id: String { url.path }

    init(ipa url: URL) {
        let info = IPA.read(url)
        self.url = url
        title = info.title ?? url.deletingPathExtension().lastPathComponent
        icon = info.icon
    }
}

final class GameLibrary: ObservableObject {
    static let folder = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacSwitch/Games", isDirectory: true)

    @Published var games: [Game] = []

    init() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        reload()
    }

    /// Scannt den Games-Ordner. shortcut: bekannte Dateinamen werden nicht neu gelesen – eine ersetzte IPA gleichen Namens erscheint erst nach App-Neustart.
    func reload() {
        let known = Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        DispatchQueue.global().async {
            let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
            let found = urls
                .filter { $0.pathExtension.lowercased() == "ipa" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { known[$0.path] ?? Game(ipa: $0) }
            DispatchQueue.main.async { self.games = found }
        }
    }

    func add(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls where url.pathExtension.lowercased() == "ipa" {
            let dest = Self.folder.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: url, to: dest) }
        }
        reload()
    }

    func addWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ipa")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { add(panel.urls) }
    }

    /// Übergibt die IPA ans System (Standard-App für .ipa, z. B. PlayCover). iOS-Apps laufen nur auf Apple Silicon.
    func launch(_ game: Game) {
        #if arch(arm64)
        NSWorkspace.shared.open(game.url)
        #else
        let alert = NSAlert()
        alert.messageText = "iOS-Spiele laufen nur auf Macs mit Apple Silicon."
        alert.runModal()
        #endif
    }
}

enum IPA {
    /// Liest Titel und Icon direkt aus der IPA (ein ZIP) – ohne sie zu entpacken.
    static func read(_ url: URL) -> (title: String?, icon: NSImage?) {
        guard let listing = unzip(["-Z1", url.path]).flatMap({ String(data: $0, encoding: .utf8) }) else { return (nil, nil) }
        let names = listing.split(separator: "\n").map(String.init)
        // Genau Payload/<Name>.app/Info.plist – tiefer verschachtelte Apps (Watch) ignorieren.
        guard let plistName = names.first(where: { $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist") && $0.split(separator: "/").count == 3 }),
              let plistData = entry(url, plistName),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return (nil, nil) }

        let title = plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String

        // shortcut: nur lose Icon-PNGs und iTunesArtwork; Icons nur im Assets.car → Platzhalter-Kachel.
        let appDir = String(plistName.dropLast("Info.plist".count))
        let primary = (plist["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        let stems = primary?["CFBundleIconFiles"] as? [String] ?? plist["CFBundleIconFiles"] as? [String] ?? []
        let icon = names
            .filter { n in n == "iTunesArtwork" || (n.hasSuffix(".png") && stems.contains { n.hasPrefix(appDir + $0) }) }
            .compactMap { n in entry(url, n).flatMap { NSImage(data: $0) } }
            .max { ($0.representations.first?.pixelsWide ?? 0) < ($1.representations.first?.pixelsWide ?? 0) }
        return (title, icon)
    }

    private static func entry(_ ipa: URL, _ name: String) -> Data? {
        // unzip behandelt Namen als Muster – Sonderzeichen escapen.
        let literal = name.replacingOccurrences(of: #"([\[\]*?\\])"#, with: #"\\$1"#, options: .regularExpression)
        return unzip(["-p", ipa.path, literal])
    }

    private static func unzip(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile() // vor waitUntilExit lesen, sonst Pipe-Deadlock
        p.waitUntilExit()
        return p.terminationStatus <= 1 ? data : nil // 1 = Warnung (z. B. Zusatzbytes vor dem ZIP)
    }
}
