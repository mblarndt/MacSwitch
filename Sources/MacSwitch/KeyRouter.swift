import SwiftUI

/// Eine Taste für die Menüs: von der Tastatur (über den Fokus) oder vom iPhone und von Controllern (direkt, ohne Fokus).
struct PageKey {
    let key: KeyEquivalent
    let characters: String
    let isDown: Bool // false: Wiederholung einer gehaltenen Taste

    init(key: KeyEquivalent, characters: String = "", isDown: Bool = true) {
        self.key = key
        self.characters = characters
        self.isDown = isDown
    }

    init(_ press: KeyPress) { self.init(key: press.key, characters: press.characters, isDown: press.phase == .down) }
}

/// Verteilt Tasten an die oberste Seite (Optionen, Einstellungen, Datei-Browser …). Der Tastaturfokus von SwiftUI wandert zwischen Seiten nicht verlässlich und geht beim Schließen einer Seite
/// verloren; Controller und iPhone rufen darum den Verteiler direkt auf, und die HomeView reicht ihm auch die Tasten weiter, die bei ihr statt bei der Seite landen.
final class KeyRouter {
    static let shared = KeyRouter()
    private var handlers = [(id: UUID, action: (PageKey) -> KeyPress.Result)]()

    func push(_ id: UUID, _ action: @escaping (PageKey) -> KeyPress.Result) { handlers.removeAll { $0.id == id }; handlers.append((id, action)) }
    func pop(_ id: UUID) { handlers.removeAll { $0.id == id } }
    func route(_ key: PageKey) -> KeyPress.Result { handlers.last?.action(key) ?? .ignored }
}

private struct PageKeys: ViewModifier {
    let action: (PageKey) -> KeyPress.Result
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: [.down, .repeat]) { action(PageKey($0)) } // hat die Seite den Fokus, bekommt sie die Tasten der Tastatur selbst
            .onAppear { KeyRouter.shared.push(id, action) }
            .onDisappear { KeyRouter.shared.pop(id) }
    }
}

extension View {
    /// Tasten einer Seite: von der Tastatur über den Fokus oder über den KeyRouter, von iPhone und Controllern immer über ihn.
    func pageKeys(_ action: @escaping (PageKey) -> KeyPress.Result) -> some View { modifier(PageKeys(action: action)) }
}
