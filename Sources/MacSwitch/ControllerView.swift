import SwiftUI

/// Controller (Dock): schaltet den iPhone-Host ein und zeigt, wer auf welchem Spielerplatz sitzt.
/// Die Spiele lesen die Plätze über den DSU-Server des Hosts (nxnative-Host: Spieler 1 bis 4 mit analogen Sticks).
struct ControllerView: View {
    @EnvironmentObject private var host: ControllerHost
    let close: () -> Void
    @State private var index = 0
    @FocusState private var focused: Bool

    private var rows: Int { 1 + ControllerHost.playerCount + 1 } // Schalter, Spieler, Spiele-Anbindung

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(symbol: "gamecontroller.fill", title: "Controller", subtitle: host.snapshot.status)
            list
            footer
        }
        .frame(width: 1280, height: 720)
        .background(Theme.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, rows - 1)
            case .rightArrow, .return, .space: if press.phase == .down { activate() }
            case .escape, .leftArrow: if press.phase == .down { close() }
            default: return .ignored
            }
            return .handled
        }
    }

    private var list: some View {
        VStack(spacing: 16) {
            ForEach(0..<rows, id: \.self) { i in
                row(label(i), value(i), selected: i == index).onTapGesture { if i == index { activate() } else { index = i } }
            }
            Spacer()
        }
        .padding(.horizontal, 140)
        .padding(.vertical, 24)
    }

    private func row(_ label: String, _ value: String, selected: Bool) -> some View {
        HStack(spacing: 22) {
            Text(label).font(.system(size: 26, design: .rounded)).foregroundStyle(Theme.text)
            Spacer()
            Text(value).font(.system(size: 20, design: .rounded)).foregroundStyle(Theme.subtle).lineLimit(1).truncationMode(.middle)
        }
        .menuRow(selected: selected)
    }

    private func label(_ i: Int) -> String {
        i == 0 ? "iPhone-Controller" : i <= ControllerHost.playerCount ? "Spieler \(i)" : "Anbindung für Spiele"
    }

    private func value(_ i: Int) -> String {
        if i == 0 { return host.enabled ? "An" : "Aus" }
        guard i <= ControllerHost.playerCount else { return host.snapshot.dsu }
        let p = host.snapshot.players[i - 1]
        guard let name = p.name else { return "frei" }
        return p.connected ? name + (p.latency.map { " · \($0) ms" } ?? "") : "\(name) (getrennt)"
    }

    private func activate() {
        if index == 0 { host.enabled.toggle() }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                Spacer()
                Hint(key: "B", label: "Schließen").onTapGesture { close() }
                if index == 0 { Hint(key: "A", label: host.enabled ? "Ausschalten" : "Einschalten") }
            }
        }
        .padding(.horizontal, 56)
        .padding(.bottom, 26)
    }
}
