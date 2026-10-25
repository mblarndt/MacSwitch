import XCTest
@testable import MacSwitch

final class IPATests: XCTestCase {
    func testReadsTitleFromInfoPlist() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Eckige Klammern im Namen prüfen das Escaping für unzip.
        let app = dir.appendingPathComponent("Payload/Demo [HD].app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": "Demo Game"], format: .binary, options: 0)
        try plist.write(to: app.appendingPathComponent("Info.plist"))

        let ipa = dir.appendingPathComponent("demo.ipa")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-qr", ipa.path, "Payload"]
        try zip.run()
        zip.waitUntilExit()

        XCTAssertEqual(IPA.read(ipa).title, "Demo Game")
    }
}
