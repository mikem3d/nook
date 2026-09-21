import XCTest
@testable import Nook

final class TaskBoardTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Monday 21 September 2026, 10:00.
    private var now: Date { date(2026, 9, 21, 10) }

    // MARK: quick add

    func testQuickAddReadsTheExampleLine() {
        let agents = [QuickAdd.AgentName(key: "/work/sternfall", label: "sternfall"), .init(key: "/work/zipdemand", label: "zipdemand")]
        let parsed = QuickAdd.parse("fix the login bug @zipdemand !high due fri #auth", agents: agents, now: now, calendar: calendar)
        XCTAssertEqual(parsed, QuickAdd(title: "fix the login bug", agent: "/work/zipdemand", priority: .high, due: date(2026, 9, 25), dueHasTime: false, tags: ["auth"]))
    }

    func testQuickAddMarksCanGoAnywhereAndJunkStaysInTheTitle() {
        let agents = [QuickAdd.AgentName(key: "/z", label: "zipdemand")]
        var parsed = QuickAdd.parse("  #UI !urgent  tidy   the header #ui #Nav @zip ", agents: agents, now: now, calendar: calendar)
        XCTAssertEqual(parsed, QuickAdd(title: "tidy the header", agent: "/z", priority: .urgent, tags: ["ui", "nav"]))
        parsed = QuickAdd.parse("email bob@example.com about what is due !soon @nobody # !", agents: agents, now: now, calendar: calendar)
        XCTAssertEqual(parsed, QuickAdd(title: "email bob@example.com about what is due !soon @nobody # !"))
        XCTAssertEqual(QuickAdd.parse("   ", agents: agents, now: now, calendar: calendar).title, "")
        XCTAssertEqual(QuickAdd.parse("ship !m", agents: [], now: now, calendar: calendar).priority, .medium)
        XCTAssertEqual(QuickAdd.parse("ship !l !h", agents: [], now: now, calendar: calendar).priority, .high, "the last one wins")
    }

    func testAgentsMatchLoosely() {
        let agents = [QuickAdd.AgentName(key: "1", label: "zipdemand-api"), .init(key: "2", label: "zipdemand"), .init(key: "3", label: "Iron Pachyderm"),
                      .init(key: "4", label: "api")]
        XCTAssertEqual(QuickAdd.match("ZIPDEMAND", in: agents), "2", "exact beats prefix")
        XCTAssertEqual(QuickAdd.match("zip", in: agents), "2", "the shorter of two prefixes")
        XCTAssertEqual(QuickAdd.match("api", in: agents), "4")
        XCTAssertEqual(QuickAdd.match("demand-", in: agents), "1", "substring")
        XCTAssertEqual(QuickAdd.match("pachy", in: agents), "3")
        XCTAssertEqual(QuickAdd.match("irnp", in: agents), "3", "letters in order")
        XCTAssertNil(QuickAdd.match("sternfall", in: agents))
        XCTAssertNil(QuickAdd.match("", in: agents))
    }

    func testDueDates() {
        func due(_ text: String) -> (Date?, Bool, String) {
            let parsed = QuickAdd.parse("x due \(text) y", agents: [], now: now, calendar: calendar)
            return (parsed.due, parsed.dueHasTime, parsed.title)
        }
        func check(_ text: String, _ expected: Date, time: Bool = false, line: UInt = #line) {
            let (date, hasTime, title) = due(text)
            XCTAssertEqual(date, expected, text, line: line)
            XCTAssertEqual(hasTime, time, text, line: line)
            XCTAssertEqual(title, "x y", text, line: line)
        }
        check("today", date(2026, 9, 21))
        check("tomorrow", date(2026, 9, 22))
        check("tmrw 9:30am", date(2026, 9, 22, 9, 30), time: true)
        check("fri", date(2026, 9, 25))
        check("Friday 3pm", date(2026, 9, 25, 15), time: true)
        check("mon", date(2026, 9, 28)) // today's weekday means next week's
        check("thurs", date(2026, 9, 24))
        check("next fri", date(2026, 10, 2))
        check("in 3d", date(2026, 9, 24))
        check("in 3 days", date(2026, 9, 24))
        check("in 2 weeks", date(2026, 10, 5))
        check("in 1 month", date(2026, 10, 21))
        check("in 4h", date(2026, 9, 21, 14), time: true)
        check("2026-10-01", date(2026, 10, 1))
        check("2026-10-01 15:00", date(2026, 10, 1, 15), time: true)
        check("10/1", date(2026, 10, 1))
        check("1/5", date(2027, 1, 5)) // a date already past this year is next year's
        check("12/24/26", date(2026, 12, 24))
        check("oct 1", date(2026, 10, 1))
        check("1 October 12pm", date(2026, 10, 1, 12), time: true)
        check("9/21", date(2026, 9, 21)) // today is not past

        XCTAssertEqual(QuickAdd.parse("x due:fri y", agents: [], now: now, calendar: calendar).due, date(2026, 9, 25))
        XCTAssertEqual(QuickAdd.parse("x due: fri y", agents: [], now: now, calendar: calendar).title, "x y")
        for junk in ["someday", "2/30", "13/1", "in 0d", "in 5 minutes", "fr", "25pm"] {
            let (date, _, title) = due(junk)
            XCTAssertNil(date, junk)
            XCTAssertEqual(title, "x due \(junk) y", "nothing typed is lost")
        }
        let (friday, hasTime, title) = due("fri 7")
        XCTAssertEqual(friday, date(2026, 9, 25))
        XCTAssertFalse(hasTime, "a bare number is not a time")
        XCTAssertEqual(title, "x 7 y")
        XCTAssertNil(QuickAdd.parse("pay what is due", agents: [], now: now, calendar: calendar).due)
    }

    func testTimes() {
        XCTAssertEqual(QuickAdd.time("12am")?.0, 0)
        XCTAssertEqual(QuickAdd.time("12pm")?.0, 12)
        XCTAssertEqual(QuickAdd.time("11:59pm")?.0, 23)
        XCTAssertEqual(QuickAdd.time("23:05")?.1, 5)
        for junk in ["24:00", "13pm", "0am", "9:60", "9", "pm", "9:3:1", nil] { XCTAssertNil(QuickAdd.time(junk), junk ?? "nil") }
    }

    // MARK: due dates

    func testOverdueAndDueToday() {
        var task = NookTask(title: "t", due: date(2026, 9, 21), dueHasTime: false)
        XCTAssertTrue(task.isDueToday(at: now, calendar: calendar))
        XCTAssertFalse(task.isOverdue(at: date(2026, 9, 21, 23, 59), calendar: calendar), "a day is due by its end")
        XCTAssertTrue(task.isOverdue(at: date(2026, 9, 22), calendar: calendar))
        XCTAssertFalse(task.isDueToday(at: date(2026, 9, 22), calendar: calendar), "overdue is not also due today")
        task = NookTask(title: "t", due: date(2026, 9, 21, 15), dueHasTime: true)
        XCTAssertTrue(task.isDueToday(at: now, calendar: calendar))
        XCTAssertTrue(task.isOverdue(at: date(2026, 9, 21, 15), calendar: calendar))
        task.status = .done
        XCTAssertFalse(task.isOverdue(at: date(2026, 9, 30), calendar: calendar), "finished work is never overdue")
        XCTAssertFalse(NookTask(title: "no date").isOverdue(at: now, calendar: calendar))
    }

    func testDueSoonAndNews() {
        let late = NookTask(title: "late", due: date(2026, 9, 18), agent: "/a")
        let today = NookTask(title: "today", due: date(2026, 9, 21, 18), dueHasTime: true, agent: "/a")
        let nextWeek = NookTask(title: "next week", due: date(2026, 9, 28), agent: "/a")
        let doneLate = NookTask(title: "done", due: date(2026, 9, 1), agent: "/a", status: .done, finished: date(2026, 9, 2))
        let tasks = [nextWeek, today, NookTask(title: "undated"), late, doneLate]
        XCTAssertEqual(tasks.dueSoon(now: now, horizon: now.addingTimeInterval(86_400), calendar: calendar).map(\.title), ["late", "today"])

        // "late" went overdue at the start of the 19th.
        XCTAssertTrue(tasks.hasNews(for: "/a", since: date(2026, 9, 18, 12), now: now, calendar: calendar), "it went overdue since the board was opened")
        XCTAssertFalse(tasks.hasNews(for: "/a", since: date(2026, 9, 20), now: now, calendar: calendar), "seen since")
        XCTAssertFalse(tasks.hasNews(for: "/b", since: .distantPast, now: now, calendar: calendar), "another agent's")
        XCTAssertTrue(tasks.hasNews(for: "/a", since: date(2026, 9, 20), now: date(2026, 9, 21, 18), calendar: calendar), "the timed one just went overdue")
        XCTAssertTrue(tasks.hasNews(for: "/a", since: date(2026, 9, 1, 12), now: date(2026, 9, 10), calendar: calendar), "a task came back")
    }

    // MARK: the list's rules

    func testCyclesAreRefusedAtEditTime() {
        let a = NookTask(title: "a")
        var b = NookTask(title: "b")
        var c = NookTask(title: "c")
        b.after = [a.id]
        c.after = [b.id]
        var tasks = [a, b, c]
        XCTAssertTrue(tasks.wouldCycle(a.id, waitingOn: a.id), "itself")
        XCTAssertTrue(tasks.wouldCycle(a.id, waitingOn: b.id))
        XCTAssertTrue(tasks.wouldCycle(a.id, waitingOn: c.id), "through the chain")
        XCTAssertFalse(tasks.wouldCycle(c.id, waitingOn: a.id), "a diamond is not a loop")
        XCTAssertFalse(tasks.setPrerequisites([c.id], of: a.id))
        XCTAssertEqual(tasks[0].after, [], "a refused edit changes nothing")
        XCTAssertTrue(tasks.setPrerequisites([a.id, b.id, a.id], of: c.id))
        XCTAssertEqual(tasks[2].after, [a.id, b.id])
        XCTAssertFalse(tasks.setPrerequisites([], of: UUID()))
        // A loop already in a damaged file does not hang the check.
        tasks[0].after = [c.id]
        XCTAssertTrue(tasks.wouldCycle(UUID(), waitingOn: a.id) == false)
    }

    func testCancelRemoveRequeueAndFinish() {
        let t = date(2026, 9, 21)
        var tasks = [NookTask(title: "queued"), NookTask(title: "out", agent: "/a", status: .running), NookTask(title: "done", status: .done),
                     NookTask(title: "failed", status: .failed)]
        tasks.append(NookTask(title: "after done", after: [tasks[2].id]))
        tasks.append(NookTask(title: "after failed", after: [tasks[3].id]))
        let ids = tasks.map(\.id)

        XCTAssertTrue(tasks.cancelOrRemove(ids[0], at: t))
        XCTAssertEqual(tasks[0].status, .cancelled)
        XCTAssertFalse(tasks.cancelOrRemove(ids[1], at: t), "a turn cannot be taken back")
        XCTAssertTrue(tasks.cancelOrRemove(ids[2], at: t))
        XCTAssertNil(tasks.task(ids[2]))
        XCTAssertEqual(tasks.task(ids[4])?.after, [], "its dependant goes on without it")
        XCTAssertTrue(tasks.cancelOrRemove(ids[3], at: t))
        XCTAssertEqual(tasks.blocker(of: tasks.task(ids[5])!), .missing, "deleting a failure does not step over it")
        XCTAssertFalse(tasks.cancelOrRemove(UUID(), at: t))

        tasks.requeue(ids[0])
        XCTAssertEqual(tasks[0].status, .queued)
        XCTAssertNil(tasks[0].finished)
        tasks.finish(ids[1], summary: "ok", failed: false, at: t)
        XCTAssertEqual(tasks.task(ids[1])?.status, .done)
        XCTAssertEqual(tasks.task(ids[1])?.result, "ok")
        tasks.finish(ids[0], summary: "never sent", failed: true, at: t)
        XCTAssertEqual(tasks[0].status, .queued, "only a task that is out can finish")
    }

    func testReorderKeepsOtherTasksInPlace() {
        var tasks = ["a", "x", "b", "c"].map { NookTask(title: $0, agent: $0 == "x" ? "/other" : "/a") }
        tasks.reorder([tasks[3].id, tasks[0].id, tasks[2].id])
        XCTAssertEqual(tasks.map(\.title), ["c", "x", "a", "b"])
        tasks.reorder([UUID()])
        XCTAssertEqual(tasks.map(\.title), ["c", "x", "a", "b"])
    }

    func testTrimKeepsWhatOpenWorkWaitsOn() {
        var tasks = (0..<8).map { NookTask(title: "done \($0)", agent: "/a", status: .done, finished: Date(timeIntervalSince1970: TimeInterval($0))) }
        let oldest = tasks[0]
        tasks.append(NookTask(title: "waits", agent: "/b", after: [oldest.id]))
        tasks.append(NookTask(title: "other agent's", agent: "/b", status: .failed, finished: Date(timeIntervalSince1970: 0)))
        tasks.trimFinished(limit: 3)
        XCTAssertEqual(tasks.map(\.title), ["done 0", "done 5", "done 6", "done 7", "waits", "other agent's"])
    }

    func testFilter() {
        let tasks = [NookTask(title: "a", priority: .high, tags: ["ui"]), NookTask(title: "b", status: .done), NookTask(title: "c", priority: .low, status: .running)]
        func shown(_ filter: TaskFilter) -> [String] { tasks.filter(filter.matches).map(\.title) }
        XCTAssertEqual(shown(TaskFilter()), ["a", "c"], "open work by default")
        XCTAssertEqual(shown(TaskFilter(show: .all)), ["a", "b", "c"])
        XCTAssertEqual(shown(TaskFilter(show: .only(.done))), ["b"])
        XCTAssertEqual(shown(TaskFilter(priority: .medium)), ["a"])
        XCTAssertEqual(shown(TaskFilter(show: .all, tag: "ui")), ["a"])
    }

    // MARK: the hub's layout

    func testColumnsAndKeyboardMoves() {
        let agents = [HubAgent(key: "/a", label: "a", state: .idle), HubAgent(key: "/b", label: "b")]
        let tasks = [NookTask(title: "in"), NookTask(title: "a1", agent: "/a"), NookTask(title: "a2", priority: .urgent, agent: "/a"),
                     NookTask(title: "stray", agent: "/gone"), NookTask(title: "finished", agent: "/b", status: .done)]
        var columns = HubLayout.columns(tasks: tasks, agents: agents, filter: TaskFilter())
        XCTAssertEqual(columns.map { $0.tasks.map(\.title) }, [["in", "stray"], ["a2", "a1"], []])
        XCTAssertEqual(columns.map(\.agent?.key), [nil, "/a", "/b"])
        columns = HubLayout.columns(tasks: tasks, agents: agents, filter: TaskFilter(show: .all))
        XCTAssertEqual(columns[2].tasks.map(\.title), ["finished"])

        let (a, b, c, d, e) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let grid = [[a, b, c], [], [d], [e]]
        XCTAssertEqual(HubLayout.move(nil, .down, in: grid), a)
        XCTAssertNil(HubLayout.move(nil, .down, in: [[], []]))
        XCTAssertEqual(HubLayout.move(a, .down, in: grid), b)
        XCTAssertEqual(HubLayout.move(c, .down, in: grid), c, "stops at the end")
        XCTAssertEqual(HubLayout.move(a, .up, in: grid), a)
        XCTAssertEqual(HubLayout.move(c, .right, in: grid), d, "skips the empty column, clamps the row")
        XCTAssertEqual(HubLayout.move(d, .left, in: grid), a)
        XCTAssertEqual(HubLayout.move(e, .right, in: grid), e)
        XCTAssertEqual(HubLayout.move(a, .left, in: grid), a)
        XCTAssertEqual(HubLayout.move(UUID(), .up, in: grid), a, "a selection that was filtered away starts over")
    }

    // MARK: the store

    private func folder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-tasks-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testStoreRoundTripsAndOnlyWritesOnChange() throws {
        let folder = folder()
        let store = TaskStore(folder: folder)
        var task = NookTask(title: "ship", notes: "carefully", priority: .high, due: date(2026, 9, 25), agent: "/a", tags: ["x"])
        task.after = [UUID()]
        XCTAssertTrue(store.edit { $0.append(task) })
        XCTAssertFalse(store.edit { _ in }, "no change, no write")
        store.markSeen("/a", at: now)
        let again = TaskStore(folder: folder)
        XCTAssertEqual(again.tasks, [task])
        XCTAssertEqual(again.seen("/a"), now)
        XCTAssertEqual(again.seen("/b"), .distantPast)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("tasks.json"))) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
    }

    func testStoreSaysWhatChanged() {
        let store = TaskStore(folder: folder())
        var changed: [(String, Bool)] = []
        var finished: [NookTask] = []
        var batches = 0
        let centre = NotificationCenter.default
        let observers = [
            centre.addObserver(forName: .nookTaskChanged, object: store, queue: nil) { note in
                if let task = note.userInfo?["task"] as? NookTask { changed.append((task.title, note.userInfo?["removed"] as? Bool ?? false)) }
            },
            centre.addObserver(forName: .nookTaskFinished, object: store, queue: nil) { note in
                if let task = note.userInfo?["task"] as? NookTask { finished.append(task) }
            },
            centre.addObserver(forName: TaskStore.changed, object: store, queue: nil) { _ in batches += 1 },
        ]
        defer { observers.forEach(centre.removeObserver) }

        let (one, two) = (NookTask(title: "one", agent: "/a"), NookTask(title: "two", agent: "/a"))
        store.edit { $0 += [one, two] }
        XCTAssertEqual(changed.map(\.0), ["one", "two"])
        XCTAssertEqual(batches, 1)
        changed = []
        store.edit { $0[0].status = .running }
        store.edit { $0.finish(one.id, summary: "all good", failed: false, at: Date()) }
        XCTAssertEqual(changed.map(\.0), ["one", "one"])
        XCTAssertEqual(finished.map(\.result), ["all good"])
        XCTAssertEqual(finished.first?.status, .done)
        changed = []
        store.edit { $0.cancelOrRemove(two.id, at: Date()) }
        store.edit { $0.cancelOrRemove(two.id, at: Date()) }
        XCTAssertEqual(changed.map(\.1), [false, true], "cancelled, then removed")
        XCTAssertEqual(finished.count, 1, "a cancel is not a finish")
    }

    func testNotificationsCarryPlainFieldsTheNotificationsFeatureCanRead() throws {
        let store = TaskStore(folder: folder())
        let task = NookTask(title: "ship", due: Date(timeIntervalSince1970: 2_000_000_000), dueHasTime: true, agent: "/work/zipdemand")
        var parsed = try XCTUnwrap(DueTasks.parse(store.info(task)))
        XCTAssertEqual(parsed.id, task.id.uuidString)
        XCTAssertEqual(parsed.title, "ship")
        XCTAssertEqual(parsed.agent, "zipdemand")
        XCTAssertEqual(parsed.due, task.due)
        XCTAssertFalse(parsed.done)
        XCTAssertEqual(store.info(task)["task"] as? NookTask, task)
        parsed = try XCTUnwrap(DueTasks.parse(store.info(task, removed: true)))
        XCTAssertTrue(parsed.done, "a removed task is forgotten")
        var day = NookTask(title: "by friday", due: date(2026, 9, 25), status: .cancelled)
        XCTAssertTrue(try XCTUnwrap(DueTasks.parse(store.info(day))).done)
        day.status = .queued
        XCTAssertEqual(store.info(day)["due"] as? Date, day.deadline(), "a day is due by its end, so that is when an alert belongs")
        XCTAssertNil(store.info(day)["agent"])
    }

    func testVersionOneFileMigratesWithABackupAndLosesNothing() throws {
        let folder = folder()
        let file = folder.appendingPathComponent("tasks.json")
        let old = """
        {"version": 1, "agents": {
          "/work/a": {"queued": [{"id": "11111111-1111-1111-1111-111111111111", "text": "first"}, {"id": "22222222-2222-2222-2222-222222222222", "text": "second"}],
                      "sending": {"id": "33333333-3333-3333-3333-333333333333", "text": "out"}, "sentAutomatically": true, "unseen": true,
                      "done": [{"id": "44444444-4444-4444-4444-444444444444", "text": "newest", "finished": 800000000, "summary": "ok", "failed": false, "automatic": true},
                               {"id": "55555555-5555-5555-5555-555555555555", "text": "older", "finished": 700000000, "summary": "boom", "failed": true, "automatic": false}]},
          "/work/b": {"queued": [{"id": "66666666-6666-6666-6666-666666666666", "text": "b's"}], "sentAutomatically": false, "unseen": false, "done": []}}}
        """
        try Data(old.utf8).write(to: file)

        let store = TaskStore(folder: folder, now: now)
        XCTAssertEqual(store.tasks.map(\.title), ["older", "newest", "out", "first", "second", "b's"])
        XCTAssertEqual(store.tasks.map(\.status), [.failed, .done, .sent, .queued, .queued, .queued])
        XCTAssertEqual(store.tasks.map(\.agent), ["/work/a", "/work/a", "/work/a", "/work/a", "/work/a", "/work/b"])
        XCTAssertEqual(store.tasks[3].id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"), "ids survive")
        XCTAssertEqual(store.tasks[0].result, "boom")
        XCTAssertEqual(store.tasks[1].finished, Date(timeIntervalSinceReferenceDate: 800_000_000))
        XCTAssertTrue(store.tasks[1].automatic)
        XCTAssertTrue(store.tasks[2].automatic)
        XCTAssertEqual(store.tasks.ready(for: "/work/a").map(\.title), ["first", "second"], "the queue keeps its order")
        XCTAssertTrue(store.tasks.hasNews(for: "/work/a", since: store.seen("/work/a"), now: now), "the wax seal survives")
        XCTAssertFalse(store.tasks.hasNews(for: "/work/b", since: store.seen("/work/b"), now: now))

        let backup = folder.appendingPathComponent("tasks.v1.backup.json")
        XCTAssertEqual(try Data(contentsOf: backup), Data(old.utf8), "the old file, byte for byte")
        let again = TaskStore(folder: folder)
        XCTAssertEqual(again.tasks, store.tasks, "written forward as version 2; a second launch does not migrate again")
    }

    func testAFileThisBuildCannotReadIsSetAsideNotOverwritten() throws {
        for contents in ["{\"version\": 3, \"tasks\": [], \"seen\": {}, \"extra\": true}", "not json at all"] {
            let folder = folder()
            try Data(contents.utf8).write(to: folder.appendingPathComponent("tasks.json"))
            let store = TaskStore(folder: folder, now: now)
            XCTAssertTrue(store.tasks.isEmpty)
            store.edit { $0.append(NookTask(title: "new")) }
            let copy = folder.appendingPathComponent("tasks.unreadable-\(Int(now.timeIntervalSince1970)).json")
            XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), contents)
        }
    }
}
