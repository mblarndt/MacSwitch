import SwiftUI

/// Optionen eines mit nxnative gebauten Spiels: Update oder DLC installieren (die Datei wird in den Arbeitsordner des Spiels verlinkt) und neu bauen.
/// Das Neu-Bauen zeigt die Builder-Seite, der Lauf gehört wie dort dem GameBuilder.
struct GameOptionsView: View {
    private enum Field: Hashable {
        case settings, update, dlc, keys, build, file(URL)
    }

    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var builder: GameBuilder
    let game: Game
    let close: () -> Void
    let showBuild: () -> Void
    @State private var files: [URL] = []
    @State private var index = 0
    @State private var message: String?
    @State private var picking: Field?
    @State private var showSettings = false
    @FocusState private var focused: Bool

    private var work: URL? { GameBuilder.workFolder(of: game) }
    /// Einstellungen gibt es für jedes nxnative-Spiel; Update und DLC nur, wo der Arbeitsordner des Spiels neben der App liegt.
    private var fields: [Field] { [.settings] + (work == nil ? [] : [.update, .dlc, .keys, .build] + files.map(Field.file)) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScreenHeader(symbol: "gearshape.fill", title: game.title, subtitle: work == nil ? "Einstellungen" : "Einstellungen, Update und DLC", message: message)
                list
                footer
            }
            .background(Theme.background)
            if let field = picking {
                FileBrowser(kind: field == .keys ? .file(["keys"]) : .file(GameBuilder.extensions), title: title(field), start: startDir(field), choose: { set(field, $0) }) { picking = nil }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if showSettings {
                GameSettingsView(game: game) { showSettings = false }.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 1280, height: 720)
        .animation(.easeOut(duration: 0.25), value: picking)
        .animation(.easeOut(duration: 0.25), value: showSettings)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { refresh(); focused = true }
        .onChange(of: picking) { _, field in if field == nil { focused = true } }
        .onChange(of: showSettings) { _, open in if !open { focused = true } }
        .onKeyPress(phases: [.down, .repeat]) { press in
            guard picking == nil, !showSettings else { return .ignored } // der Datei-Browser hat den Fokus; was er nicht braucht, geht nicht an diese Seite
            let down = press.phase == .down
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, fields.count - 1)
            case .rightArrow, .return, .space: if down { activate() }
            case .delete: if down { remove(fields[index]) }
            case .escape, .leftArrow: if down { close() }
            default:
                guard press.characters.lowercased() == "y" else { return .ignored }
                if down { remove(fields[index]) }
            }
            return .handled
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(fields.enumerated()), id: \.element) { i, field in
                        row(field, selected: i == index).id(field).onTapGesture { if i == index { activate() } else { index = i } }
                    }
                }
                .padding(.horizontal, 140)
                .padding(.vertical, 24)
            }
            .onChange(of: index) { _, i in
                if fields.indices.contains(i) { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(fields[i], anchor: .center) } }
            }
        }
    }

    private func row(_ field: Field, selected: Bool) -> some View {
        HStack(spacing: 22) {
            Text(label(field))
                .font(.system(size: 26, design: .rounded))
                .foregroundStyle(field == .build && builder.canRebuild ? Theme.cursor : Theme.text)
                .opacity(field == .build && !builder.canRebuild ? 0.4 : 1)
                .lineLimit(1)
            Spacer()
            Text(value(field))
                .font(.system(size: 20, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuRow(selected: selected)
    }

    private func label(_ field: Field) -> String {
        switch field {
        case .settings: "Einstellungen"
        case .update: "Update installieren …"
        case .dlc: "DLC installieren …"
        case .keys: "prod.keys"
        case .build: "Neu bauen"
        case .file(let url): url.lastPathComponent
        }
    }

    private func value(_ field: Field) -> String {
        switch field {
        case .settings: "Bildrate, Auflösung, Konsolenmodus …"
        case .update, .dlc: ""
        case .keys: builder.keys?.path ?? "nicht gewählt"
        case .build:
            if builder.running { "es läuft schon ein Build" }
            else if !builder.repoValid { "nxnative-Ordner unter „Spiel bauen“ prüfen" }
            else if builder.keys == nil { "erst prod.keys wählen" }
            else { "" }
        case .file(let url): FileManager.default.fileExists(atPath: url.path) ? "" : "Datei fehlt" // fehlt = verwaister Link
        }
    }

    private func title(_ field: Field) -> String {
        switch field {
        case .update: "Update wählen"
        case .dlc: "DLC wählen"
        default: "prod.keys wählen"
        }
    }

    /// Dort anfangen, wo schon eine Spieldatei liegt; prod.keys wie auf der Builder-Seite.
    private func startDir(_ field: Field) -> URL {
        if field == .keys { return builder.keysStart }
        return files.first.map { $0.resolvingSymlinksInPath().deletingLastPathComponent() } ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func refresh() {
        files = work.map(GameBuilder.installedFiles) ?? []
        index = min(index, fields.count - 1)
    }

    private func set(_ field: Field, _ url: URL) {
        if field == .keys { builder.keys = url; return }
        guard let work else { return }
        do {
            try GameBuilder.install(url, into: work)
            message = "\(url.deletingPathExtension().lastPathComponent) installiert – jetzt neu bauen"
        } catch { message = error.localizedDescription }
        refresh()
    }

    private func activate() {
        switch fields[index] {
        case .build:
            guard builder.canRebuild else { return }
            builder.rebuild(game) { library.add([$0]) }
            showBuild()
        case .file: break
        case .settings: showSettings = true
        case let field: picking = field
        }
    }

    /// Entfernt nur den Link im Arbeitsordner, nie die Datei selbst.
    private func remove(_ field: Field) {
        guard case .file(let url) = field, (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { return }
        try? FileManager.default.removeItem(at: url)
        message = "\(url.lastPathComponent) entfernt"
        refresh()
    }

    private var canRemove: Bool { if case .file = fields[index] { true } else { false } }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                Spacer()
                if canRemove { Hint(key: "Y", label: "Entfernen").onTapGesture { remove(fields[index]) } }
                Hint(key: "B", label: "Schließen").onTapGesture { close() }
                if !canRemove { Hint(key: "A", label: fields[index] == .build ? "Neu bauen" : "Wählen") }
            }
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 26)
    }
}
