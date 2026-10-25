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
        icon = NSWorkspace.shared.icon(forFile: real.path).trimmed()
    }
}

extension NSImage {
    /// Schneidet den transparenten Rand ab (macOS-Icons haben ~10 % Padding), damit das Icon die ganze Kachel füllt.
    func trimmed() -> NSImage {
        let w = 512
        var rect = NSRect(x: 0, y: 0, width: w, height: w)
        guard let cg = cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.assumingMemoryBound(to: UInt8.self)
        else { return self }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: w))

        var minX = w, minY = w, maxX = -1, maxY = -1
        for y in 0..<w {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 128 { // >50 % deckend: ignoriert Schatten und Antialiasing
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, let out = ctx.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return self }
        return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
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
