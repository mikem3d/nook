import XCTest
@testable import Nook

final class SceneLogicTests: XCTestCase {
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
