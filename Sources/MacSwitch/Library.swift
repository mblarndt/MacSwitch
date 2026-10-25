import AppKit

struct Game: Identifiable {
    let url: URL // Eintrag im Games-Ordner (normalerweise ein Symlink auf die echte App)
    let title: String
    let icon: NSImage
    var id: String { url.path }

    init(app url: URL) {
        let real = url.resolvingSymlinksInPath()
        let bundle = Bundle(url: real)
        self.url = url
        title = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? real.deletingPathExtension().lastPathComponent
        icon = NSWorkspace.shared.icon(forFile: real.path)
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

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        games = urls
            .filter { $0.pathExtension == "app" && FileManager.default.fileExists(atPath: $0.path) } // fileExists folgt Symlinks → verwaiste Links fallen raus
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(Game.init(app:))
    }

    /// Verknüpft die App per Symlink im Games-Ordner – kopiert wird nichts. Entfernen = Symlink im Ordner löschen.
    func add(_ urls: [URL]) {
        for url in urls where url.pathExtension == "app" {
            let link = Self.folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: url) // existiert schon → Fehler ignoriert
        }
        reload()
    }

    func contains(_ app: URL) -> Bool {
        games.contains { $0.url.lastPathComponent == app.lastPathComponent }
    }
}
