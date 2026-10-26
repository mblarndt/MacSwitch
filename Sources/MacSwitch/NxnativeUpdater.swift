import Foundation

/// Hält den nxnative-Ordner auf dem Stand des offiziellen Repositories: nxnative hat keine Releases, es kommen laufend Änderungen.
/// Prüft per `git fetch`, ob der Upstream-Zweig neuer ist, und aktualisiert per `git pull --ff-only`. Verändert wird nur, wenn das gefahrlos geht:
/// keine eigenen Commits und keine lokalen Änderungen an Dateien, die auch das Update ändert (sonst bleibt alles, wie es ist, und der Status sagt warum).
/// Gebaute Spiele übernehmen Änderungen erst mit „Neu bauen“.
final class NxnativeUpdater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case current
        /// `count` neue Änderungen, die zuletzt `when`; `blocker`: warum ein Update nicht gefahrlos ginge.
        case behind(count: Int, when: String, blocker: String?)
        case updating
        case updated
        case failed(String)

        var updatable: Bool { if case .behind(_, _, nil) = self { true } else { false } }
    }

    @Published private(set) var state = State.idle
    private let queue = DispatchQueue(label: "MacSwitch.NxnativeUpdater", qos: .utility)

    /// Prüft im Hintergrund; läuft schon eine Prüfung oder ein Update, passiert nichts.
    func check(repo: URL) { run(.checking) { Self.check(repo: repo) } }

    func update(repo: URL) {
        guard state.updatable else { return }
        run(.updating) { Self.update(repo: repo) }
    }

    private func run(_ start: State, _ work: @escaping () -> State) {
        guard state != .checking, state != .updating else { return }
        state = start
        queue.async {
            let result = work()
            DispatchQueue.main.async { self.state = result }
        }
    }

    // MARK: Git

    /// Führt git aus; (Status, Ausgabe). Ohne Rückfrage nach Zugangsdaten, mit Zeitlimit.
    static func git(_ args: [String], in repo: URL, timeout: TimeInterval = 60) -> (status: Int32, output: String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path] + args
        p.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true", "LC_ALL": "C"]) { $1 }
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let killer = DispatchWorkItem { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func check(repo: URL) -> State {
        guard FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git").path) else { return .failed("kein Git-Ordner") }
        let fetch = git(["fetch", "--quiet"], in: repo, timeout: 30)
        guard fetch.status == 0 else { return .failed("nicht erreichbar") }
        let up = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: repo)
        guard up.status == 0 else { return .failed("Zweig ohne Upstream") }
        guard let behind = Int(git(["rev-list", "--count", "HEAD..\(up.output)"], in: repo).output) else { return .failed("Vergleich fehlgeschlagen") }
        if behind == 0 { return .current }
        let when = git(["log", "-1", "--format=%cr", up.output], in: repo).output
        let ahead = Int(git(["rev-list", "--count", "\(up.output)..HEAD"], in: repo).output) ?? 0
        if ahead > 0 { return .behind(count: behind, when: when, blocker: "\(ahead) eigene Commits: im Terminal aktualisieren") }
        // Lokale Änderungen an Dateien, die das Update ebenfalls ändert, würden beim Einspielen kollidieren.
        func names(_ args: [String]) -> Set<String> { Set(git(args, in: repo).output.split(separator: "\n").map(String.init)) }
        let clash = names(["diff", "--name-only", "HEAD..\(up.output)"]).intersection(names(["diff", "--name-only", "HEAD"])).sorted()
        let blocker = clash.isEmpty ? nil : "lokale Änderungen an \(clash.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))\(clash.count > 3 ? " …" : ""): erst committen"
        return .behind(count: behind, when: when, blocker: blocker)
    }

    /// Spielt die neuen Commits ein. Lokale Änderungen an anderen Dateien bleiben (autostash).
    static func update(repo: URL) -> State {
        let pull = git(["pull", "--ff-only", "--autostash", "--quiet"], in: repo, timeout: 180)
        guard pull.status == 0 else { return .failed(pull.output.split(separator: "\n").last.map(String.init) ?? "Update fehlgeschlagen") }
        return .updated
    }

    /// Text für die Anzeige.
    var summary: String {
        switch state {
        case .idle: "nicht geprüft"
        case .checking: "prüft …"
        case .current: "aktuell"
        case .behind(let count, let when, let blocker): "\(count) neue Änderung\(count == 1 ? "" : "en"), zuletzt \(when)" + (blocker.map { " – \($0)" } ?? "")
        case .updating: "aktualisiert …"
        case .updated: "aktualisiert – Spiele mit „Neu bauen“ übernehmen die Änderungen"
        case .failed(let message): message
        }
    }
}
