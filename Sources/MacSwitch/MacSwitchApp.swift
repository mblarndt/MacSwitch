import SwiftUI

@main
struct MacSwitchApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var session = GameSession()

    var body: some Scene {
        // Window statt WindowGroup: genau ein Fenster, kein ⌘N. Vollbild-Verhalten macht GameSession.home().
        Window("MacSwitch", id: "main") {
            HomeView()
                .environmentObject(library)
                .environmentObject(session)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
    }
}
