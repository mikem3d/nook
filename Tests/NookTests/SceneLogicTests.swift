import XCTest
@testable import Nook

final class SceneLogicTests: XCTestCase {
    /// A finished turn glows until the window is looked at or the agent starts something new.
    func testFinishedTurnGlowsUntilSeen() throws {
        let scene = RoomScene(art: try Art(), roomIndex: 0, title: "p", avatarSeed: nil)
        scene.show(state: .working, bubble: "", unread: 0)
        scene.show(state: .done, bubble: "Done.", unread: 1)
        XCTAssertTrue(scene.celebrating)
        scene.show(state: .idle, bubble: "", unread: 1)
        XCTAssertTrue(scene.celebrating, "relaxing to idle unseen keeps the glow")
        scene.setActive(true)
        XCTAssertFalse(scene.celebrating)

        scene.show(state: .done, bubble: "Again.", unread: 0)
        XCTAssertTrue(scene.celebrating)
        scene.show(state: .idle, bubble: "", unread: 0)
        XCTAssertFalse(scene.celebrating, "watched it finish, so idle clears it")

        scene.setActive(false)
        scene.show(state: .done, bubble: "Third.", unread: 0)
        scene.show(state: .working, bubble: "", unread: 0)
        XCTAssertFalse(scene.celebrating, "new work clears it")
    }

    func testWrapAndPages() {
        XCTAssertEqual(TextPager.wrap("Fixed the zip lookup. All 42 tests pass.", columns: 16),
                       ["Fixed the zip", "lookup. All 42", "tests pass."])
        XCTAssertEqual(TextPager.wrap("a\n\n  b   c ", columns: 10), ["a", "b c"])
        XCTAssertEqual(TextPager.wrap("abcdefghij", columns: 4), ["abcd", "efgh", "ij"])
        XCTAssertEqual(TextPager.wrap("", columns: 4), [])
        let pages = TextPager.pages(String(repeating: "word ", count: 40), columns: 20, rows: 3)
        XCTAssertEqual(pages.count, 4)
        XCTAssertTrue(pages.allSatisfy { $0.count <= 3 && $0.allSatisfy { $0.count <= 20 } })
        XCTAssertEqual(pages.joined().joined(separator: " ").split(separator: " ").count, 40, "paging drops nothing")
    }

    /// The recap stays fresh for a few minutes, then fades, but never disappears.
    func testRecapFadesWithAge() {
        let fresh = RoomScene.recapAlpha(age: 0)
        XCTAssertEqual(RoomScene.recapAlpha(age: 4 * 60), fresh)
        XCTAssertLessThan(RoomScene.recapAlpha(age: 3600), fresh)
        XCTAssertLessThan(RoomScene.recapAlpha(age: 3 * 3600), RoomScene.recapAlpha(age: 3600))
        XCTAssertEqual(RoomScene.recapAlpha(age: 3 * 3600), RoomScene.recapAlpha(age: 30 * 86400))
        XCTAssertGreaterThan(RoomScene.recapAlpha(age: 30 * 86400), 0.3)
    }

    /// A restored window says what it was last doing, with the original time so it is already faded.
    func testRecapSurvivesARestart() throws {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let agent = Persistence.SavedAgent(folder: "/tmp", label: "nook", sessionID: "s", corner: 0, order: 0,
                                           minimised: false, display: nil, scene: nil, recap: "Fixed the log", recapAt: at)
        let data = try JSONEncoder().encode(Persistence.SavedState(agents: [agent], axes: []))
        let back = try JSONDecoder().decode(Persistence.SavedState.self, from: data).agents[0]
        XCTAssertEqual(back.recap, "Fixed the log")
        XCTAssertEqual(back.recapAt, at)

        let session = AgentSession(label: "nook", cwd: nil)
        session.restoreSummary("Fixed the log", at: at)
        XCTAssertEqual(session.summary, "Fixed the log")
        XCTAssertEqual(session.summaryAt, at)

        // State files written before recaps existed still load.
        let old = #"{"version":1,"axes":[],"agents":[{"folder":"/tmp","label":"a","corner":0,"order":0,"minimised":false}]}"#
        let legacy = try JSONDecoder().decode(Persistence.SavedState.self, from: Data(old.utf8)).agents[0]
        XCTAssertNil(legacy.recap)
    }

    /// The done pose relaxes after a few seconds; its bubble stays until it has had time to be read.
    func testBubbleOutlastsThePose() {
        let session = AgentSession(label: "demo", cwd: nil)
        let text = "Fixed bubble placement, added done glow and hop"
        session.simulate(.done, text: text)
        for _ in 0..<12 { session.tick(0.5) }
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.bubble, text, "still up after the pose relaxed")
        let rest = AgentSession.linger(text) - 6 + 1
        for _ in 0..<Int(rest / 0.5) { session.tick(0.5) }
        XCTAssertEqual(session.bubble, "")
        XCTAssertEqual(session.state, .idle)
    }

    func testVitalLevels() {
        XCTAssertEqual(Vitals.level(fraction: 0, states: 11), 0)
        XCTAssertEqual(Vitals.level(fraction: 0.01, states: 11), 1)
        XCTAssertEqual(Vitals.level(fraction: 0.5, states: 11), 5)
        XCTAssertEqual(Vitals.level(fraction: 1.4, states: 11), 10)
        XCTAssertEqual(Vitals.level(fraction: 0.5, states: 1), 0)

        XCTAssertEqual(Vitals.coins(cost: 0, states: 9), 0)
        XCTAssertEqual(Vitals.coins(cost: 0.01, states: 9), 1)
        XCTAssertEqual(Vitals.coins(cost: 20, states: 9), 8)
        XCTAssertEqual(Vitals.coins(cost: 500, states: 9), 8)
        let levels = [0.01, 0.05, 0.3, 1, 4, 12, 20].map { Vitals.coins(cost: $0, states: 9) }
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertGreaterThan(Set(levels).count, 4, "the log scale spreads typical costs over the jar")

        XCTAssertEqual([3, 7, 12, 18, 23].map { Vitals.sky(hour: $0, states: 3) }, [2, 1, 0, 1, 2])
    }

    func testSavedStateRoundTripsAndSkipsMissingFolders() throws {
        let here = FileManager.default.temporaryDirectory.path
        let state = Persistence.SavedState(agents: [
            .init(folder: "/no/such/folder", label: "gone", sessionID: nil, corner: 0, order: 0, minimised: false, display: 1),
            .init(folder: here, label: "b", sessionID: "abc", corner: 2, order: 2, minimised: true, display: nil),
            .init(folder: here, label: "a", sessionID: nil, corner: 1, order: 1, minimised: false, display: 7),
        ], axes: [.init(display: 1, corner: 2, axis: .horizontal)])
        let decoded = try JSONDecoder().decode(Persistence.SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(Persistence.restorable(decoded).map(\.label), ["a", "b"])
    }

    func testBundledThemeDeclaresEveryPropAndTheFontLoads() throws {
        let art = try Art()
        for name in ["window", "bookshelf", "coinjar", "papers", "clock", "hourglass"] {
            let loaded = try XCTUnwrap(art.states(forProp: name), name)
            XCTAssertEqual(loaded.textures.count, loaded.prop.states)
        }
        XCTAssertNil(art.states(forProp: "no-such-prop"))
        PixelFont.register(art.url("fonts/DepartureMono-Regular.otf"))
        XCTAssertTrue(PixelFont.shared.pixelated)
        let text = try XCTUnwrap(PixelFont.shared.image(lines: ["Hi!", "ok"], color: .white))
        XCTAssertEqual(text.size, CGSize(width: 21, height: 22))
        XCTAssertEqual(text.image.width, 21, "one font pixel per image pixel")
    }
}
