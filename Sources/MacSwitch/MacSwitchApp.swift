import SwiftUI

@main
struct MacSwitchApp: App {
    @StateObject private var library = GameLibrary()

    var body: some Scene {
        // Window statt WindowGroup: genau ein Fenster, kein ⌘N.
        Window("MacSwitch", id: "main") {
            HomeView()
                .environmentObject(library)
                .frame(minWidth: 640, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
    }
}
