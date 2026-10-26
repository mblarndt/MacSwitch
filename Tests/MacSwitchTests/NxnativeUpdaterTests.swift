import XCTest
@testable import MacSwitch

/// Prüfen und Aktualisieren gegen echte, lokale Git-Repositories (ein "Origin" und ein Klon).
final class NxnativeUpdaterTests: XCTestCase {
    private func git(_ repo: URL, _ args: String...) {
        let r = NxnativeUpdater.git(["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + args, in: repo)
        XCTAssertEqual(r.status, 0, "git \(args.joined(separator: " ")): \(r.output)")
    }

    private func write(_ repo: URL, _ file: String, _ text: String) throws { try text.write(to: repo.appendingPathComponent(file), atomically: true, encoding: .utf8) }
    private func read(_ repo: URL, _ file: String) throws -> String { try String(contentsOf: repo.appendingPathComponent(file), encoding: .utf8) }

    private func setup() throws -> (origin: URL, clone: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let origin = tmp.appendingPathComponent("origin"), clone = tmp.appendingPathComponent("clone")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        git(origin, "init", "-q", "-b", "main")
        try write(origin, "a.txt", "a1"); try write(origin, "b.txt", "b1")
        git(origin, "add", "."); git(origin, "commit", "-q", "-m", "eins")
        let r = NxnativeUpdater.git(["clone", "-q", origin.path, clone.path], in: tmp)
        XCTAssertEqual(r.status, 0, r.output)
        git(clone, "config", "user.name", "t"); git(clone, "config", "user.email", "t@t")
        return (origin, clone)
    }

    func testCheckSeesNewCommitsAndUpdateKeepsUnrelatedLocalChanges() throws {
        let (origin, clone) = try setup()
        XCTAssertEqual(NxnativeUpdater.check(repo: clone), .current)

        try write(origin, "a.txt", "a2"); git(origin, "commit", "-q", "-am", "zwei")
        try write(origin, "a.txt", "a3"); git(origin, "commit", "-q", "-am", "drei")
        try write(clone, "b.txt", "lokal") // eine Änderung an einer Datei, die das Update nicht anfasst

        guard case .behind(let count, _, let blocker) = NxnativeUpdater.check(repo: clone) else { return XCTFail("müsste zurückliegen") }
        XCTAssertEqual(count, 2)
        XCTAssertNil(blocker, "andere Datei: kein Hindernis")

        XCTAssertEqual(NxnativeUpdater.update(repo: clone), .updated)
        XCTAssertEqual(try read(clone, "a.txt"), "a3")
        XCTAssertEqual(try read(clone, "b.txt"), "lokal", "die lokale Änderung bleibt")
        XCTAssertEqual(NxnativeUpdater.check(repo: clone), .current)
    }

    func testLocalChangeToAFileTheUpdateTouchesBlocks() throws {
        let (origin, clone) = try setup()
        try write(origin, "a.txt", "a2"); git(origin, "commit", "-q", "-am", "zwei")
        try write(clone, "a.txt", "meine Fassung")
        guard case .behind(_, _, let blocker) = NxnativeUpdater.check(repo: clone) else { return XCTFail() }
        XCTAssertTrue(blocker?.contains("a.txt") == true, blocker ?? "kein Hindernis")
        XCTAssertFalse(NxnativeUpdater.State.behind(count: 1, when: "", blocker: blocker).updatable)
        XCTAssertEqual(try read(clone, "a.txt"), "meine Fassung", "geprüft, nichts verändert")
    }

    func testOwnCommitsAreMergedWithUpstream() throws {
        let (origin, clone) = try setup()
        try write(clone, "c.txt", "mein Commit"); git(clone, "add", "."); git(clone, "commit", "-q", "-m", "lokal")
        try write(origin, "a.txt", "a2"); git(origin, "commit", "-q", "-am", "zwei")
        guard case .behind(1, _, let blocker) = NxnativeUpdater.check(repo: clone) else { return XCTFail("müsste 1 zurückliegen") }
        XCTAssertNil(blocker, "eigene Commits sind kein Hindernis mehr")
        XCTAssertEqual(NxnativeUpdater.update(repo: clone), .updated)
        XCTAssertEqual(try read(clone, "a.txt"), "a2")
        XCTAssertEqual(try read(clone, "c.txt"), "mein Commit", "der eigene Commit bleibt")
        XCTAssertEqual(NxnativeUpdater.check(repo: clone), .current)
    }

    func testMergeConflictIsRolledBackAndReported() throws {
        let (origin, clone) = try setup()
        try write(clone, "a.txt", "meine Fassung"); git(clone, "commit", "-q", "-am", "lokal")
        try write(origin, "a.txt", "andere Fassung"); git(origin, "commit", "-q", "-am", "zwei")
        guard case .behind = NxnativeUpdater.check(repo: clone) else { return XCTFail() }
        guard case .failed(let message) = NxnativeUpdater.update(repo: clone) else { return XCTFail("müsste scheitern") }
        XCTAssertTrue(message.contains("Konflikte in a.txt"), message)
        XCTAssertEqual(try read(clone, "a.txt"), "meine Fassung", "zurückgenommen: alles wie vorher")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clone.appendingPathComponent(".git/MERGE_HEAD").path), "kein halber Merge")
    }

    func testNonGitFolderFails() throws {
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        XCTAssertEqual(NxnativeUpdater.check(repo: plain), .failed("kein Git-Ordner"))
    }
}
