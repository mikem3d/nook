import XCTest
@testable import Nook

final class HotspotTests: XCTestCase {
    private let board = HotspotArea(id: "tasks", name: "Task board", rect: CGRect(x: 64, y: 31, width: 20, height: 20))
    private let almanac = HotspotArea(id: "calendar", name: "Calendar", rect: CGRect(x: 119, y: 34, width: 15, height: 16))

    // MARK: hit testing

    func testHitScalesWithTheWindow() {
        for s in [1.0, 1.5, 2.0] as [CGFloat] {
            let areas = [board, almanac]
            XCTAssertEqual(HotspotHit.hotspot(at: CGPoint(x: 70 * s, y: 40 * s), scale: s, in: areas), "tasks")
            XCTAssertEqual(HotspotHit.hotspot(at: CGPoint(x: 120 * s, y: 35 * s), scale: s, in: areas), "calendar")
            XCTAssertNil(HotspotHit.hotspot(at: CGPoint(x: 100 * s, y: 40 * s), scale: s, in: areas), "the character is not a hotspot")
            XCTAssertNil(HotspotHit.hotspot(at: CGPoint(x: 63.5 * s, y: 40 * s), scale: s, in: areas), "just left of the board")
            XCTAssertEqual(HotspotHit.hotspot(at: CGPoint(x: 64 * s, y: 31 * s), scale: s, in: areas), "tasks", "its bottom-left pixel")
        }
        XCTAssertNil(HotspotHit.hotspot(at: CGPoint(x: 70, y: 40), scale: 0, in: [board]))
    }

    func testFrontMostHotspotWinsAnOverlap() {
        let behind = HotspotArea(id: "behind", name: "", rect: CGRect(x: 60, y: 30, width: 30, height: 30))
        XCTAssertEqual(HotspotHit.hotspot(at: CGPoint(x: 70, y: 40), scale: 1, in: [board, behind]), "tasks")
        XCTAssertEqual(HotspotHit.hotspot(at: CGPoint(x: 70, y: 40), scale: 1, in: [behind, board]), "behind")
        XCTAssertEqual(HotspotHit.hotspot(at: CGPoint(x: 61, y: 40), scale: 1, in: [board, behind]), "behind")
    }

    func testHeaderButtonsBeatAHotspotUnderThem() {
        let s: CGFloat = 2
        let size = CGSize(width: RoomScene.W * s, height: RoomScene.H * s)
        // A badly placed hotspot covering the whole top right, header included.
        let stray = HotspotArea(id: "stray", name: "", rect: CGRect(x: 150, y: 80, width: 42, height: 28))
        func target(_ x: CGFloat, _ y: CGFloat, minimised: Bool = false, dimmed: Bool = false) -> HotspotHit.Target {
            HotspotHit.target(CGPoint(x: x * s, y: y * s), in: size, minimised: minimised, dimmed: dimmed, areas: [stray, board])
        }
        XCTAssertEqual(target(188, 104), .chrome(.close))
        XCTAssertEqual(target(174, 104), .chrome(.minimise))
        XCTAssertEqual(target(155, 104), .chrome(.body), "the rest of the header is the window's, never a hotspot's")
        XCTAssertEqual(target(155, 90), .hotspot("stray"), "below the header it is a hotspot again")
        XCTAssertEqual(target(70, 40), .hotspot("tasks"))
        XCTAssertEqual(target(100, 40), .chrome(.body))
    }

    func testHotspotsAreInertWhenDimmedOrAnOrb() {
        let size = CGSize(width: RoomScene.W * 2, height: RoomScene.H * 2)
        let point = CGPoint(x: 140, y: 80)
        XCTAssertEqual(HotspotHit.target(point, in: size, minimised: false, dimmed: false, areas: [board]), .hotspot("tasks"))
        XCTAssertEqual(HotspotHit.target(point, in: size, minimised: false, dimmed: true, areas: [board]), .chrome(.body),
                       "a click on a dimmed window activates it, as before")
        let orb = CGSize(width: 56, height: 56)
        XCTAssertEqual(HotspotHit.target(CGPoint(x: 28, y: 28), in: orb, minimised: true, dimmed: false,
                                         areas: [HotspotArea(id: "x", name: "", rect: CGRect(x: 0, y: 0, width: 28, height: 28))]), .chrome(.restore))
    }

    // MARK: the bundled theme

    func testEveryDwarfSceneHasBothHotspotsClearOfEverythingElse() throws {
        let art = try Art()
        let specs = try XCTUnwrap(art.theme.hotspots)
        XCTAssertEqual(Set(specs.map(\.id)), ["tasks", "calendar"])
        for spec in specs {
            let sheet = try art.texture(spec.sheet)
            XCTAssertEqual(sheet.size(), CGSize(width: spec.frame[0] * spec.levels, height: spec.frame[1] * 2), "\(spec.id): levels across, idle over hover")
        }
        XCTAssertEqual(specs.first { $0.id == "tasks" }?.levels, 6, "0 to 5 parchments")

        let header = CGRect(x: 0, y: RoomScene.H - RoomScene.bar, width: RoomScene.W, height: RoomScene.bar)
        let ladder = CGRect(x: 12, y: 0, width: 14, height: RoomScene.H)
        let tunnels = [CGRect(x: 0, y: 16, width: 10, height: 30), CGRect(x: 182, y: 16, width: 10, height: 30)]
        let bubble = CGRect(x: 0, y: RoomScene.H - 55, width: RoomScene.W, height: 55) // rows 0..54: header, bubble and its tail
        for choice in art.sceneChoices {
            let scene = try XCTUnwrap(art.scene(choice.id))
            let chamber = ChamberNode(art: art, scene: scene)
            XCTAssertEqual(Set(chamber.areas.map(\.id)), ["tasks", "calendar"], choice.id)
            let feet = scene.feet ?? art.theme.character.feet
            let figure = CGRect(x: feet[0] - 10, y: feet[1], width: 20, height: 32) // the dwarf's pixels within his 32 px frame
            var busy = [header, ladder, bubble, figure] + tunnels
            let props = Dictionary(uniqueKeysWithValues: (art.theme.props ?? []).map { ($0.name, $0) })
            for place in scene.props ?? [] {
                guard let prop = props[place.name] else { continue }
                busy.append(CGRect(x: place.position[0], y: place.position[1], width: CGFloat(prop.frame[0]), height: CGFloat(prop.frame[1])))
            }
            for area in chamber.areas {
                for other in busy { XCTAssertFalse(area.rect.intersects(other), "\(choice.id)/\(area.id) \(area.rect) collides with \(other)") }
                XCTAssertTrue(CGRect(x: 6, y: 18, width: 180, height: 79).contains(area.rect), "\(choice.id)/\(area.id) is inside the chamber")
            }
            XCTAssertFalse(chamber.areas[0].rect.intersects(chamber.areas[1].rect), choice.id)
        }
    }

    func testSceneKeepsHotspotStateAcrossASceneChangeAndHidesAreasInAnOrb() throws {
        let art = try Art()
        let scene = RoomScene(art: art, roomIndex: 0, title: "x")
        XCTAssertEqual(scene.hotspotAreas.count, 2)
        scene.showHotspot("tasks", HotspotState(level: 3, news: true))
        scene.setScene("forge")
        XCTAssertEqual(scene.hotspotAreas.count, 2)
        scene.configure(scale: 2, minimised: true)
        XCTAssertTrue(scene.hotspotAreas.isEmpty, "an orb has no hotspots")
    }

    // MARK: panel placement

    func testPanelGoesBesideTheWindowOnTheSideWithRoom() {
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 400, height: 560)
        let right = CGRect(x: 1044, y: 12, width: 384, height: 216) // docked bottom right
        var frame = PanelPlacement.frame(size: size, beside: right, in: area)
        XCTAssertEqual(frame.maxX, right.minX - 8)
        XCTAssertEqual(frame.minY, 0, "clamped to the screen: the panel is taller than the window's top allows")
        let left = CGRect(x: 12, y: 600, width: 384, height: 216)
        frame = PanelPlacement.frame(size: size, beside: left, in: area)
        XCTAssertEqual(frame.minX, left.maxX + 8)
        XCTAssertEqual(frame.maxY, left.maxY, "tops level")
        // No room either side: above or below, whichever is roomier, and always on screen.
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 900)
        frame = PanelPlacement.frame(size: size, beside: CGRect(x: 108, y: 12, width: 384, height: 216), in: narrow)
        XCTAssertEqual(frame.minY, 236)
        XCTAssertTrue(narrow.contains(frame))
        frame = PanelPlacement.frame(size: size, beside: CGRect(x: 108, y: 672, width: 384, height: 216), in: narrow)
        XCTAssertEqual(frame.maxY, 664)
    }

    // MARK: the agent's plan

    func testTodoWriteReplacesThePlanAndToleratesJunk() {
        var plan = AgentPlan()
        XCTAssertTrue(plan.toolUse(id: "a", name: "TodoWrite", input: ["todos": [
            ["content": "Write tests", "status": "in_progress", "activeForm": "Writing tests"],
            ["content": "Ship", "status": "pending", "activeForm": "Shipping"],
            ["content": "", "status": "pending"], ["status": "completed"],
            ["content": "Odd", "status": "blocked"]]]))
        XCTAssertEqual(plan.todos.map(\.content), ["Write tests", "Ship", "Odd"])
        XCTAssertEqual(plan.todos.map(\.status), [.inProgress, .pending, .pending])
        XCTAssertEqual(plan.todos[0].activeForm, "Writing tests")
        XCTAssertEqual(plan.todos[2].activeForm, "Odd", "falls back to the content")
        XCTAssertFalse(plan.toolUse(id: "b", name: "TodoWrite", input: ["todos": "nonsense"]), "a malformed call does not wipe the plan")
        XCTAssertFalse(plan.toolUse(id: "c", name: "Bash", input: ["command": "ls"]))
        XCTAssertEqual(plan.todos.count, 3)
        XCTAssertTrue(plan.toolUse(id: "d", name: "TodoWrite", input: ["todos": [[String: Any]]()]))
        XCTAssertTrue(plan.todos.isEmpty)
    }

    /// The shapes below are copied from a live Claude Code 2.1.277 run.
    func testTaskCreateAndUpdateFollowTheirResults() {
        var plan = AgentPlan()
        XCTAssertFalse(plan.toolUse(id: "u1", name: "TaskCreate", input: ["subject": "Alpha", "description": "First tiny step", "activeForm": "Doing alpha"]))
        XCTAssertTrue(plan.todos.isEmpty, "nothing until the CLI confirms it, with the id")
        XCTAssertTrue(plan.toolResult(id: "u1", result: ["task": ["id": "1", "subject": "Alpha"]]))
        _ = plan.toolUse(id: "u2", name: "TaskCreate", input: ["subject": "Beta", "description": "Second"])
        XCTAssertTrue(plan.toolResult(id: "u2", result: ["task": ["id": "2", "subject": "Beta"]]))
        XCTAssertEqual(plan.todos.map(\.content), ["Alpha", "Beta"])
        XCTAssertEqual(plan.todos[0].activeForm, "Doing alpha")

        _ = plan.toolUse(id: "u3", name: "TaskUpdate", input: ["taskId": "1", "status": "in_progress"])
        XCTAssertTrue(plan.toolResult(id: "u3", result: ["success": true, "taskId": "1", "updatedFields": ["status"],
                                                          "statusChange": ["from": "pending", "to": "in_progress"]]))
        XCTAssertEqual(plan.todos[0].status, .inProgress)
        _ = plan.toolUse(id: "u4", name: "TaskUpdate", input: ["taskId": "1", "status": "completed"])
        XCTAssertFalse(plan.toolResult(id: "u4", result: ["success": false, "taskId": "1"]), "a failed update changes nothing")
        XCTAssertEqual(plan.todos[0].status, .inProgress)
        _ = plan.toolUse(id: "u5", name: "TaskUpdate", input: ["taskId": "2", "status": "deleted"])
        XCTAssertTrue(plan.toolResult(id: "u5", result: ["success": true, "taskId": "2"]))
        XCTAssertEqual(plan.todos.map(\.content), ["Alpha"])
        _ = plan.toolUse(id: "u6", name: "TaskUpdate", input: ["taskId": "9", "status": "completed"])
        XCTAssertFalse(plan.toolResult(id: "u6", result: ["success": true, "taskId": "9"]), "an unknown task is ignored")
        XCTAssertFalse(plan.toolResult(id: "never-asked", result: ["task": ["id": "3", "subject": "Ghost"]]))
    }

    // MARK: the user's queue and auto mode

    func testQueueSendsFromTheTopAndFilesResults() {
        var queue = TaskQueue()
        queue.add("  first  ")
        queue.add("")
        queue.add("second")
        XCTAssertEqual(queue.queued.map(\.text), ["first", "second"])
        XCTAssertEqual(queue.open, 2)
        let sent = queue.takeNext(automatic: true)
        XCTAssertEqual(sent?.text, "first")
        XCTAssertNil(queue.takeNext(automatic: true), "one at a time")
        XCTAssertEqual(queue.open, 2, "a task with the agent is still open")
        queue.finish(summary: "3 files changed", failed: false, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(queue.done.first?.summary, "3 files changed")
        XCTAssertEqual(queue.done.first?.automatic, true)
        XCTAssertTrue(queue.unseen, "the wax seal")
        XCTAssertNil(queue.sending)
        queue.finish(summary: "again", failed: false, at: Date())
        XCTAssertEqual(queue.done.count, 1, "nothing out, nothing to file")
        for n in 0..<(TaskQueue.doneLimit + 5) {
            queue.add("t\(n)")
            _ = queue.takeNext(automatic: false)
            queue.finish(summary: "", failed: false, at: Date())
        }
        XCTAssertEqual(queue.done.count, TaskQueue.doneLimit)
    }

    func testAutoModeNeverSendsInDoubt() {
        func decide(auto: Bool = true, queued: Int = 2, free: Bool = true, permission: Bool = false, outstanding: Bool = false,
                    failed: Bool = false, sent: Int = 0, limit: Int = 5) -> AutoRun.Decision {
            AutoRun.decide(auto: auto, queued: queued, free: free, waitingForPermission: permission, outstanding: outstanding,
                           lastTurnFailed: failed, sentThisRun: sent, limit: limit)
        }
        XCTAssertEqual(decide(), .send)
        XCTAssertEqual(decide(auto: false), .wait, "off by default means off")
        XCTAssertEqual(decide(queued: 0), .wait)
        XCTAssertEqual(decide(free: false), .wait, "mid-turn")
        XCTAssertEqual(decide(permission: true), .wait, "never while a permission question is open")
        XCTAssertEqual(decide(outstanding: true), .wait)
        XCTAssertEqual(decide(sent: 4), .send)
        if case .stop = decide(sent: 5) {} else { XCTFail("stops at the limit so a queue cannot run away") }
        if case .stop = decide(failed: true) {} else { XCTFail("stops after a failed turn") }
        XCTAssertEqual(decide(permission: true, failed: true), .wait, "a stop is only announced once the agent is free")
    }

    // MARK: persistence

    func testStoresRoundTripPerAgentFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-hotspots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HotspotStore<TaskQueue>(name: "tasks.json", folder: folder) { TaskQueue() }
        XCTAssertEqual(store["/work/a"], TaskQueue())
        XCTAssertTrue(store.update("/work/a") { $0.add("ship it") })
        XCTAssertFalse(store.update("/work/a") { _ in }, "no change, no write")
        store.update("/work/b") { $0.add("other") }
        let again = HotspotStore<TaskQueue>(name: "tasks.json", folder: folder) { TaskQueue() }
        XCTAssertEqual(again["/work/a"].queued.map(\.text), ["ship it"])
        XCTAssertEqual(Set(again.keys), ["/work/a", "/work/b"])
        again.update("/work/b") { $0.queued.removeAll() }
        XCTAssertEqual(HotspotStore<TaskQueue>(name: "tasks.json", folder: folder) { TaskQueue() }.keys, ["/work/a"], "empty queues are not kept")

        let calendars = HotspotStore<AgentCalendar>(name: "schedule.json", folder: folder) { AgentCalendar() }
        let item = AgentCalendar.Item(prompt: "Run the tests", checkedUntil: Date(timeIntervalSince1970: 1_800_000_000))
        calendars.update("/work/a") { $0.items.append(item) }
        let reloaded = HotspotStore<AgentCalendar>(name: "schedule.json", folder: folder) { AgentCalendar() }
        XCTAssertEqual(reloaded["/work/a"].items, [item])
    }
}
