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
