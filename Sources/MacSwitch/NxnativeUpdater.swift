import Foundation

/// Hält den nxnative-Ordner auf dem Stand des offiziellen Repositories: nxnative hat keine Releases, es kommen laufend Änderungen.
/// Prüft per `git fetch`, ob der Upstream-Zweig (`@{u}`, bei einem Fork der offizielle Zweig) neuer ist, und aktualisiert: ohne eigene Commits per `git pull --ff-only`, mit eigenen
/// per `git merge` (ein Konflikt macht den Merge rückgängig und bleibt gemeldet). Verändert wird nur, wenn das gefahrlos geht:
/// keine lokalen Änderungen an Dateien, die auch das Update ändert (sonst bleibt alles, wie es ist, und der Status sagt warum).
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
        let when = TimeInterval(git(["log", "-1", "--format=%ct", up.output], in: repo).output).map(age) ?? ""
        // Lokale Änderungen an Dateien, die das Update ebenfalls ändert, würden beim Einspielen kollidieren.
        func names(_ args: [String]) -> Set<String> { Set(git(args, in: repo).output.split(separator: "\n").map(String.init)) }
        let clash = names(["diff", "--name-only", "HEAD..\(up.output)"]).intersection(names(["diff", "--name-only", "HEAD"])).sorted()
        let blocker = clash.isEmpty ? nil : "lokale Änderungen an \(clash.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))\(clash.count > 3 ? " …" : ""): erst committen"
        return .behind(count: behind, when: when, blocker: blocker)
    }

    /// Spielt die neuen Commits ein: ohne eigene Commits als Vorspulen, mit eigenen als Merge. Lokale Änderungen an anderen Dateien bleiben erhalten (autostash).
    static func update(repo: URL) -> State {
        let ahead = Int(git(["rev-list", "--count", "@{u}..HEAD"], in: repo).output) ?? 0
        if ahead == 0 {
            let pull = git(["pull", "--ff-only", "--autostash", "--quiet"], in: repo, timeout: 180)
            guard pull.status == 0 else { return .failed(pull.output.split(separator: "\n").last.map(String.init) ?? "Update fehlgeschlagen") }
            return .updated
        }
        // Eigene Commits: Upstream einmergen. Ohne eingerichteten Git-Namen bekommt der Merge-Commit einen Ersatz.
        let identity = git(["config", "user.name"], in: repo).status == 0 ? [] : ["-c", "user.name=MacSwitch", "-c", "user.email=macswitch@localhost"]
        let merge = git(identity + ["merge", "--no-edit", "--autostash", "--quiet", "@{u}"], in: repo, timeout: 180)
        guard merge.status != 0 else { return .updated }
        let conflicts = git(["diff", "--name-only", "--diff-filter=U"], in: repo).output.split(separator: "\n").map { ($0 as NSString).lastPathComponent }
        _ = git(["merge", "--abort"], in: repo) // zurück auf den Stand davor
        if conflicts.isEmpty { return .failed(merge.output.split(separator: "\n").last.map(String.init) ?? "Merge fehlgeschlagen") }
        return .failed("Konflikte in \(conflicts.prefix(3).joined(separator: ", ")): im Terminal zusammenführen")
    }

    /// "vor 25 Minuten" aus einem Unix-Zeitstempel (Git liefert ihn sprachunabhängig).
    static func age(_ timestamp: TimeInterval) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .full
        return f.localizedString(for: Date(timeIntervalSince1970: timestamp), relativeTo: Date())
    }

    /// Der Stand des Ordners: kurzer Commit-Hash, Datum und wie lange das her ist, etwa "d62ddbb · 25.10.2026 (vor 2 Stunden)". nil ohne Git-Ordner.
    static func localHead(repo: URL) -> String? {
        let r = git(["log", "-1", "--format=%h|%ct"], in: repo, timeout: 10)
        let c = r.output.split(separator: "|").map(String.init)
        guard r.status == 0, c.count == 2, let ts = TimeInterval(c[1]) else { return nil }
        let day = DateFormatter()
        day.dateFormat = "dd.MM.yyyy"
        return "\(c[0]) · \(day.string(from: Date(timeIntervalSince1970: ts))) (\(age(ts)))"
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
