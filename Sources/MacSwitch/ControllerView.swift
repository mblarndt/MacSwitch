import SwiftUI

/// Controller (Dock): schaltet den iPhone-Host ein und zeigt, wer auf welchem Spielerplatz sitzt.
/// Die Spiele lesen die Plätze über den DSU-Server des Hosts (nxnative-Host: Spieler 1 bis 4 mit analogen Sticks).
struct ControllerView: View {
    @EnvironmentObject private var host: ControllerHost
    @EnvironmentObject private var pads: PhysicalPads
    let close: () -> Void
    @State private var index = 0
    @State private var confirmOff: Date? // bis wann ein zweites A das Ausschalten bestätigt
    @FocusState private var focused: Bool

    private var rows: Int { 1 + ControllerHost.playerCount + 1 + max(pads.names.count, 1) } // Schalter, Spieler, Spiele-Anbindung, echte Controller

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
        .onChange(of: index) { _, _ in confirmOff = nil }
        .onKeyPress(phases: [.down, .repeat]) { press in
            switch press.key {
            case .upArrow: index = max(index - 1, 0)
            case .downArrow: index = min(index + 1, rows - 1)
            case .return, .space: if press.phase == .down { activate() } // nur A: ein Druck nach rechts darf den Host nicht ausschalten
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
        let n = ControllerHost.playerCount
        if i == 0 { return "iPhone-Controller" }
        if i <= n { return "Spieler \(i)" }
        if i == n + 1 { return "Anbindung für Spiele" }
        return pads.names.indices.contains(i - n - 2) ? pads.names[i - n - 2] : "Controller (Bluetooth oder Kabel)"
    }

    private func value(_ i: Int) -> String {
        if i == 0 { return confirmOff != nil ? "A noch einmal: das iPhone trennt sich" : host.enabled ? "An" : "Aus" }
        if i == ControllerHost.playerCount + 1 { return host.snapshot.dsu }
        if i > ControllerHost.playerCount + 1 { return pads.names.isEmpty ? "keiner verbunden" : "verbunden" }
        let p = host.snapshot.players[i - 1]
        guard let name = p.name else { return "frei" }
        return p.connected ? name + (p.latency.map { " · \($0) ms" } ?? "") : "\(name) (getrennt)"
    }

    /// Ein iPhone, das am Host hängt, steuert diese Seite selbst: Ausschalten trennt es und ließe es ohne Kontrolle. Darum braucht es dann ein zweites A.
    private func activate() {
        guard index == 0 else { return }
        if host.enabled, host.snapshot.players.contains(where: \.connected), confirmOff == nil {
            let until = Date().addingTimeInterval(3)
            confirmOff = until
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if confirmOff == until { confirmOff = nil } }
            return
        }
        confirmOff = nil
        host.enabled.toggle()
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
