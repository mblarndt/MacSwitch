import SwiftUI

/// Systemeinstellungen (Dock): Design, Spiele hinzufügen und der Stand von nxnative samt Update.
struct SettingsView: View {
    private enum Row: Hashable { case dark, addGame, folder, stand, update, repo }

    @EnvironmentObject private var builder: GameBuilder
    @EnvironmentObject private var updater: NxnativeUpdater
    @AppStorage("darkTheme") private var dark = false
    let close: () -> Void
    let addGame: () -> Void
    @State private var index = 0
    @State private var head: String? // Stand des nxnative-Ordners
    @State private var loaded = false

    private let sections: [(title: String, rows: [Row])] = [("MacSwitch", [.dark, .addGame, .folder]), ("nxnative", [.stand, .update, .repo])]
    private var rows: [Row] { sections.flatMap(\.rows) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(symbol: "slider.horizontal.3", title: "Systemeinstellungen", subtitle: "MacSwitch und nxnative")
            list
            footer
        }
        .frame(width: 1280, height: 720)
        .background(Theme.background)
        .focusable()
        .focusEffectDisabled()
        .onAppear { load() }
        .onChange(of: updater.state) { _, _ in load() }
        .pageKeys { press in
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, rows.count - 1)
            case .leftArrow, .rightArrow: if rows[index] == .dark && press.isDown { activate() }
            case .return, .space: if press.isDown { activate() }
            case .escape: if press.isDown { close() }
            default: return .ignored
            }
            return .handled
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections, id: \.title) { section in
                        Text(section.title).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(Theme.subtle)
                        ForEach(section.rows, id: \.self) { r in
                            let i = rows.firstIndex(of: r) ?? 0
                            row(r, selected: i == index).id(r).onTapGesture { if i == index { activate() } else { index = i } }
                        }
                    }
                }
                .padding(.horizontal, 140)
                .padding(.vertical, 24)
            }
            .onChange(of: index) { _, i in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(rows[i], anchor: .center) } }
        }
    }

    private func row(_ r: Row, selected: Bool) -> some View {
        HStack(spacing: 22) {
            Text(label(r)).font(.system(size: 26, design: .rounded)).foregroundStyle(Theme.text)
            Spacer()
            Text(value(r)).font(.system(size: 20, design: .rounded)).foregroundStyle(r == .update && updater.state.updatable ? Theme.cursor : Theme.subtle).lineLimit(1).truncationMode(.middle)
        }
        .menuRow(selected: selected)
    }

    private func label(_ r: Row) -> String {
        switch r {
        case .dark: "Dunkles Design"
        case .addGame: "Spiel hinzufügen …"
        case .folder: "Games-Ordner öffnen"
        case .stand: "Stand von nxnative"
        case .update: "nxnative aktualisieren"
        case .repo: "nxnative-Ordner"
        }
    }

    private func value(_ r: Row) -> String {
        switch r {
        case .dark: dark ? "An" : "Aus"
        case .addGame, .folder: ""
        case .stand: !loaded ? "liest …" : head ?? "kein Git-Ordner"
        case .update: updater.summary
        case .repo: builder.repo.path
        }
    }

    private var actionLabel: String {
        switch rows[index] {
        case .dark: "Umschalten"
        case .addGame: "Wählen"
        case .folder: "Öffnen"
        case .update: updater.state.updatable ? "Aktualisieren" : "Prüfen"
        case .stand, .repo: "–"
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                Spacer()
                Hint(key: "B", label: "Schließen").onTapGesture { close() }
                Hint(key: "A", label: actionLabel)
            }
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 26)
    }

    private func activate() {
        switch rows[index] {
        case .dark: dark.toggle()
        case .addGame: addGame()
        case .folder: NSWorkspace.shared.open(GameLibrary.folder)
        case .update:
            if updater.state.updatable { updater.update(repo: builder.repo) } else { updater.check(repo: builder.repo) }
        case .stand, .repo: break
        }
    }

    /// Stand lesen (Git, im Hintergrund); ein Update ändert ihn, darum auch dann neu.
    private func load() {
        let repo = builder.repo
        DispatchQueue.global().async {
            let h = NxnativeUpdater.localHead(repo: repo)
            DispatchQueue.main.async { head = h; loaded = true }
        }
        if case .idle = updater.state { updater.check(repo: repo) }
    }
}
