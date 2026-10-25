import SwiftUI

/// Datei-Browser im Switch-Look: Ordner und Apps als weiße Zeilen mit Cursor. Enter fügt eine App dem Menü hinzu.
struct FileBrowser: View {
    @EnvironmentObject private var library: GameLibrary
    let close: () -> Void
    @State private var dir = URL(fileURLWithPath: "/Applications")
    @State private var entries: [URL] = []
    @State private var index = 0
    @State private var message: String?
    @FocusState private var focused: Bool

    /// Nur Ordner (ohne Pakete) und .app-Bundles, Ordner zuerst.
    static func entries(in dir: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)) ?? []
        func isFolder(_ u: URL) -> Bool {
            let v = try? u.resourceValues(forKeys: keys)
            return u.pathExtension != "app" && v?.isDirectory == true && v?.isPackage != true
        }
        return urls
            .filter { $0.pathExtension == "app" || isFolder($0) }
            .sorted { a, b in
                let fa = isFolder(a), fb = isFolder(b)
                return fa != fb ? fa : a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            footer
        }
        .frame(width: 1280, height: 720)
        .background(Theme.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { entries = Self.entries(in: dir); focused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, max(entries.count - 1, 0))
            case .leftArrow, .delete: goUp()
            case .rightArrow, .return: if press.phase == .down { open() }
            case .escape: if press.phase == .down { close() }
            default: return .ignored
            }
            return .handled
        }
    }

    private var header: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Circle()
                    .fill(Theme.dock)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "plus.app.fill").font(.system(size: 26)).foregroundStyle(Theme.cursor))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spiel hinzufügen").font(.system(size: 30, weight: .medium, design: .rounded))
                    Text(dir.path).font(.system(size: 18, design: .rounded)).foregroundStyle(Theme.subtle).lineLimit(1)
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
                Hint(key: "A", label: selectedIsApp ? "Hinzufügen" : "Öffnen")
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
            if !isApp {
                Image(systemName: "chevron.right").foregroundStyle(Theme.subtle)
            } else if library.contains(url) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.cursor)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 72)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.dock).shadow(color: .black.opacity(0.15), radius: 4, y: 2))
        .overlay { if selected { Cursor(shape: RoundedRectangle(cornerRadius: 12)) } }
        .contentShape(Rectangle())
    }

    private var selectedIsApp: Bool { entries.indices.contains(index) && entries[index].pathExtension == "app" }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard entries.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(entries[index], anchor: .center) }
    }

    private func open() {
        guard entries.indices.contains(index) else { return }
        let url = entries[index]
        guard url.pathExtension == "app" else { go(to: url); return }
        let name = url.deletingPathExtension().lastPathComponent
        message = library.contains(url) ? "\(name) ist schon im Menü" : "\(name) hinzugefügt"
        library.add([url])
    }

    private func goUp() {
        guard dir.path != "/" else { return }
        go(to: dir.deletingLastPathComponent(), selecting: dir)
    }

    private func go(to url: URL, selecting child: URL? = nil) {
        dir = url
        entries = Self.entries(in: url)
        message = nil
        index = child.flatMap { entries.firstIndex(of: $0) } ?? 0
    }
}
