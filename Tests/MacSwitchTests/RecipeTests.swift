import XCTest
@testable import MacSwitch

final class RecipeTests: XCTestCase {
    private func tmp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Eine NSP, die nur aus dem PFS0-Kopf mit den Dateinamen besteht (Daten leer).
    private func nsp(named names: [String], at url: URL) throws {
        var table = Data(), entries = Data()
        func le(_ v: Int, _ n: Int) -> Data { Data((0..<n).map { UInt8((v >> (8 * $0)) & 255) }) }
        for n in names { entries += le(0, 8) + le(0, 8) + le(table.count, 4) + le(0, 4); table += Data(n.utf8) + Data([0]) }
        try (Data("PFS0".utf8) + le(names.count, 4) + le(table.count, 4) + le(0, 4) + entries + table).write(to: url)
    }

    func testTitleIDFromFileNameUpdateBaseAndTicket() throws {
        let d = try tmp()
        XCTAssertEqual(Recipe.titleID(of: URL(fileURLWithPath: "/x/Super Mario Bros. Wonder [010015100b514000][v0].nsp")), "010015100B514000")
        XCTAssertEqual(Recipe.titleID(of: URL(fileURLWithPath: "/x/Wonder[010015100B514000][1.0.0][0][16.0.3].nsp")), "010015100B514000")
        XCTAssertEqual(Recipe.titleID(of: URL(fileURLWithPath: "/x/Wonder Update [010015100B514800][v65536].nsp")), "010015100B514000", "ein Update gehört zu seinem Basisspiel")
        XCTAssertNil(Recipe.titleID(of: URL(fileURLWithPath: "/x/ohne Kennung.xci")))

        let file = d.appendingPathComponent("Spiel ohne Tag.nsp")
        try nsp(named: ["abc.cnmt.nca", "0100152000022000000000000000000A.tik", "0100152000022000000000000000000A.cert"], at: file)
        XCTAssertEqual(Recipe.titleID(of: file), "0100152000022000", "aus dem Ticket der NSP")
        let plain = d.appendingPathComponent("leer.nsp"); try Data("kein pfs0".utf8).write(to: plain)
        XCTAssertNil(Recipe.titleID(of: plain))
    }

    func testLookupFindsRecipeMissingAndUpstreamOnly() throws {
        let d = try tmp(), origin = d.appendingPathComponent("origin"), clone = d.appendingPathComponent("clone")
        try FileManager.default.createDirectory(at: origin.appendingPathComponent("dm/games/010015100B514000"), withIntermediateDirectories: true)
        try "# c\nname\tSuper Mario Bros. Wonder\nbuild\tv0\t1.0.0\tmain=x\nbuild\tv327680\t1.2.1\tmain=y\n".write(to: origin.appendingPathComponent("dm/games/010015100B514000/game.tsv"), atomically: true, encoding: .utf8)
        func git(_ dir: URL, _ args: String...) { XCTAssertEqual(NxnativeUpdater.git(["-c", "user.name=t", "-c", "user.email=t@t"] + args, in: dir).status, 0, args.joined(separator: " ")) }
        git(origin, "init", "-q", "-b", "main"); git(origin, "add", "."); git(origin, "commit", "-q", "-m", "eins")
        XCTAssertEqual(NxnativeUpdater.git(["clone", "-q", origin.path, clone.path], in: d).status, 0)

        let wonder = URL(fileURLWithPath: "/x/Wonder [010015100B514000][v0].nsp")
        XCTAssertEqual(Recipe.lookup(rom: wonder, repo: clone), .found(name: "Super Mario Bros. Wonder", versions: ["1.0.0", "1.2.1"]))
        XCTAssertTrue(Recipe.lookup(rom: wonder, repo: clone).text.contains("getestet: 1.0.0, 1.2.1"))
        XCTAssertEqual(Recipe.lookup(rom: URL(fileURLWithPath: "/x/Neu [0100AAAA0000B000].nsp"), repo: clone), .missing(titleID: "0100AAAA0000B000"))
        XCTAssertEqual(Recipe.lookup(rom: URL(fileURLWithPath: "/x/ohne.xci"), repo: clone), .unknown)

        // Ein Rezept, das nur im Upstream steht.
        try FileManager.default.createDirectory(at: origin.appendingPathComponent("dm/games/0100AAAA0000B000"), withIntermediateDirectories: true)
        try "name\tNeu\n".write(to: origin.appendingPathComponent("dm/games/0100AAAA0000B000/game.tsv"), atomically: true, encoding: .utf8)
        git(origin, "add", "."); git(origin, "commit", "-q", "-m", "zwei")
        XCTAssertEqual(NxnativeUpdater.git(["fetch", "-q"], in: clone).status, 0)
        XCTAssertEqual(Recipe.lookup(rom: URL(fileURLWithPath: "/x/Neu [0100AAAA0000B000].nsp"), repo: clone), .upstreamOnly)
    }
}
