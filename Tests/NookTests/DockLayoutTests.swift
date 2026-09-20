import XCTest
@testable import Nook

final class DockLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1079)
    private let layout = DockLayout()

    private func stack(_ corner: Corner, _ axis: DockLayout.Axis, _ count: Int, minimised: Set<Int> = []) -> DockLayout.Stack {
        DockLayout.Stack(corner: corner, axis: axis, minimised: (0..<count).map { minimised.contains($0) })
    }

    private func assertClean(_ result: [Corner: DockLayout.Placement], in area: CGRect, avoiding reserved: CGRect? = nil,
                             file: StaticString = #filePath, line: UInt = #line) {
        let all = result.values.flatMap(\.frames)
        for (i, a) in all.enumerated() {
            XCTAssertTrue(area.contains(a), "\(a) leaves \(area)", file: file, line: line)
            if let reserved { XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(reserved), "\(a) covers the reserved rect", file: file, line: line) }
            for b in all[(i + 1)...] {
                XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(b), "\(a) overlaps \(b)", file: file, line: line)
            }
        }
    }

    func testSingleColumnGrowsFromItsCornerAtFullScale() {
        let result = layout.solve(area: screen, stacks: [stack(.bottomRight, .vertical, 2)])
        let p = result[.bottomRight]!
        XCTAssertEqual(p.scale, 2)
        XCTAssertEqual(p.lines, 1)
        XCTAssertEqual(p.frames[0], CGRect(x: 1728 - 12 - 384, y: 12, width: 384, height: 216))
        XCTAssertEqual(p.frames[1].minY, 12 + 216 + 8)
    }

    func testTopLeftRowRunsRightAndMinimisedIsShort() {
        let p = layout.solve(area: screen, stacks: [stack(.topLeft, .horizontal, 2, minimised: [1])])[.topLeft]!
        XCTAssertEqual(p.frames[0], CGRect(x: 12, y: 1079 - 12 - 216, width: 384, height: 216))
        XCTAssertEqual(p.frames[1], CGRect(x: 12 + 384 + 8, y: 1079 - 12 - 22, width: 384, height: 22))
    }

    func testLongColumnShrinksBeforeItWraps() {
        let p = layout.solve(area: screen, stacks: [stack(.bottomRight, .vertical, 6)])[.bottomRight]!
        XCTAssertEqual(p.lines, 1)
        XCTAssertEqual(p.scale, 1.5)
    }

    func testVeryLongColumnWrapsIntoASecondLine() {
        let result = layout.solve(area: screen, stacks: [stack(.bottomRight, .vertical, 12)])
        let p = result[.bottomRight]!
        XCTAssertEqual(p.lines, 2)
        XCTAssertEqual(Set(p.frames.map(\.minX)).count, 2)
        assertClean(result, in: screen)
    }

    func testRowMeetingAColumnNeverOverlaps() {
        // A long row from the bottom left runs into the column standing in the bottom right.
        let stacks = [stack(.bottomLeft, .horizontal, 8), stack(.bottomRight, .vertical, 3)]
        let result = layout.solve(area: screen, stacks: stacks)
        assertClean(result, in: screen)
        XCTAssertEqual(result[.bottomRight]!.scale, 2, "the short stack keeps its size; the long one gives way")
    }

    func testFacingColumnsShareAnEdge() {
        let result = layout.solve(area: screen, stacks: [stack(.bottomRight, .vertical, 3), stack(.topRight, .vertical, 3)])
        assertClean(result, in: screen)
    }

    func testAllFourCornersCrowded() {
        let stacks = [stack(.bottomRight, .vertical, 5), stack(.topRight, .horizontal, 6),
                      stack(.bottomLeft, .horizontal, 6), stack(.topLeft, .vertical, 5)]
        assertClean(layout.solve(area: screen, stacks: stacks), in: screen)
    }

    func testNegativeOriginScreen() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
        let result = layout.solve(area: left, stacks: [stack(.topLeft, .vertical, 2), stack(.bottomRight, .horizontal, 3)])
        assertClean(result, in: left)
        XCTAssertEqual(result[.topLeft]!.frames[0].origin, CGPoint(x: -1920 + 12, y: -200 + 1055 - 12 - 216))
        XCTAssertEqual(result[.bottomRight]!.frames[0].maxX, -12)
    }

    func testBottomRowStaysClearOfTheChatPanel() {
        let chat = CGRect(x: screen.midX - 340, y: 24, width: 680, height: 440)
        let result = layout.solve(area: screen, stacks: [stack(.bottomLeft, .horizontal, 4)], reserved: chat)
        assertClean(result, in: screen, avoiding: chat)
    }

    func testStackThatCannotAvoidThePanelIsLiftedAboveIt() {
        let small = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let chat = CGRect(x: 0, y: 24, width: 1000, height: 300) // spans the whole width: nowhere to go but up
        let result = layout.solve(area: small, stacks: [stack(.bottomRight, .vertical, 2)], reserved: chat)
        assertClean(result, in: small, avoiding: chat)
        XCTAssertGreaterThanOrEqual(result[.bottomRight]!.frames[0].minY, chat.maxY)
    }

    func testTopStacksIgnoreThePanel() {
        let chat = CGRect(x: screen.midX - 340, y: 24, width: 680, height: 440)
        let p = layout.solve(area: screen, stacks: [stack(.topRight, .vertical, 2)], reserved: chat)[.topRight]!
        XCTAssertEqual(p.scale, 2)
    }

    func testFixedScaleWrapsInsteadOfShrinking() {
        var fixed = DockLayout()
        fixed.scales = [2]
        fixed.fallbackScales = [1.5, 1]
        let result = fixed.solve(area: screen, stacks: [stack(.bottomRight, .vertical, 6)])
        XCTAssertEqual(result[.bottomRight]!.scale, 2)
        XCTAssertEqual(result[.bottomRight]!.lines, 2)
        assertClean(result, in: screen)
    }

    func testHopelesslyFullScreenStillReturnsEveryFrame() {
        let tiny = CGRect(x: 0, y: 0, width: 640, height: 480)
        let p = layout.solve(area: tiny, stacks: [stack(.bottomRight, .vertical, 30)])[.bottomRight]!
        XCTAssertEqual(p.frames.count, 30)
    }
}
