import AppKit
import XCTest
@testable import MacSwitch

final class LibraryTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testGameTitleComesFromBundleThroughSymlink() throws {
        let dir = try tempDir()
        let contents = dir.appendingPathComponent("Fake.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Fake Game", "CFBundleIdentifier": "test.fake"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let link = dir.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("Fake.app"))

        XCTAssertEqual(Game(app: link).title, "Fake Game")
    }

    func testBrowserListsFoldersBeforeAppsAndHidesOtherFiles() throws {
        let dir = try tempDir()
        for folder in ["Zeta", "Alpha.app", "Beta.app"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Data().write(to: dir.appendingPathComponent("notes.txt"))

        XCTAssertEqual(FileBrowser.entries(in: dir).map(\.lastPathComponent), ["Zeta", "Alpha.app", "Beta.app"])
    }

    func testBrowserFileKindListsFoldersThenMatchingFilesIgnoringCase() throws {
        let dir = try tempDir()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Games"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Fake.app"), withIntermediateDirectories: true)
        for file in ["b.NSP", "a.xci", "notes.txt"] { try Data().write(to: dir.appendingPathComponent(file)) }

        let names = FileBrowser.entries(in: dir, kind: .file(GameBuilder.extensions)).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Games", "a.xci", "b.NSP"])
        XCTAssertEqual(FileBrowser.entries(in: dir, kind: .folder).map(\.lastPathComponent), ["Games"])
    }
}

final class BuilderTests: XCTestCase {
    func testNameDropsTitleIdAndVersionTags() {
        let rom = URL(fileURLWithPath: "/x/Super Mario Bros. Wonder [010015100B514000][v0].nsp")
        XCTAssertEqual(GameBuilder.name(rom), "Super Mario Bros. Wonder")
        XCTAssertEqual(GameBuilder.name(URL(fileURLWithPath: "/x/Game (EU): Deluxe.xci")), "Game- Deluxe")
        XCTAssertEqual(GameBuilder.name(URL(fileURLWithPath: "/x/[010015100B514000].nsp")), "Game")
    }

    /// Ganzer Ablauf mit Attrappen-Skripten statt nxnative: Fortschrittszeilen lesen, danach make_mac_app.py mit dem Startbefehl, dann `done`.
    /// Anschließend ein Update installieren und neu bauen: das Skript bekommt den Arbeitsordner mit dem neuen Link.
    func testRunsBuildThenMakeAppAndReportsApp() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scripts = tmp.appendingPathComponent("repo/scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try """
        import json, os, sys
        assert sys.argv[-2:] == ["--platform", "mac"], sys.argv
        open(os.path.join(os.path.dirname(sys.argv[1]), "seen.txt"), "w").write("\\n".join(sorted(os.listdir(sys.argv[1]))))
        for e in ({"ev": "stage", "k": 1, "n": 1, "name": "Fake"}, {"ev": "say", "msg": "cd /tmp && DM_ROMFS=x host patched"}):
            print(json.dumps(e), flush=True)
        """.write(to: scripts.appendingPathComponent("build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        try """
        import os, shutil, sys
        assert sys.argv[2] == "Fake Game" and sys.argv[3].startswith("cd /tmp"), sys.argv
        shutil.rmtree(sys.argv[1], ignore_errors=True)
        os.mkdir(sys.argv[1])
        """.write(to: scripts.appendingPathComponent("make_mac_app.py"), atomically: true, encoding: .utf8)
        let rom = tmp.appendingPathComponent("Fake Game [0100000000000000][v0].nsp")
        try Data().write(to: rom)

        let builder = GameBuilder()
        builder.repo = tmp.appendingPathComponent("repo")
        builder.rom = rom
        builder.keys = tmp.appendingPathComponent("prod.keys")
        builder.out = tmp.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: builder.out!, withIntermediateDirectories: true)
        XCTAssertTrue(builder.ready)

        func wait() {
            let deadline = Date().addingTimeInterval(20)
            while builder.running && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        }

        var app: URL?
        builder.start { app = $0 }
        wait()

        XCTAssertEqual(builder.status, "Fertig", builder.error)
        XCTAssertEqual(app?.lastPathComponent, "Fake Game.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app?.path ?? ""))

        let game = Game(app: app!)
        let work = try XCTUnwrap(GameBuilder.workFolder(of: game))
        XCTAssertNil(GameBuilder.workFolder(of: Game(app: tmp.appendingPathComponent("Other.app"))))

        let update = tmp.appendingPathComponent("Fake Game [0100000000000800][v65536].nsp")
        try Data().write(to: update)
        try GameBuilder.install(update, into: work)
        try GameBuilder.install(update, into: work) // dieselbe Datei nochmal: kein zweiter Link
        XCTAssertEqual(GameBuilder.installedFiles(in: work).map(\.lastPathComponent), [rom.lastPathComponent, update.lastPathComponent])
        XCTAssertThrowsError(try GameBuilder.install(tmp.appendingPathComponent("notes.txt"), into: work))

        var rebuilt: URL?
        builder.rebuild(game) { rebuilt = $0 }
        wait()

        XCTAssertEqual(builder.status, "Fertig", builder.error)
        XCTAssertEqual(rebuilt?.lastPathComponent, "Fake Game.app")
        let seen = try String(contentsOf: builder.out!.appendingPathComponent("NxNative-Work/seen.txt"), encoding: .utf8)
        XCTAssertTrue(seen.contains("[v65536]"), seen)
    }
}

final class IconTests: XCTestCase {
    func testTrimmedRemovesTransparentMargin() {
        // 200×200 transparent, mittig ein deckendes 100×100-Quadrat → nach dem Trimmen bleibt ~die Hälfte der 512 px Rasterbreite.
        let img = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { _ in
            NSColor.red.setFill()
            NSRect(x: 50, y: 50, width: 100, height: 100).fill()
            return true
        }
        let w = img.trimmed().size.width
        XCTAssertEqual(w, 256, accuracy: 4)
    }
}
