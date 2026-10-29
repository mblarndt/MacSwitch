import SwiftUI

/// Datei-Browser im Switch-Look: Ordner und Apps als weiße Zeilen mit Cursor. Enter fügt eine App dem Menü hinzu.
/// Mit `kind` wählt er stattdessen eine Datei (Enter) oder den aktuellen Ordner (Leertaste) und meldet sie über `choose`.
/// Mit `all` wählt die Leertaste (+) stattdessen alle passenden Dateien des geöffneten Ordners auf einmal und meldet sie über `all`.
struct FileBrowser: View {
    enum Kind {
        case app
        case file([String]) // erlaubte Endungen, klein geschrieben
        case folder

        var symbol: String { if case .app = self { "plus.app.fill" } else { "folder.fill" } }
    }

    @EnvironmentObject private var library: GameLibrary
    let kind: Kind
    let title: String
    let choose: (URL) -> Void
    let all: (([URL]) -> Void)?
    let close: () -> Void
    @State private var dir: URL
    @State private var entries: [URL] = []
    @State private var index = 0
    @State private var message: String?
    @FocusState private var focused: Bool

    init(kind: Kind = .app, title: String = "Spiel hinzufügen", start: URL = URL(fileURLWithPath: "/Applications"),
         choose: @escaping (URL) -> Void = { _ in }, all: (([URL]) -> Void)? = nil, close: @escaping () -> Void) {
        self.kind = kind
        self.title = title
        self.choose = choose
        self.all = all
        self.close = close
        _dir = State(initialValue: start)
    }

    static func isFolder(_ u: URL) -> Bool {
        let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return u.pathExtension != "app" && v?.isDirectory == true && v?.isPackage != true
    }

    /// Ordner (ohne Pakete) zuerst, dann je nach `kind` .app-Bundles bzw. Dateien mit passender Endung.
    static func entries(in dir: URL, kind: Kind = .app) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: .skipsHiddenFiles)) ?? []
        func keep(_ u: URL) -> Bool {
            if isFolder(u) { return true }
            switch kind {
            case .app: return u.pathExtension == "app"
            case .file(let exts): return exts.contains(u.pathExtension.lowercased())
            case .folder: return false
            }
        }
        return urls
            .filter(keep)
            .sorted { a, b in
                let fa = isFolder(a), fb = isFolder(b)
                return fa != fb ? fa : a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(symbol: kind.symbol, title: title, subtitle: dir.path, message: message)
            list
            footer
        }
        .frame(width: 1280, height: 720)
        .background(Theme.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { entries = Self.entries(in: dir, kind: kind); focused = true }
        .pageKeys { press in
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, max(entries.count - 1, 0))
            case .leftArrow, .delete: goUp()
            case .rightArrow, .return: if press.isDown { open() }
            case .space:
                if case .folder = kind { if press.isDown { pickFolder() } }
                else if all != nil { if press.isDown { pickAll() } }
                else { return .ignored }
            case .escape: if press.isDown { close() }
            default: return .ignored
            }
            return .handled
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(entries.enumerated()), id: \.element) { i, url in
                        row(url, selected: i == index).id(url).onTapGesture { if i == index { open() } else { index = i } }
                    }
                }
                .padding(.horizontal, 140)
                .padding(.vertical, 24)
            }
            .id(dir) // neuer Ordner → Scrollposition zurücksetzen
            .onAppear { DispatchQueue.main.async { scroll(proxy) } }
            .onChange(of: index) { _, _ in scroll(proxy) }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                Spacer()
                Hint(key: "←", label: "Ordner zurück").onTapGesture { goUp() }
                Hint(key: "B", label: "Schließen").onTapGesture { close() }
                if case .folder = kind { Hint(key: "+", label: "Diesen Ordner wählen").onTapGesture { pickFolder() } }
                else if all != nil { Hint(key: "+", label: "Alle auswählen").onTapGesture { pickAll() } }
                Hint(key: "A", label: selectedIsFile ? pickLabel : "Öffnen")
            }
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 26)
    }

    private func row(_ url: URL, selected: Bool) -> some View {
        let isApp = url.pathExtension == "app"
        return HStack(spacing: 22) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 48, height: 48)
            Text(isApp ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent)
                .font(.system(size: 26, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            if Self.isFolder(url) {
                Image(systemName: "chevron.right").foregroundStyle(Theme.subtle)
            } else if isApp && library.contains(url) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.cursor)
            }
        }
        .menuRow(selected: selected)
    }

    private var selectedIsFile: Bool { entries.indices.contains(index) && !Self.isFolder(entries[index]) }
    private var pickLabel: String { if case .app = kind { "Hinzufügen" } else { "Wählen" } }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard entries.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(entries[index], anchor: .center) }
    }

    private func open() {
        guard entries.indices.contains(index) else { return }
        let url = entries[index]
        if Self.isFolder(url) { return go(to: url) }
        guard case .app = kind else { choose(url); close(); return }
        let name = url.deletingPathExtension().lastPathComponent
        message = library.contains(url) ? "\(name) ist schon im Menü" : "\(name) hinzugefügt"
        library.add([url])
    }

    private func pickFolder() {
        choose(dir)
        close()
    }

    private func pickAll() {
        let files = entries.filter { !Self.isFolder($0) }
        guard !files.isEmpty else { message = "Keine passenden Dateien in diesem Ordner"; return }
        all?(files)
        close()
    }

    private func goUp() {
        guard dir.path != "/" else { return }
        go(to: dir.deletingLastPathComponent(), selecting: dir)
    }

    private func go(to url: URL, selecting child: URL? = nil) {
        dir = url
        entries = Self.entries(in: url, kind: kind)
        message = nil
        index = child.flatMap { entries.firstIndex(of: $0) } ?? 0
    }
}

/// Kopf der Menü-Seiten: Symbol im Kreis, Titel, Unterzeile und rechts eine Meldung.
struct ScreenHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var message: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Circle()
                    .fill(Theme.dock)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Theme.cursor))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 30, weight: .medium, design: .rounded))
                    Text(subtitle).font(.system(size: 18, design: .rounded)).foregroundStyle(Theme.subtle).lineLimit(1)
                }
                Spacer()
                if let message { Text(message).font(.system(size: 20, design: .rounded)).foregroundStyle(Theme.cursor) }
            }
            .foregroundStyle(Theme.text)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.top, 34)
        .padding(.horizontal, 56)
    }
}

extension View {
    /// Weiße Switch-Zeile mit pulsierendem Cursor, solange sie ausgewählt ist.
    func menuRow(selected: Bool) -> some View {
        padding(.horizontal, 28)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.dock).shadow(color: .black.opacity(0.15), radius: 4, y: 2))
            .overlay { if selected { Cursor(shape: RoundedRectangle(cornerRadius: 12)) } }
            .contentShape(Rectangle())
    }
}
