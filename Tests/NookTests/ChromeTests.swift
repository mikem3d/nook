import XCTest
@testable import Nook

final class ChromeTests: XCTestCase {
    // MARK: hit testing

    func testHeaderHitAreasScaleFromTheRightEdge() {
        for s in [1.0, 1.5, 2.0] as [CGFloat] {
            let size = CGSize(width: RoomScene.W * s, height: RoomScene.H * s)
            let header = size.height - 2 * s
            XCTAssertEqual(WindowChrome.hit(CGPoint(x: size.width - 3 * s, y: header), in: size, minimised: false), .close)
            XCTAssertEqual(WindowChrome.hit(CGPoint(x: size.width - (RoomScene.closeHit + 1) * s, y: header), in: size, minimised: false), .minimise)
            XCTAssertEqual(WindowChrome.hit(CGPoint(x: size.width - (RoomScene.minimiseHit + 1) * s, y: header), in: size, minimised: false), .body)
            // Below the header the right-hand side is just the room.
            XCTAssertEqual(WindowChrome.hit(CGPoint(x: size.width - 3 * s, y: size.height - (RoomScene.bar + 1) * s), in: size, minimised: false), .body)
        }
    }

    func testOrbOnlyTakesClicksInsideItsDisc() {
        let size = CGSize(width: 56, height: 56)
        XCTAssertEqual(WindowChrome.hit(CGPoint(x: 28, y: 28), in: size, minimised: true), .restore)
        XCTAssertEqual(WindowChrome.hit(CGPoint(x: 28, y: 1), in: size, minimised: true), .restore)
        for corner in [CGPoint(x: 2, y: 2), CGPoint(x: 54, y: 2), CGPoint(x: 2, y: 54), CGPoint(x: 54, y: 54)] {
            XCTAssertEqual(WindowChrome.hit(corner, in: size, minimised: true), .outside)
        }
        XCTAssertTrue(WindowChrome.inOrb(CGPoint(x: 28 + 19, y: 28 + 19), size: size))
        XCTAssertFalse(WindowChrome.inOrb(CGPoint(x: 28 + 21, y: 28 + 21), size: size))
    }

    func testTooltip() {
        XCTAssertEqual(WindowChrome.tooltip(label: "zipdemand", state: .working, waitingForPermission: false, summary: "Fixing the lookup"),
                       "zipdemand: working\nFixing the lookup")
        XCTAssertEqual(WindowChrome.tooltip(label: "zipdemand", state: .alert, waitingForPermission: true, summary: ""),
                       "zipdemand: waiting for permission")
    }

    // MARK: connectors

    func testColumnConnectsTopAndBottom() {
        let frames = (0..<3).map { CGRect(x: 100, y: 12 + CGFloat($0) * 216, width: 384, height: 216) }
        XCTAssertEqual(Connectors.edges(frames), [[.top], [.top, .bottom], [.bottom]])
    }

    func testRowConnectsLeftAndRight() {
        let frames = (0..<2).map { CGRect(x: 12 + CGFloat($0) * 384, y: 12, width: 384, height: 216) }
        XCTAssertEqual(Connectors.edges(frames), [[.right], [.left]])
    }

    func testGapOffsetOrDifferentSizeDoesNotConnect() {
        let a = CGRect(x: 0, y: 0, width: 384, height: 216)
        XCTAssertEqual(Connectors.edges([a, a.offsetBy(dx: 0, dy: 224)]), [[], []], "a gap")
        XCTAssertEqual(Connectors.edges([a, a.offsetBy(dx: 40, dy: 216)]), [[], []], "out of line")
        XCTAssertEqual(Connectors.edges([a, CGRect(x: 0, y: 216, width: 288, height: 162)]), [[], []], "another scale")
        XCTAssertEqual(Connectors.edges([a]), [[]])
        XCTAssertEqual(Connectors.edges([]), [])
    }

    func testConnectorsFollowTheLayout() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1079)
        // Chamber, orb, chamber: the orb moves to the far end, so the two chambers join.
        let mixed = DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: [false, true, false])
        let frames = DockLayout().solve(area: screen, stacks: [mixed])[.bottomRight]!.frames
        XCTAssertEqual(Connectors.edges([frames[0], frames[2]]), [[.top], [.bottom]])

        // A wrapped stack is a block: the corner chamber gains a tunnel to the second line.
        let block = DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: Array(repeating: false, count: 12))
        let grid = DockLayout().solve(area: screen, stacks: [block])[.bottomRight]!.frames
        XCTAssertEqual(Connectors.edges(grid)[0], [.top, .left])

        // Two stacks never join: the solver keeps them apart.
        let two = DockLayout().solve(area: screen, stacks: [
            DockLayout.Stack(corner: .bottomRight, axis: .vertical, minimised: [false, false, false]),
            DockLayout.Stack(corner: .topRight, axis: .vertical, minimised: [false, false, false]),
        ])
        let all = two[.bottomRight]!.frames + two[.topRight]!.frames
        XCTAssertEqual(Connectors.edges(all)[2], [.bottom])
        XCTAssertEqual(Connectors.edges(all)[5], [.top], "the top stack grows downward, so its last chamber has one above")
    }

    // MARK: close and undo

    private func agent(_ label: String, order: Int, folder: String = "/tmp", scene: String? = nil) -> Persistence.SavedAgent {
        Persistence.SavedAgent(folder: folder, label: label, sessionID: "s-\(label)", corner: 0, order: order,
                               minimised: false, display: 1, scene: scene)
    }

    func testOnlyBusyAgentsAskBeforeClosing() {
        for state in [AgentState.idle, .done, .sleeping] {
            XCTAssertFalse(CloseUndo.needsConfirmation(state: state, hasPending: false, turnInProgress: false))
        }
        for state in [AgentState.thinking, .working, .talking, .alert] {
            XCTAssertTrue(CloseUndo.needsConfirmation(state: state, hasPending: false, turnInProgress: false))
        }
        XCTAssertTrue(CloseUndo.needsConfirmation(state: .idle, hasPending: true, turnInProgress: false))
        XCTAssertTrue(CloseUndo.needsConfirmation(state: .idle, hasPending: false, turnInProgress: true))
    }

    func testUndoWithinTheWindowReturnsAgentsInStackOrder() {
        var undo = CloseUndo()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        undo.closed([agent("b", order: 2), agent("a", order: 0)], at: t0)
        XCTAssertEqual(undo.held.count, 2, "still saved while undo is on offer")
        XCTAssertEqual(undo.undo(at: t0.addingTimeInterval(5.9)).map(\.label), ["a", "b"])
        XCTAssertTrue(undo.held.isEmpty)
        XCTAssertFalse(undo.expire(), "nothing left to make final")
    }

    func testUndoAfterTheWindowDoesNothing() {
        var undo = CloseUndo()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        undo.closed([agent("a", order: 0)], at: t0)
        XCTAssertEqual(undo.undo(at: t0.addingTimeInterval(6.1)), [])
        XCTAssertTrue(undo.held.isEmpty)
    }

    func testExpiryMakesTheCloseFinalOnce() {
        var undo = CloseUndo()
        undo.closed([agent("a", order: 0)], at: Date())
        XCTAssertTrue(undo.expire())
        XCTAssertTrue(undo.held.isEmpty)
        XCTAssertFalse(undo.expire())
    }

    func testASecondCloseMakesTheFirstFinal() {
        var undo = CloseUndo()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        undo.closed([agent("a", order: 0)], at: t0)
        undo.closed([agent("b", order: 0)], at: t0.addingTimeInterval(4))
        XCTAssertEqual(undo.held.map(\.label), ["b"])
        XCTAssertEqual(undo.undo(at: t0.addingTimeInterval(9)).map(\.label), ["b"], "the window restarts with the newer close")
    }

    // MARK: persistence

    func testClosedAgentsStaySavedInPlaceUntilFinal() {
        let open = [agent("a", order: 0), agent("c", order: 1)]
        let merged = Persistence.merge(open: open, closed: [agent("b", order: 1), agent("demo", order: 0, folder: "")])
        XCTAssertEqual(merged.map(\.label), ["a", "b", "c"])
        XCTAssertEqual(merged.map(\.order), [0, 1, 2])
        XCTAssertEqual(Persistence.merge(open: open, closed: []), open)
    }

    func testSceneRoundTripsAndOldFilesStillLoad() throws {
        let state = Persistence.SavedState(agents: [agent("a", order: 0, scene: "bakery")], axes: [])
        let decoded = try JSONDecoder().decode(Persistence.SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.agents[0].scene, "bakery")

        let old = #"{"version":1,"axes":[],"agents":[{"folder":"/tmp","label":"a","corner":0,"order":0,"minimised":true}]}"#
        let legacy = try JSONDecoder().decode(Persistence.SavedState.self, from: Data(old.utf8))
        XCTAssertNil(legacy.agents[0].scene)
        XCTAssertTrue(legacy.agents[0].minimised)
    }

    // MARK: scene choice for new agents

    func testNewAgentScene() {
        let choices = ["workshop", "bakery", "distillery"]
        XCTAssertEqual((0..<4).map { ScenePrefs.scene(forNew: $0, choices: choices, preference: nil) }, ["workshop", "bakery", "distillery", "workshop"])
        XCTAssertEqual(ScenePrefs.scene(forNew: 2, choices: choices, preference: ScenePrefs.rotate), "distillery")
        XCTAssertEqual(ScenePrefs.scene(forNew: 2, choices: choices, preference: "bakery"), "bakery")
        XCTAssertEqual(ScenePrefs.scene(forNew: 1, choices: choices, preference: "gone"), "bakery", "an unknown scene falls back to rotating")
        XCTAssertNil(ScenePrefs.scene(forNew: 0, choices: [], preference: "bakery"))
    }
}
