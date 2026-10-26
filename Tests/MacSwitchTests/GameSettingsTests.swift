import XCTest
@testable import MacSwitch

final class GameSettingsTests: XCTestCase {
    private func setting(_ env: String) -> GameSetting { GameSettings.catalog.first { $0.env == env }! }

    func testSteppingChoicesTogglesAndRanges() {
        let fps = setting("DM_FPS_TARGET"), snap = setting("DM_PRESENT_SNAP"), scale = setting("DM_RENDER_SCALE")
        XCTAssertEqual(fps.stepped(from: "30", by: 1), "60")
        XCTAssertEqual(fps.stepped(from: "60", by: 1), "30", "Auswahl läuft rund")
        XCTAssertEqual(fps.stepped(from: nil, by: 1), "30", "ohne Wert: die erste")
        XCTAssertEqual(snap.stepped(from: "1", by: 1), "0")
        XCTAssertEqual(snap.stepped(from: nil, by: 1), "1")
        XCTAssertEqual(scale.stepped(from: "1.0", by: -1), "0.95")
        XCTAssertEqual(scale.stepped(from: "1.0", by: 1), "1.0", "am oberen Ende halten")
        XCTAssertEqual(scale.stepped(from: "1.0", by: 1, wrap: true), "0.5", "mit A zurück an den Anfang")
        XCTAssertEqual(scale.stepped(from: "0.5", by: -1), "0.5")
        XCTAssertEqual(setting("DM_RUMBLE_GAIN").stepped(from: "1.0", by: 1), "1.1")
        XCTAssertEqual(scale.text(for: "0.75"), "75 %")
        XCTAssertEqual(snap.text(for: "1"), "An")
        XCTAssertEqual(fps.text(for: "60"), "60 fps")
        XCTAssertEqual(fps.text(for: nil), "Standard")
    }

    /// Eine App und ein nxnative-Ordner wie im echten Fall: Profil (game.tsv), Umschreibtabelle und Metal-Bibliotheken.
    private func fixture(profile: String, fixups: String, msl: String) throws -> (game: Game, repo: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        let app = tmp.appendingPathComponent("Test.app"), res = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: res.appendingPathComponent("patched"), withIntermediateDirectories: true)
        try fm.createDirectory(at: res.appendingPathComponent("msl/\(msl)"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "org.nxnative.mac.0100ABCD00001000", "CFBundleName": "Test"], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try fixups.write(to: res.appendingPathComponent("patched/main.fixups.tsv"), atomically: true, encoding: .utf8)
        let games = tmp.appendingPathComponent("repo/dm/games/0100ABCD00001000")
        try fm.createDirectory(at: games, withIntermediateDirectories: true)
        try profile.write(to: games.appendingPathComponent("game.tsv"), atomically: true, encoding: .utf8)
        return (Game(app: app), tmp.appendingPathComponent("repo"))
    }

    func testAvailableSettingsAndDefaultsFollowTheGameProfile() throws {
        let f = try fixture(profile: "# c\ntitle_id\t0100ABCD00001000\nfps_target\t30\nop_mode\thandheld\npresent_snap\ton\n", fixups: "# PATCH_OFF\t0x1\n# RENDER_SCALE\t0x2\n", msl: "b-1234")
        let p = GameProfile(game: f.game, repo: f.repo)
        XCTAssertEqual(p.values["fps_target"], "30")
        XCTAssertTrue(p.fixups.contains("RENDER_SCALE") && p.nvn)
        let ids = GameSettings.available(for: p).map(\.env)
        XCTAssertTrue(ids.contains("DM_FPS_TARGET") && ids.contains("DM_RENDER_SCALE") && ids.contains("DM_FPS_HOLD") && ids.contains("DM_PSO_MTL4"))
        XCTAssertEqual(GameSettings.defaultValue(setting("DM_FPS_TARGET"), p), "30")
        XCTAssertEqual(GameSettings.defaultValue(setting("DM_OPMODE"), p), "0", "Profil: Handheld")
        XCTAssertEqual(GameSettings.defaultValue(setting("DM_PRESENT_SNAP"), p), "1")
    }

    func testGamesWithoutFpsControlRenderScaleOrNvnHideThoseSettings() throws {
        let f = try fixture(profile: "title_id\t0100ABCD00001000\n", fixups: "# PATCH_OFF\t0x1\n", msl: "vk")
        let p = GameProfile(game: f.game, repo: f.repo)
        XCTAssertFalse(p.nvn)
        let ids = Set(GameSettings.available(for: p).map(\.env))
        XCTAssertTrue(ids.isDisjoint(with: ["DM_FPS_TARGET", "DM_FPS_HOLD", "DM_RENDER_SCALE", "DM_PRESENT_SNAP", "DM_PSO_MTL4", "DM_PSO_PREBUILD", "DM_NVN_ENC_THREAD"]), "\(ids)")
        XCTAssertTrue(ids.isSuperset(of: ["DM_OPMODE", "DM_PRESENT_UPSCALE", "DM_RUMBLE"]))
    }

    func testStoreKeepsOnlyChangesPerGame() {
        let saved = GameSettingsStore.file
        defer { GameSettingsStore.file = saved }
        GameSettingsStore.file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/settings.json")
        XCTAssertEqual(GameSettingsStore.values(for: "A.app"), [:])
        GameSettingsStore.set("DM_FPS_TARGET", "60", for: "A.app")
        GameSettingsStore.set("DM_OPMODE", "0", for: "A.app")
        GameSettingsStore.set("DM_OPMODE", "1", for: "B.app")
        XCTAssertEqual(GameSettingsStore.values(for: "A.app"), ["DM_FPS_TARGET": "60", "DM_OPMODE": "0"])
        GameSettingsStore.set("DM_OPMODE", nil, for: "A.app")
        XCTAssertEqual(GameSettingsStore.values(for: "A.app"), ["DM_FPS_TARGET": "60"])
        GameSettingsStore.reset(for: "A.app")
        XCTAssertEqual(GameSettingsStore.values(for: "A.app"), [:])
        XCTAssertEqual(GameSettingsStore.values(for: "B.app"), ["DM_OPMODE": "1"], "andere Spiele bleiben")
    }
}
