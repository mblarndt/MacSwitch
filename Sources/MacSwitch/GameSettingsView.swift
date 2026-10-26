import SwiftUI

/// Einstellungen eines Spiels (Bildrate, Auflösung, Konsolenmodus …): Umgebungsvariablen für den nxnative-Host, die MacSwitch beim nächsten Start des Spiels mitgibt.
/// ← → ändern, A schaltet weiter, Y setzt eine Einstellung zurück. Gespeichert wird nur, was vom Standard abweicht.
struct GameSettingsView: View {
    @EnvironmentObject private var builder: GameBuilder
    let game: Game
    let close: () -> Void
    @State private var settings = [GameSetting]()
    @State private var profile = GameProfile()
    @State private var values = [String: String]()
    @State private var index = 0
    @FocusState private var focused: Bool

    private var key: String { game.url.lastPathComponent }
    private var rows: Int { settings.count + 1 } // die Einstellungen und „Alles zurücksetzen“

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(symbol: "slider.horizontal.3", title: game.title, subtitle: "Einstellungen · gelten ab dem nächsten Start des Spiels")
            list
            footer
        }
        .frame(width: 1280, height: 720)
        .background(Theme.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { load(); focused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            let down = press.phase == .down
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, rows - 1)
            case .leftArrow: change(-1)
            case .rightArrow: change(1)
            case .return, .space: if down { index == settings.count ? resetAll() : change(1, wrap: true) }
            case .delete: if down { reset(index) }
            case .escape: if down { close() }
            default:
                guard press.characters.lowercased() == "y" else { return .ignored }
                if down { reset(index) }
            }
            return .handled
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(settings.enumerated()), id: \.element.id) { i, s in
                        VStack(alignment: .leading, spacing: 8) {
                            if i == 0 || settings[i - 1].section != s.section {
                                Text(s.section).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(Theme.subtle).padding(.top, i == 0 ? 0 : 12)
                            }
                            row(s.label, value: valueText(s), changed: values[s.env] != nil, selected: i == index)
                                .onTapGesture { if i == index { change(1, wrap: true) } else { index = i } }
                        }
                        .id(s.env)
                    }
                    row("Alles zurücksetzen", value: values.isEmpty ? "" : "\(values.count) geändert", changed: false, selected: index == settings.count)
                        .id("reset")
                        .onTapGesture { if index == settings.count { resetAll() } else { index = settings.count } }
                }
                .padding(.horizontal, 140)
                .padding(.vertical, 24)
            }
            .onChange(of: index) { _, i in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(settings.indices.contains(i) ? settings[i].env : "reset", anchor: .center) } }
        }
    }

    private func row(_ label: String, value: String, changed: Bool, selected: Bool) -> some View {
        HStack(spacing: 22) {
            Text(label).font(.system(size: 26, design: .rounded)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            Text(value).font(.system(size: 22, design: .rounded)).foregroundStyle(changed ? Theme.cursor : Theme.subtle).lineLimit(1)
        }
        .menuRow(selected: selected)
    }

    private func valueText(_ s: GameSetting) -> String {
        let text = s.text(for: values[s.env] ?? GameSettings.defaultValue(s, profile))
        return text + (values[s.env] == nil && GameSettings.defaultValue(s, profile) != nil && text != "Standard" ? " (Standard)" : "")
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                if settings.indices.contains(index), !settings[index].note.isEmpty {
                    Text(settings[index].note).font(.system(size: 18, design: .rounded)).foregroundStyle(Theme.subtle).lineLimit(1)
                }
                Spacer()
                if index < settings.count { Hint(key: "Y", label: "Standard").onTapGesture { reset(index) } }
                Hint(key: "B", label: "Zurück").onTapGesture { close() }
                Hint(key: "A", label: index == settings.count ? "Zurücksetzen" : "Ändern")
            }
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 26)
    }

    private func load() {
        profile = GameProfile(game: game, repo: builder.repo)
        settings = GameSettings.available(for: profile)
        values = GameSettingsStore.values(for: key)
    }

    private func change(_ direction: Int, wrap: Bool = false) {
        guard settings.indices.contains(index) else { return }
        let s = settings[index], standard = GameSettings.defaultValue(s, profile)
        let next = s.stepped(from: values[s.env] ?? standard, by: direction, wrap: wrap)
        let stored: String? = next == standard ? nil : next // der Standard wird nicht gespeichert: er folgt künftigen Änderungen des Hosts
        GameSettingsStore.set(s.env, stored, for: key)
        values[s.env] = stored
    }

    private func reset(_ i: Int) {
        guard settings.indices.contains(i) else { return }
        GameSettingsStore.set(settings[i].env, nil, for: key)
        values[settings[i].env] = nil
    }

    private func resetAll() {
        GameSettingsStore.reset(for: key)
        values = [:]
    }
}
