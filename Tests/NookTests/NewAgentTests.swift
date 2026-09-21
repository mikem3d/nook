import XCTest
@testable import Nook

final class NewAgentTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1079)
    private let layout = DockLayout()

    // MARK: layout with the plus orb

    func testPlusOrbFollowsTheLastOrbAndLeavesMemberFramesAlone() {
        let plain = DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: [false, true, false])
        var withPlus = plain
        withPlus.plus = true
        let a = layout.solve(area: screen, stacks: [plain])[.bottomRight]!
        let b = layout.solve(area: screen, stacks: [withPlus])[.bottomRight]!
        XCTAssertNil(a.plus)
        XCTAssertEqual(a.frames, b.frames, "the plus orb never moves an agent")
        XCTAssertEqual(b.frames.count, 3)
        let orb = b.frames[1], plus = b.plus!
        XCTAssertEqual(plus.size, orb.size, "same size as an agent orb")
        XCTAssertEqual(plus.minY, orb.maxY + layout.orbGap, "at the far end, after the agent orbs")
        XCTAssertEqual(plus.maxX, orb.maxX, "hugging the screen edge like the other orbs")
    }

    func testAStackOfNothingButThePlusOrbSitsInItsCorner() {
        let p = layout.solve(area: screen, stacks: [DockLayout.Stack(corner: .topLeft, axis: .vertical, minimised: [], plus: true)])[.topLeft]!
        XCTAssertTrue(p.frames.isEmpty)
        XCTAssertEqual(p.plus, CGRect(x: 12, y: 1079 - 12 - 56, width: 56, height: 56))
        XCTAssertTrue(layout.solve(area: screen, stacks: [DockLayout.Stack(corner: .topLeft, axis: .vertical, minimised: [])]).isEmpty)
    }

    func testPlusOrbIsNeverAChamberSoItJoinsNothing() {
        let p = layout.solve(area: screen, stacks: [DockLayout.Stack(corner: .bottomLeft, axis: .horizontal, minimised: [false, false], plus: true)])[.bottomLeft]!
        XCTAssertEqual(p.frames[1].minX, p.frames[0].maxX, "chambers still touch")
        let edges = Connectors.edges(p.frames)
        XCTAssertEqual(edges, [[.right], [.left]], "only the two chambers connect; the plus frame is not among them")
        XCTAssertEqual(p.plus!.minX, p.frames[1].maxX + layout.orbGap)
    }

    func testPlusOrbsKeepClearOfOtherStacksAndTheReservedRect() {
        let stacks = [DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: [false, false, false, false], plus: true),
                      DockLayout.Stack(corner: .topRight, axis: .vertical, minimised: [false, false], plus: true)]
        let reserved = CGRect(x: 364, y: 0, width: 1000, height: 300)
        let result = layout.solve(area: screen, stacks: stacks, reserved: reserved)
        let all = result.values.flatMap { $0.frames + [$0.plus!] }
        for (i, a) in all.enumerated() {
            XCTAssertTrue(screen.contains(a))
            XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(reserved))
            for b in all[(i + 1)...] { XCTAssertFalse(a.insetBy(dx: 1, dy: 1).intersects(b), "\(a) overlaps \(b)") }
        }
    }

    func testEdgeZoneRunsFromTheStackEndAndStopsBeforeTheNextStack() {
        let bottom = DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: [false], plus: true)
        let alone = layout.solve(area: screen, stacks: [bottom])
        let zone = layout.edgeZone(of: .bottomRight, axis: .vertical, in: screen, placements: alone)!
        XCTAssertEqual(zone.minY, alone[.bottomRight]!.plus!.maxY + layout.orbGap)
        XCTAssertEqual(zone.maxY, 1079 - 12)
        XCTAssertEqual(zone.width, 384)

        let top = DockLayout.Stack(corner: .topRight, axis: .vertical, minimised: [false], plus: true)
        let both = layout.solve(area: screen, stacks: [bottom, top])
        let lower = layout.edgeZone(of: .bottomRight, axis: .vertical, in: screen, placements: both)!
        let upper = layout.edgeZone(of: .topRight, axis: .vertical, in: screen, placements: both)!
        XCTAssertEqual(lower.maxY, both[.topRight]!.plus!.minY - layout.gap)
        XCTAssertEqual(upper.minY, both[.bottomRight]!.plus!.maxY + layout.gap)
        XCTAssertNil(layout.edgeZone(of: .topLeft, axis: .vertical, in: screen, placements: both), "no stack, no zone")
    }

    func testEdgeZoneIsNilWhenTheStackFillsItsEdge() {
        let full = DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: [false, false, false, false], plus: true)
        let placements = layout.solve(area: CGRect(x: 0, y: 0, width: 1728, height: 960), stacks: [full])
        XCTAssertNil(layout.edgeZone(of: .bottomRight, axis: .vertical, in: CGRect(x: 0, y: 0, width: 1728, height: 960), placements: placements))
    }

    // MARK: project path decoding

    private func disk(_ paths: String...) -> (String) -> Bool {
        var all = Set<String>()
        for path in paths {
            var url = URL(fileURLWithPath: path)
            while url.path != "/" { all.insert(url.path); url.deleteLastPathComponent() }
        }
        return { all.contains($0) }
    }

    func testEncodeMatchesClaudeCode() {
        XCTAssertEqual(ProjectPaths.encode("/Users/z/work/asche-kron"), "-Users-z-work-asche-kron")
        XCTAssertEqual(ProjectPaths.encode("/Users/z/.claude/my_app v2"), "-Users-z--claude-my-app-v2")
    }

    func testDecodePlainPath() {
        XCTAssertEqual(ProjectPaths.decode("-Users-z-work-nook", isDirectory: disk("/Users/z/work/nook")), "/Users/z/work/nook")
    }

    func testDecodeKeepsDashesThatAreReallyInTheName() {
        let exists = disk("/Users/z/work/claude-avatar/nook-mac")
        XCTAssertEqual(ProjectPaths.decode("-Users-z-work-claude-avatar-nook-mac", isDirectory: exists), "/Users/z/work/claude-avatar/nook-mac")
    }

    func testDecodeDotsUnderscoresAndSpaces() {
        XCTAssertEqual(ProjectPaths.decode("-Users-z--claude-my-app-v2", isDirectory: disk("/Users/z/.claude/my_app v2")), "/Users/z/.claude/my_app v2")
    }

    func testDecodePrefersTheDeeperFolderWhenBothExist() {
        XCTAssertEqual(ProjectPaths.decode("-a-b-c", isDirectory: disk("/a/b/c", "/a/b-c")), "/a/b/c")
    }

    func testDecodeGivesUpOnMissingFoldersAndMalformedNames() {
        XCTAssertNil(ProjectPaths.decode("-Users-z-gone", isDirectory: disk("/Users/z")))
        XCTAssertNil(ProjectPaths.decode("no-leading-dash", isDirectory: { _ in true }))
        XCTAssertNil(ProjectPaths.decode("-", isDirectory: { _ in true }))
        var checks = 0
        XCTAssertNil(ProjectPaths.decode("-" + Array(repeating: "x", count: 24).joined(separator: "-")) { _ in checks += 1; return false })
        XCTAssertLessThanOrEqual(checks, 2000, "a name with many dashes cannot run away")
    }

    // MARK: recents

    func testRecentsAreNewestFirstWithoutDuplicates() {
        var recents = RecentFolders()
        recents.touch("/p/a", sessionID: "s1")
        recents.touch("/p/b")
        recents.touch("/p/a/") // the same folder, spelled differently
        XCTAssertEqual(recents.entries.map(\.path), ["/p/a", "/p/b"])
        XCTAssertEqual(recents.entries[0].sessionID, "s1", "a touch without a session keeps the known one")
    }

    func testRecentsNoteRemoveAndLimit() {
        var recents = RecentFolders()
        recents.touch("/p/a")
        recents.touch("/p/b")
        XCTAssertTrue(recents.note(sessionID: "s2", for: "/p/a"))
        XCTAssertFalse(recents.note(sessionID: "s2", for: "/p/a"), "nothing to save the second time")
        XCTAssertFalse(recents.note(sessionID: "s3", for: "/p/unknown"))
        XCTAssertEqual(recents.entries.map(\.path), ["/p/b", "/p/a"], "noting a session does not reorder")
        recents.remove("/p/b")
        XCTAssertEqual(recents.entries.map(\.path), ["/p/a"])
        for i in 0..<40 { recents.touch("/p/\(i)") }
        XCTAssertEqual(recents.entries.count, RecentFolders.limit)
        XCTAssertEqual(recents.entries[0].path, "/p/39")
        let copy = try? JSONDecoder().decode(RecentFolders.self, from: JSONEncoder().encode(recents))
        XCTAssertEqual(copy, recents)
    }

    func testChoicesPutRecentsFirstAndBorrowAKnownSession() {
        var recents = RecentFolders()
        recents.touch("/p/a")
        let suggested = [FolderChoice(path: "/p/a", source: .suggested, sessionID: "s9"), FolderChoice(path: "/p/c", source: .suggested)]
        let choices = NewAgentRules.choices(recents: recents, suggested: suggested)
        XCTAssertEqual(choices, [FolderChoice(path: "/p/a", source: .recent, sessionID: "s9"), FolderChoice(path: "/p/c", source: .suggested)])
    }

    // MARK: search

    func testSearchRanking() {
        let choices = ["/w/zipdemand", "/w/nook-mac", "/w/big-nook", "/w/snooker", "/w/notebook", "/nook/other"]
            .map { FolderChoice(path: $0, source: .recent) }
        XCTAssertEqual(FolderSearch.rank("nook", in: choices).map(\.name), ["nook-mac", "big-nook", "snooker", "notebook", "other"])
        XCTAssertEqual(FolderSearch.rank("  ", in: choices), choices, "an empty query keeps everything in order")
        XCTAssertEqual(FolderSearch.rank("ZIP", in: choices).map(\.name), ["zipdemand"])
        XCTAssertTrue(FolderSearch.rank("qqq", in: choices).isEmpty)
    }

    func testEqualScoresKeepTheirOrder() {
        let choices = ["/w/app-one", "/w/app-two", "/w/app-three"].map { FolderChoice(path: $0, source: .recent) }
        XCTAssertEqual(FolderSearch.rank("app", in: choices), choices)
    }

    // MARK: duplicates and limits

    func testDuplicateDetection() {
        let open: [String?] = [nil, "/p/a", "/p/b/"]
        XCTAssertEqual(NewAgentRules.existing("/p/b", among: open), 2)
        XCTAssertEqual(NewAgentRules.existing("/p/x/../a", among: open), 1)
        XCTAssertNil(NewAgentRules.existing("/p/c", among: open))
        XCTAssertNil(NewAgentRules.existing("/p/a", among: [nil, nil]), "demo agents have no folder")
    }

    func testUsageNoteStartsAtEightAndNeverBlocks() {
        XCTAssertNil(NewAgentRules.usageNote(count: 7))
        XCTAssertNotNil(NewAgentRules.usageNote(count: 8))
        XCTAssertNotNil(NewAgentRules.usageNote(count: 20))
    }
}
