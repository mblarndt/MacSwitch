import SwiftUI

/// Spiel bauen: Dateien und Ordner wählt man wie beim Hinzufügen im Switch-Datei-Browser, dann baut nxnative daraus eine Mac-App fürs Menü.
/// Der Lauf gehört dem GameBuilder und geht weiter, wenn man diese Seite schließt.
struct BuilderView: View {
    private enum Field: Hashable {
        case repo, nxUpdate, rom, recipe, update, dlc(URL), addDlc, keys, out, start
    }

    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var builder: GameBuilder
    @EnvironmentObject private var updater: NxnativeUpdater
    let close: () -> Void
    @State private var index = 0
    @State private var picking: Field?
    @State private var recipe: Recipe.Result? // ob nxnative für das gewählte Hauptspiel ein Rezept (Spielprofil) hat
    @FocusState private var focused: Bool

    private var fields: [Field] { [.repo, .nxUpdate, .rom] + (recipe == nil ? [] : [.recipe]) + [.update] + builder.dlcs.map(Field.dlc) + [.addDlc, .keys, .out, .start] }
    private var showsRun: Bool { !builder.status.isEmpty }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScreenHeader(symbol: "hammer.fill", title: "Spiel bauen", subtitle: "nxnative · Mac-App aus NSP/XCI und prod.keys")
                if showsRun { run } else { list }
                footer
            }
            .background(Theme.background)
            if let field = picking {
                FileBrowser(kind: kind(field), title: title(field), start: startDir(field), choose: { set(field, $0) }) { picking = nil }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 1280, height: 720)
        .animation(.easeOut(duration: 0.25), value: picking)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true; refreshRecipe() }
        .onChange(of: updater.state) { _, _ in refreshRecipe() }
        .onChange(of: picking) { _, field in if field == nil { focused = true } }
        .onKeyPress(phases: [.down, .repeat]) { press in
            guard picking == nil else { return .ignored } // der Datei-Browser hat den Fokus; was er nicht braucht, geht nicht an diese Seite
            let down = press.phase == .down
            let char = press.characters.lowercased()
            if showsRun {
                switch press.key {
                case .return, .space: if down && !builder.running { builder.reset() }
                case .escape, .leftArrow: if down { close() }
                default:
                    guard char == "x" else { return .ignored }
                    if down { builder.cancel() }
                }
                return .handled
            }
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, fields.count - 1)
            case .rightArrow, .return, .space: if down { activate() }
            case .delete: if down { remove(fields[index]) }
            case .escape, .leftArrow: if down { close() }
            default:
                guard char == "y" else { return .ignored }
                if down { remove(fields[index]) }
            }
            return .handled
        }
    }

    // MARK: Auswahl

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
                .foregroundStyle(field == .start && builder.ready ? Theme.cursor : Theme.text)
                .opacity(field == .start && !builder.ready ? 0.4 : 1)
            Spacer()
            Text(value(field))
                .font(.system(size: 20, design: .rounded))
                .foregroundStyle(field == .recipe ? (recipe?.good == true ? Theme.cursor : .orange) : Theme.subtle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuRow(selected: selected)
    }

    private func label(_ field: Field) -> String {
        switch field {
        case .repo: "nxnative-Ordner"
        case .nxUpdate: "nxnative aktualisieren"
        case .rom: "Hauptspiel"
        case .recipe: "Rezept"
        case .update: "Update (optional)"
        case .dlc: "DLC"
        case .addDlc: "DLC hinzufügen …"
        case .keys: "prod.keys"
        case .out: "Ausgabeordner"
        case .start: "Mac-App bauen"
        }
    }

    private func value(_ field: Field) -> String {
        let none = "nicht gewählt"
        switch field {
        case .repo: return builder.repo.path + (builder.repoValid ? "" : " – Skripte nicht gefunden")
        case .rom: return builder.rom?.lastPathComponent ?? none
        case .update: return builder.update?.lastPathComponent ?? none
        case .dlc(let url): return url.lastPathComponent
        case .keys: return builder.keys?.path ?? none
        case .out: return builder.out?.path ?? none
        case .nxUpdate: return updater.summary
        case .recipe: return recipe?.text ?? ""
        case .addDlc, .start: return ""
        }
    }

    private func kind(_ field: Field) -> FileBrowser.Kind {
        switch field {
        case .repo, .out: .folder
        case .keys: .file(["keys"])
        default: .file(GameBuilder.extensions)
        }
    }

    private func title(_ field: Field) -> String {
        field == .addDlc ? "DLC wählen" : label(field).replacingOccurrences(of: " (optional)", with: "") + " wählen"
    }

    /// Dort anfangen, wo man gerade ist: prod.keys liegen meist in ~/.switch, alles andere beim Hauptspiel.
    private func startDir(_ field: Field) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch field {
        case .repo: return home
        case .keys: return builder.keysStart
        default: return builder.rom?.deletingLastPathComponent() ?? home
        }
    }

    private func set(_ field: Field, _ url: URL) {
        switch field {
        case .repo: builder.repo = url; refreshRecipe()
        case .rom: builder.rom = url; refreshRecipe()
        case .update: builder.update = url
        case .addDlc: if !builder.dlcs.contains(url) { builder.dlcs.append(url) }
        case .keys: builder.keys = url
        case .out: builder.out = url
        case .dlc, .start, .nxUpdate, .recipe: break
        }
    }

    private func refreshRecipe() { recipe = builder.rom.map { Recipe.lookup(rom: $0, repo: builder.repo) } }

    private func activate() {
        switch fields[index] {
        case .start: if builder.ready { builder.start { library.add([$0]) } }
        case .recipe: break
        case .nxUpdate: if updater.state.updatable { updater.update(repo: builder.repo) } else { updater.check(repo: builder.repo) }
        case .dlc(let url): remove(.dlc(url))
        case let field: picking = field
        }
    }

    private func remove(_ field: Field) {
        switch field {
        case .update: builder.update = nil
        case .dlc(let url): builder.dlcs.removeAll { $0 == url }
        default: return
        }
        index = min(index, fields.count - 1)
    }

    private var canRemove: Bool {
        switch fields[index] {
        case .update: builder.update != nil
        case .dlc: true
        default: false
        }
    }

    // MARK: Lauf

    private var run: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(builder.status).font(.system(size: 30, weight: .medium, design: .rounded)).foregroundStyle(Theme.text)
            ProgressView(value: builder.overall).tint(Theme.cursor)
            Text(builder.detail).font(.system(size: 20, design: .rounded)).foregroundStyle(Theme.subtle)
            if !builder.error.isEmpty {
                Text(builder.error).font(.system(size: 20, design: .rounded)).foregroundStyle(.red).lineLimit(4)
            }
            Spacer()
            Text(builder.log.suffix(6).joined(separator: "\n"))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.subtle)
                .lineLimit(6)
        }
        .padding(.horizontal, 140)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Fußzeile

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                Spacer()
                if showsRun {
                    if builder.running { Hint(key: "X", label: "Abbrechen").onTapGesture { builder.cancel() } }
                    Hint(key: "B", label: builder.running ? "Im Hintergrund" : "Schließen").onTapGesture { close() }
                    if !builder.running { Hint(key: "A", label: "Zurück").onTapGesture { builder.reset() } }
                } else {
                    if canRemove { Hint(key: "Y", label: "Entfernen").onTapGesture { remove(fields[index]) } }
                    Hint(key: "B", label: "Schließen").onTapGesture { close() }
                    Hint(key: "A", label: actionLabel)
                }
            }
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 26)
    }

    private var actionLabel: String {
        switch fields[index] {
        case .start: "Bauen"
        case .nxUpdate: updater.state.updatable ? "Aktualisieren" : "Prüfen"
        case .recipe: "Info"
        case .dlc: "Entfernen"
        default: "Wählen"
        }
    }
}
