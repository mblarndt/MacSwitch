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
