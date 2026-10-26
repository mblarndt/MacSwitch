import SwiftUI

// MARK: - Theme (Switch "Basic White" / "Basic Black")

private func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    func ns(_ h: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
    }
    return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light) })
}

enum Theme {
    static let background = LinearGradient(colors: [dyn(0xEBEBEB, 0x303030), dyn(0xE2E2E2, 0x252525)], startPoint: .top, endPoint: .bottom)
    static let text = dyn(0x2D2D2D, 0xFFFFFF)
    static let subtle = dyn(0x6E6E6E, 0xB4B4B4)
    static let dock = dyn(0xFFFFFF, 0x4B4B4B)
    static let line = dyn(0xBDBDBD, 0x5E5E5E)
    static let cursor = Color(red: 0.04, green: 0.74, blue: 0.90)
    static let cursorBright = Color(red: 0.35, green: 0.95, blue: 1.0)
}

private enum DockItem: CaseIterable {
    case news, eshop, album, controllers, settings, power

    var title: String {
        switch self {
        case .news: "Neuigkeiten"
        case .eshop: "Nintendo eShop"
        case .album: "Album"
        case .controllers: "Controller"
        case .settings: "Systemeinstellungen"
        case .power: "Beenden"
        }
    }

    var symbol: String {
        switch self {
        case .news: "newspaper.fill"
        case .eshop: "bag.fill"
        case .album: "photo.fill"
        case .controllers: "gamecontroller.fill"
        case .settings: "slider.horizontal.3"
        case .power: "power"
        }
    }

    var tint: Color {
        switch self {
        case .news: Color(red: 0.93, green: 0.27, blue: 0.20)
        case .eshop: Color(red: 0.98, green: 0.52, blue: 0.10)
        case .album: Color(red: 0.93, green: 0.35, blue: 0.55)
        case .controllers: Color(red: 0.25, green: 0.60, blue: 0.85)
        case .settings, .power: Color(red: 0.45, green: 0.45, blue: 0.48)
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var library: GameLibrary
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var builder: GameBuilder
    @EnvironmentObject private var updater: NxnativeUpdater
    @EnvironmentObject private var controllers: ControllerHost
    @EnvironmentObject private var pads: PhysicalPads
    @AppStorage("darkTheme") private var dark = false
    @State private var onDock = false
    @State private var gameIndex = 0 // hinter den Spielen: Kachel "Apps hinzufügen", dann "Spiel bauen"
    @State private var dockIndex = 0
    @State private var showSettings = false
    @State private var showBrowser = false
    @State private var showBuilder = false
    @State private var showControllers = false
    @State private var optionsGame: Game?
    @FocusState private var focused: Bool

    /// Welche Seiten über dem Menü liegen (Bits); 0 = keine. Für Animation, Fokus und gesperrte Menü-Eingaben.
    private var pages: Int { (showBrowser ? 1 : 0) | (showBuilder ? 2 : 0) | (showControllers ? 4 : 0) | (optionsGame == nil ? 0 : 8) | (showSettings ? 16 : 0) }

    private var selectedGame: Game? { !onDock && library.games.indices.contains(gameIndex) ? library.games[gameIndex] : nil }
    /// Einstellungen (und Updates und DLC) gibt es nur für Spiele, die mit nxnative gebaut wurden.
    private var hasOptions: Bool { selectedGame.map(GameBuilder.isNxnative) ?? false }

    var body: some View {
        // Feste 1280×720-Bühne, die ins Fenster skaliert wird: Proportionen bleiben bei jeder Größe wie auf der Konsole.
        GeometryReader { geo in
            ZStack {
                stage
                overlays
            }
            .frame(width: 1280, height: 720)
            .scaleEffect(min(geo.size.width / 1280, geo.size.height / 720))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeOut(duration: 0.25), value: pages)
        .background(Theme.background.ignoresSafeArea())
        .background(WindowAccessor { session.attach($0) })
        .overlay {
            if let game = session.game { LaunchScreen(game: game, spinning: session.isLaunching).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.35), value: session.game?.id)
        .preferredColorScheme(dark ? .dark : .light)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true; controllers.onMenu = deliver; pads.onMenu = deliver; updater.check(repo: builder.repo) }
        .onChange(of: pages) { _, open in if open == 0 { focused = true } }
        .onChange(of: library.games.count) { _, n in gameIndex = min(gameIndex, n + 1) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in library.reload() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { library.add([url]) } }
                }
            }
            return true
        }
        .onKeyPress(phases: [.down, .repeat]) { handle(PageKey($0)) }
    }

    /// Menü-Tasten vom iPhone und von Controllern: direkt in die Menüs, wenn MacSwitch vorn ist (nicht über Tastenereignisse und Fokus); Home holt MacSwitch nach vorn, auch aus einem laufenden Spiel.
    private func deliver(_ key: MenuPad.Key, isRepeat: Bool) {
        if key == .home { return session.home() }
        guard NSApp.isActive else { return }
        _ = handle(key.pageKey(isRepeat: isRepeat))
    }

    private func handle(_ press: PageKey) -> KeyPress.Result {
        guard session.game == nil else { return .handled } // während Start und Spiel keine Menü-Eingaben
        guard pages == 0 else { return KeyRouter.shared.route(press) } // mit einer Seite darüber gehören die Tasten ihr
        switch press.key {
        case .leftArrow: move(dx: -1)
        case .rightArrow: move(dx: 1)
        case .upArrow: onDock = false
        case .downArrow: onDock = true
        case .return, .space: if press.isDown { activate() }
        default:
            guard press.characters == "+" else { return .ignored }
            if press.isDown { openOptions() }
        }
        return .handled
    }

    @ViewBuilder private var overlays: some View {
        if showBrowser {
            FileBrowser { showBrowser = false }.transition(.move(edge: .trailing).combined(with: .opacity))
        }
        if showBuilder {
            BuilderView { showBuilder = false }.transition(.move(edge: .trailing).combined(with: .opacity))
        }
        if showSettings {
            SettingsView(close: { showSettings = false }, addGame: { showSettings = false; showBrowser = true }).transition(.move(edge: .trailing).combined(with: .opacity))
        }
        if showControllers {
            ControllerView { showControllers = false }.transition(.move(edge: .trailing).combined(with: .opacity))
        }
        if let game = optionsGame {
            GameOptionsView(game: game, close: { optionsGame = nil }, showBuild: { optionsGame = nil; showBuilder = true })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            topBar.padding(.top, 34).padding(.horizontal, 56)
            gameRow.padding(.top, 24)
            Spacer()
            dock
            Spacer()
            footer.padding(.horizontal, 56).padding(.bottom, 26)
        }
    }

    /// Hinweis, wenn das offizielle nxnative-Repository Neues hat (Prüfung beim Start); ein Klick öffnet „Spiel bauen“, wo man aktualisiert.
    @ViewBuilder private var updateBadge: some View {
        switch updater.state {
        case .behind(let count, _, _): badge("nxnative: \(count) neue Änderung\(count == 1 ? "" : "en")")
        case .updated: badge("nxnative aktualisiert – Spiele neu bauen")
        default: EmptyView()
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.cursor)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Theme.dock))
            .onTapGesture { showBuilder = true }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.80, blue: 0.95), Color(red: 0.30, green: 0.55, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(.white))
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            updateBadge
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
            }
            Image(systemName: "wifi").font(.system(size: 22))
            Image(systemName: "battery.100").font(.system(size: 24))
        }
        .foregroundStyle(Theme.text)
        .frame(height: 56)
    }

    private var gameRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let n = library.games.count
                    ForEach(Array(library.games.enumerated()), id: \.element.id) { i, game in
                        GameTile(game: game, selected: !onDock && i == gameIndex)
                            .id(game.id)
                            .onTapGesture { tapGame(i) }
                    }
                    GameTile(game: nil, selected: !onDock && gameIndex == n)
                        .id("add")
                        .onTapGesture { tapGame(n) }
                    GameTile(game: nil, label: builder.running ? "Baut … \(Int(builder.overall * 100)) %" : "Spiel bauen", symbol: "hammer", selected: !onDock && gameIndex == n + 1)
                        .id("build")
                        .onTapGesture { tapGame(n + 1) }
                }
                .padding(.horizontal, 92)
                .padding(.vertical, 24) // Platz für Cursor-Glow, den die ScrollView sonst abschneidet
            }
            .frame(height: 340)
            .onChange(of: gameIndex) { _, i in
                let games = library.games
                let id = games.indices.contains(i) ? games[i].id : (i == games.count ? "add" : "build")
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var dock: some View {
        HStack(spacing: 52) {
            ForEach(Array(DockItem.allCases.enumerated()), id: \.offset) { i, item in
                DockButton(item: item, selected: onDock && i == dockIndex)
                    .onTapGesture { tapDock(i) }
            }
        }
        .frame(height: 130)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 36) {
                Spacer()
                if hasOptions { Hint(key: "+", label: "Optionen").onTapGesture { openOptions() } }
                Hint(key: "A", label: onDock ? "OK" : selectedGame == nil ? "Öffnen" : "Starten")
            }
        }
    }

    // MARK: Aktionen

    private func move(dx: Int) {
        if onDock {
            dockIndex = min(max(dockIndex + dx, 0), DockItem.allCases.count - 1)
        } else {
            gameIndex = min(max(gameIndex + dx, 0), library.games.count + 1)
        }
    }

    private func openOptions() {
        if hasOptions { optionsGame = selectedGame }
    }

    private func tapGame(_ i: Int) {
        if !onDock && i == gameIndex { activate() } else { onDock = false; gameIndex = i }
    }

    private func tapDock(_ i: Int) {
        if onDock && i == dockIndex { activate() } else { onDock = true; dockIndex = i }
    }

    private func activate() {
        if onDock {
            switch DockItem.allCases[dockIndex] {
            case .settings: showSettings = true
            case .controllers: showControllers = true
            case .power: NSApp.terminate(nil)
            default: break // shortcut: News/eShop/Album sind nur Optik
            }
        } else if gameIndex == library.games.count {
            showBrowser = true
        } else if gameIndex > library.games.count {
            showBuilder = true
        } else {
            let game = library.games[gameIndex]
            session.start(game, environment: GameSettingsStore.values(for: game.url.lastPathComponent))
        }
    }
}

// MARK: - Bausteine

/// Der pulsierende Cursor um die Auswahl.
struct Cursor<S: InsettableShape>: View {
    let shape: S
    @State private var bright = false

    var body: some View {
        shape
            .strokeBorder(bright ? Theme.cursorBright : Theme.cursor, lineWidth: 6)
            .padding(-6)
            .shadow(color: Theme.cursor.opacity(0.6), radius: 10)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bright = true } }
    }
}

/// Button-Hinweis in der Fußzeile, z. B. ⓐ Starten.
struct Hint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.subtle, lineWidth: 2))
            Text(label).font(.system(size: 20, design: .rounded))
        }
        .foregroundStyle(Theme.subtle)
        .contentShape(Rectangle())
    }
}

/// `game == nil` ist eine Aktionskachel (Standard: "Apps hinzufügen") mit eigenem Symbol und Titel.
private struct GameTile: View {
    let game: Game?
    var label = "Apps hinzufügen"
    var symbol = "plus"
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            art
                .frame(width: 256, height: 256)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .overlay { if selected { Cursor(shape: RoundedRectangle(cornerRadius: 12)) } }
            Text(game?.title ?? label)
                .font(.system(size: 20, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .lineLimit(1)
                .frame(width: 256, alignment: .leading)
                .opacity(selected ? 1 : 0)
        }
    }

    @ViewBuilder private var art: some View {
        if let game {
            ZStack {
                // Unscharfe, vergrößerte Kopie füllt die abgerundeten Squircle-Ecken des Icons.
                Image(nsImage: game.icon).resizable().scaledToFill().scaleEffect(1.3).blur(radius: 30)
                Image(nsImage: game.icon).resizable().scaledToFill()
            }
        } else {
            ZStack {
                Theme.dock
                Image(systemName: symbol).font(.system(size: 64, weight: .light)).foregroundStyle(Theme.subtle)
            }
        }
    }
}

private struct DockButton: View {
    let item: DockItem
    let selected: Bool

    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Theme.dock)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                .frame(width: 88, height: 88)
                .overlay(Image(systemName: item.symbol).font(.system(size: 34)).foregroundStyle(item.tint))
                .overlay { if selected { Cursor(shape: Circle()) } }
                .scaleEffect(selected ? 1.12 : 1)
                .animation(.easeOut(duration: 0.15), value: selected)
            Text(item.title)
                .font(.system(size: 18, design: .rounded))
                .foregroundStyle(Theme.subtle)
                .fixedSize()
                .opacity(selected ? 1 : 0)
                .frame(width: 88) // Label ragt zentriert über die Kachelbreite hinaus, ohne den Abstand zu ändern
        }
    }
}

/// Schwarzer Hintergrund, solange die Mac-App startet bzw. läuft. Läuft die App, liegt dieses Fenster hinter ihrem eigenen.
private struct LaunchScreen: View {
    let game: Game
    let spinning: Bool

    var body: some View {
        VStack(spacing: 40) {
            Image(nsImage: game.icon).resizable().scaledToFit().frame(width: 220, height: 220)
            Group {
                if spinning {
                    ProgressView().controlSize(.large).environment(\.colorScheme, .dark)
                } else {
                    Text(game.title).font(.system(size: 22, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
