import SwiftUI

@main
struct MacSwitchApp: App {
    @StateObject private var library = GameLibrary()
    @StateObject private var session = GameSession()
    @StateObject private var builder = GameBuilder()
    @StateObject private var controllers = ControllerHost()
    @StateObject private var pads = PhysicalPads()
    @StateObject private var updater = NxnativeUpdater()

    var body: some Scene {
        // Window statt WindowGroup: genau ein Fenster, kein ⌘N. Vollbild-Verhalten macht GameSession.home().
        Window("MacSwitch", id: "main") {
            HomeView()
                .environmentObject(library)
                .environmentObject(session)
                .environmentObject(builder)
                .environmentObject(controllers)
                .environmentObject(pads)
                .environmentObject(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
    }
}
