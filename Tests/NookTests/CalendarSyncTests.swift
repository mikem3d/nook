import XCTest
@testable import Nook

/// Pure logic of calendar sync. Every event here is made up.
final class CalendarSyncTests: XCTestCase {
    private var cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let format = DateFormatter()
        format.calendar = cal
        format.timeZone = cal.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.date(from: text)!
    }

    private func event(_ id: String, _ start: String, minutes: Double = 30, attendees: Int = 2, busy: Bool = true, allDay: Bool = false, link: String? = nil) -> CalendarEvent {
        CalendarEvent(id: id, title: "Synthetic \(id)", start: date(start), end: date(start).addingTimeInterval(minutes * 60),
                      allDay: allDay, attendees: attendees, busy: busy, link: link)
    }

    // MARK: discovery

    func testDiscoveryIsVendorNeutralAndReadOnly() {
        let tools = CalendarTools.discover(in: [
            "mcp__claude_ai_Google_Calendar__list_events", "mcp__claude_ai_Google_Calendar__list_calendars",
            "mcp__claude_ai_Google_Calendar__get_event", "mcp__claude_ai_Google_Calendar__search_events",
            "mcp__claude_ai_Google_Calendar__create_event", "mcp__claude_ai_Google_Calendar__delete_event",
            "mcp__claude_ai_Google_Calendar__update_event", "mcp__claude_ai_Google_Calendar__suggest_time",
            "mcp__claude_ai_Gmail__search_threads", "mcp__neon__run_sql", "Bash",
        ])
        XCTAssertEqual(tools.read.map { $0.components(separatedBy: "__").last! }.sorted(), ["get_event", "list_calendars", "list_events", "search_events"])
        XCTAssertEqual(tools.create, "mcp__claude_ai_Google_Calendar__create_event")
        XCTAssertTrue(tools.canRead)
        XCTAssertEqual(tools.others.count, 7, "everything that is not a read tool is denied by name, the create tool included")

        let other = CalendarTools.discover(in: ["mcp__ms365__calendar_search_events", "mcp__ms365__mail_list", "mcp__caldav-calendar__list_events", "mcp__caldav-calendar__add_event"])
        XCTAssertEqual(other.read, ["mcp__caldav-calendar__list_events"], "a verb that is not first is not trusted to be read-only")
        XCTAssertEqual(other.create, "mcp__caldav-calendar__add_event")
    }

    func testNoCalendarMeansNotConnected() {
        let none = CalendarTools.discover(in: ["mcp__claude_ai_Gmail__search_threads", "mcp__tickets__list_events", "Read"])
        XCTAssertFalse(none.canRead, "events on a server that is not a calendar do not count")
        XCTAssertFalse(CalendarTools.discover(in: ["mcp__cal_calendar__list_calendars"]).canRead, "listing calendars alone cannot show events")
    }

    // MARK: the command line

    func testListJobMayOnlyRead() {
        let tools = CalendarTools(read: ["mcp__c_calendar__list_events"], create: "mcp__c_calendar__create_event", others: ["mcp__c_calendar__create_event", "mcp__x__y"])
        let args = CalendarBridge.arguments(for: .list(DateInterval(start: date("2026-09-14 00:00"), duration: 86400), tools), model: nil)
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        XCTAssertEqual(Array(args.prefix(1)), ["-p"])
        XCTAssertEqual(value("--model"), "haiku")
        XCTAssertEqual(value("--tools"), "")
        XCTAssertEqual(value("--allowedTools"), "mcp__c_calendar__list_events")
        XCTAssertEqual(value("--disallowedTools"), "mcp__c_calendar__create_event,mcp__x__y")
        XCTAssertEqual(value("--permission-mode"), "dontAsk")
        XCTAssertEqual(value("--permission-prompts"), "none")
        XCTAssertEqual(value("--output-format"), "json")
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data((value("--json-schema") ?? "").utf8)))
        XCTAssertTrue(args.contains("--no-session-persistence"))
        XCTAssertEqual(CalendarBridge.arguments(for: .discover, model: "sonnet")[3], "sonnet")
    }

    func testCreateJobMayOnlyCreate() {
        let tools = CalendarTools(read: ["mcp__c_calendar__list_events"], create: "mcp__c_calendar__create_event", others: ["mcp__c_calendar__create_event", "mcp__c_calendar__delete_event"])
        let draft = CalendarBridge.EventDraft(title: "Nook: synthetic", start: date("2026-09-22 09:50"), end: date("2026-09-22 10:05"), notes: "synthetic")
        let args = CalendarBridge.arguments(for: .create(draft, tools), model: "")
        XCTAssertEqual(args[args.firstIndex(of: "--allowedTools")! + 1], "mcp__c_calendar__create_event")
        XCTAssertEqual(args[args.firstIndex(of: "--disallowedTools")! + 1], "mcp__c_calendar__list_events,mcp__c_calendar__delete_event")
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(CalendarBridge.createSchema.utf8)))
    }

    // MARK: running a job (against a script standing in for the CLI)

    private func script(_ body: String) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nook-fake-claude-" + UUID().uuidString)
        try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return file.path
    }

    private func run(_ bridge: CalendarBridge, _ job: CalendarBridge.Job, timeout: TimeInterval) -> Result<BridgeOutput, CalendarBridge.Failure>? {
        let done = expectation(description: "job")
        var result: Result<BridgeOutput, CalendarBridge.Failure>?
        bridge.run(job, timeout: timeout) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 20)
        return result
    }

    func testAJobThatIgnoresSIGTERMIsStillStopped() throws {
        // Also holds the output pipe open in a child, as the CLI's helper processes do.
        let bridge = CalendarBridge(executable: try script("trap '' TERM\nsleep 60 &\nwhile true; do sleep 1; done"))
        let started = Date()
        guard case .failure(.timedOut)? = run(bridge, .list(DateInterval(start: Date(), duration: 60), CalendarTools()), timeout: 0.5) else { return XCTFail("expected a timeout") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertFalse(bridge.isRunning, "free for the next job")
    }

    func testOneJobAtATimeAndCancel() throws {
        let bridge = CalendarBridge(executable: try script("sleep 30"))
        let done = expectation(description: "cancelled")
        bridge.run(.discover) { result in
            if case .failure(.cancelled) = result { done.fulfill() }
        }
        bridge.run(.discover) { XCTAssertEqual(try? $0.get().costUSD, nil); if case .failure(.busy) = $0 {} else { XCTFail("expected busy") } }
        bridge.cancel()
        wait(for: [done], timeout: 10)
    }

    func testDiscoveryStopsAtTheToolListAndRunsInAnEmptyFolder() throws {
        let body = #"[ -z "$(ls -A)" ] && echo '{"type":"system","subtype":"init","tools":["mcp__c_calendar__list_events"]}'"# + "\nsleep 30"
        let bridge = CalendarBridge(executable: try script(body))
        let started = Date()
        let output = try XCTUnwrap(run(bridge, .discover, timeout: 20)).get()
        XCTAssertEqual(output.tools, ["mcp__c_calendar__list_events"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "did not wait for the turn")
    }

    func testNoCLIAndUselessOutput() throws {
        guard case .failure(.noClaude)? = run(CalendarBridge(executable: nil), .discover, timeout: 5) else { return XCTFail("expected noClaude") }
        let silent = CalendarBridge(executable: try script("echo 'not json'"))
        guard case .failure(.failed("no result"))? = run(silent, .list(DateInterval(start: Date(), duration: 60), CalendarTools()), timeout: 5) else { return XCTFail("expected a failure") }
    }

    // MARK: reading the result

    func testParsesResultObjectArrayAndLines() {
        let result = #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.0152,"structured_output":{"events":[]}}"#
        let initEvent = #"{"type":"system","subtype":"init","tools":["a","b"]}"#
        for text in [result, "[\(initEvent),\(result)]", "\(initEvent)\n\(result)\n"] {
            let output = BridgeOutput.parse(Data(text.utf8))
            XCTAssertNil(output.error)
            XCTAssertEqual(output.costUSD, 0.0152, accuracy: 1e-9)
            XCTAssertNotNil(output.structured)
        }
        XCTAssertEqual(BridgeOutput.parse(Data("\(initEvent)\n{\"type\":\"assi".utf8)).tools, ["a", "b"], "a half-written line is ignored")
        XCTAssertEqual(BridgeOutput.parse(Data()).error, "no result")
        XCTAssertEqual(BridgeOutput.parse(Data(#"{"type":"result","subtype":"error_max_budget_usd","is_error":true}"#.utf8)).error, "error_max_budget_usd")
        XCTAssertEqual(BridgeOutput.parse(Data(#"{"type":"result","subtype":"success","is_error":false,"result":"hi"}"#.utf8)).error, "no structured result")
    }

    func testDecodesEventsDefensively() throws {
        let json = """
        {"events":[
          {"id":"b","title":"Synthetic timed","start":"2026-09-22T10:00:00+02:00","end":"2026-09-22T10:30:00+02:00","allDay":false,"attendees":3,"busy":true,"link":"https://meet.example/abc"},
          {"id":"a","title":"Synthetic day","start":"2026-09-22","end":"2026-09-23","allDay":true,"attendees":0,"busy":false},
          {"id":"c","title":"","start":"2026-09-22T11:00:00.000Z","end":"bad","attendees":"2","link":"not a url"},
          {"id":"d","title":"Synthetic local","start":"2026-09-22T12:00:00","end":"2026-09-22T12:15:00","allDay":false,"attendees":true},
          {"id":"b","title":"duplicate","start":"2026-09-22T10:00:00+02:00","end":"2026-09-22T10:30:00+02:00","allDay":false},
          {"id":"","title":"no id","start":"2026-09-22T10:00:00Z","end":"2026-09-22T10:30:00Z"},
          {"id":"e","title":"no start","end":"2026-09-22T10:30:00Z"},
          "nonsense"
        ]}
        """
        let events = try XCTUnwrap(EventDecoding.events(from: JSONSerialization.jsonObject(with: Data(json.utf8)), calendar: cal))
        XCTAssertEqual(events.map(\.id), ["a", "b", "d", "c"], "by start: 12:00 in Berlin is before 11:00 UTC")
        let (day, timed, local, sloppy) = (events[0], events[1], events[2], events[3])
        XCTAssertEqual(day.start, date("2026-09-22 00:00"))
        XCTAssertEqual(day.end, date("2026-09-23 00:00"))
        XCTAssertFalse(day.isMeeting)
        XCTAssertEqual(timed.start, date("2026-09-22 10:00"))
        XCTAssertTrue(timed.isMeeting)
        XCTAssertEqual(sloppy.title, "(No title)")
        XCTAssertEqual(sloppy.end, sloppy.start)
        XCTAssertEqual(sloppy.attendees, 2)
        XCTAssertNil(sloppy.link)
        XCTAssertEqual(local.start, date("2026-09-22 12:00"))
        XCTAssertEqual(local.attendees, 0, "true is not a number")
        XCTAssertNil(EventDecoding.events(from: ["nothing": 1]))
        XCTAssertNil(EventDecoding.events(from: "text"))
    }

    func testSameDayAllDayEndStillCoversItsDay() throws {
        let row: [String: Any] = ["id": "x", "title": "Synthetic", "start": "2026-09-22", "end": "2026-09-22", "allDay": true]
        let event = try XCTUnwrap(EventDecoding.event(from: row, calendar: cal))
        XCTAssertEqual(event.end, date("2026-09-23 00:00"))
        XCTAssertTrue(event.falls(on: date("2026-09-22 15:00"), calendar: cal))
        XCTAssertFalse(event.falls(on: date("2026-09-23 15:00"), calendar: cal))
    }

    func testConnectorErrorIsNotAnEmptyCalendar() {
        XCTAssertNotNil(SyncProblem.message(problem: "Insufficient scope: required calendar.readonly", eventCount: 0))
        XCTAssertTrue(SyncProblem.message(problem: "Insufficient scope", eventCount: 0)!.contains("Reconnect"))
        XCTAssertNil(SyncProblem.message(problem: "one calendar failed", eventCount: 4), "a partial result is kept, and marked truncated")
        XCTAssertNil(SyncProblem.message(problem: " ", eventCount: 0))
        XCTAssertNil(SyncProblem.message(problem: nil, eventCount: 0))
    }

    // MARK: cache and policy

    func testWindowIsWholeDays() {
        let window = CalendarCache.window(around: date("2026-09-21 16:45"), calendar: cal)
        XCTAssertEqual(window.start, date("2026-09-14 00:00"))
        XCTAssertEqual(window.end, date("2026-10-22 00:00"))
        // Across the end of summer time the days are still whole.
        XCTAssertEqual(CalendarCache.window(around: date("2026-10-20 12:00"), calendar: cal).end, date("2026-11-20 00:00"))
    }

    func testCacheRoundTripsAndIsPrivate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-cache-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("calendar-cache.json")
        var cache = CalendarCache(syncedAt: date("2026-09-21 09:00"), window: CalendarCache.window(around: date("2026-09-21 09:00"), calendar: cal),
                                  costUSD: 0.02, events: [event("a", "2026-09-22 10:00", link: "https://meet.example/a")])
        cache.save(to: file)
        cache.events.append(event("b", "2026-09-23 10:00"))
        cache.save(to: file) // replacing an existing file keeps the permissions too
        XCTAssertEqual(CalendarCache.load(from: file), cache)
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["calendar-cache.json"], "no scratch file is left behind")
        XCTAssertNil(CalendarCache.load(from: folder.appendingPathComponent("missing.json")))
    }

    func testSyncPolicy() {
        let now = date("2026-09-21 12:00")
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        XCTAssertFalse(SyncPolicy.shouldSync(.panelOpened, lastSync: nil, now: now, backgroundEnabled: true), "the first sync is the user's click")
        XCTAssertFalse(SyncPolicy.shouldSync(.panelOpened, lastSync: ago(14), now: now, backgroundEnabled: false))
        XCTAssertTrue(SyncPolicy.shouldSync(.panelOpened, lastSync: ago(16), now: now, backgroundEnabled: false))
        XCTAssertFalse(SyncPolicy.shouldSync(.panelOpened, lastSync: ago(600), lastAttempt: ago(2), now: now, backgroundEnabled: false), "a sync that just failed is not retried by reopening")
        XCTAssertTrue(SyncPolicy.shouldSync(.refreshButton, lastSync: ago(1), now: now, backgroundEnabled: false))
        XCTAssertFalse(SyncPolicy.shouldSync(.background, lastSync: ago(600), now: now, backgroundEnabled: false), "off by default means never")
        XCTAssertFalse(SyncPolicy.shouldSync(.background, lastSync: nil, now: now, backgroundEnabled: true))
        XCTAssertFalse(SyncPolicy.shouldSync(.background, lastSync: ago(59), now: now, backgroundEnabled: true))
        XCTAssertTrue(SyncPolicy.shouldSync(.background, lastSync: ago(61), now: now, backgroundEnabled: true))
        XCTAssertFalse(SyncPolicy.shouldSync(.background, lastSync: ago(600), lastAttempt: ago(30), now: now, backgroundEnabled: true), "failures retry hourly, not in a loop")
        XCTAssertNil(SyncPolicy.nextBackgroundSync(lastSync: ago(5), lastAttempt: nil, enabled: false))
        XCTAssertEqual(SyncPolicy.nextBackgroundSync(lastSync: ago(5), lastAttempt: nil, enabled: true), now.addingTimeInterval(55 * 60))
    }

    // MARK: prompts tied to events

    func testReanchoring() {
        let now = date("2026-09-21 12:00")
        let window = CalendarCache.window(around: now, calendar: cal)
        let standup = event("standup", "2026-09-22 10:00")
        var items = [EventAnchoring.item(prompt: "synthetic prompt", before: standup, lead: 600, now: now)]
        XCTAssertEqual(items[0].schedule, Schedule(kind: .once, date: date("2026-09-22 09:50")))

        EventAnchoring.reanchor(&items, events: [standup], window: window, now: now)
        XCTAssertEqual(items[0].schedule.date, date("2026-09-22 09:50"), "unchanged event, unchanged prompt")

        EventAnchoring.reanchor(&items, events: [event("standup", "2026-09-22 14:00")], window: window, now: now)
        XCTAssertEqual(items[0].schedule.date, date("2026-09-22 13:50"), "the prompt follows the event")
        XCTAssertEqual(ScheduleClock.nextWake(items, calendar: cal), date("2026-09-22 13:50"))

        EventAnchoring.reanchor(&items, events: [], window: window, complete: false, now: now)
        XCTAssertEqual(items[0].anchor?.orphaned, false, "a sync that could not return everything proves nothing")

        EventAnchoring.reanchor(&items, events: [], window: window, now: now)
        XCTAssertEqual(items[0].anchor?.orphaned, true)
        XCTAssertFalse(items[0].enabled, "no prompt before a meeting that is not happening")

        EventAnchoring.reanchor(&items, events: [event("standup", "2026-09-23 10:00")], window: window, now: now)
        XCTAssertEqual(items[0].anchor?.orphaned, false)
        XCTAssertTrue(items[0].enabled, "back on the calendar, back on")
        XCTAssertEqual(items[0].schedule.date, date("2026-09-23 09:50"))
    }

    func testReanchoringLeavesAloneWhatItCannotKnow() {
        let now = date("2026-09-21 12:00")
        let window = CalendarCache.window(around: now, calendar: cal)
        let far = event("far", "2026-12-01 10:00")
        var items = [EventAnchoring.item(prompt: "synthetic", before: far, lead: 300, now: now), AgentCalendar.Item(prompt: "plain", checkedUntil: now)]
        items[0].enabled = false // the user's own choice
        let before = items
        EventAnchoring.reanchor(&items, events: [], window: window, now: now)
        XCTAssertEqual(items, before, "outside the synced window nothing is known")

        EventAnchoring.reanchor(&items, events: [event("far", "2026-12-02 10:00")], window: window, now: now)
        XCTAssertEqual(items[0].schedule.date, date("2026-12-02 09:55"))
        XCTAssertFalse(items[0].enabled, "moving an event does not switch a prompt back on")
    }

    func testRepeatingEventWithOneIDFollowsItsOwnInstance() {
        let now = date("2026-09-21 12:00")
        let tuesday = event("weekly", "2026-09-22 10:00")
        var items = [EventAnchoring.item(prompt: "synthetic", before: tuesday, lead: 600, now: now)]
        let instances = [event("weekly", "2026-09-15 10:00"), event("weekly", "2026-09-22 10:30"), event("weekly", "2026-09-29 10:00")]
        EventAnchoring.reanchor(&items, events: instances, window: CalendarCache.window(around: now, calendar: cal), now: now)
        XCTAssertEqual(items[0].schedule.date, date("2026-09-22 10:20"))
    }

    func testAnchorSurvivesTheScheduleFileAndOldFilesStillLoad() throws {
        let item = EventAnchoring.item(prompt: "synthetic", before: event("a", "2026-09-22 10:00"), lead: 600, now: date("2026-09-21 12:00"))
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(AgentCalendar.Item.self, from: data), item)
        var plain = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        plain["anchor"] = nil
        let old = try JSONDecoder().decode(AgentCalendar.Item.self, from: JSONSerialization.data(withJSONObject: plain))
        XCTAssertNil(old.anchor)
    }

    // MARK: meetings and quiet mode

    func testMeetingDetection() {
        let events = [
            event("meeting", "2026-09-21 10:00"),
            event("solo", "2026-09-21 11:00", attendees: 0),
            event("call", "2026-09-21 12:00", attendees: 0, link: "https://meet.example/x"),
            event("free", "2026-09-21 13:00", busy: false),
            event("offsite", "2026-09-21 00:00", minutes: 1440, allDay: true),
        ]
        XCTAssertFalse(MeetingClock.inMeeting(events, at: date("2026-09-21 09:59")))
        XCTAssertTrue(MeetingClock.inMeeting(events, at: date("2026-09-21 10:00")))
        XCTAssertFalse(MeetingClock.inMeeting(events, at: date("2026-09-21 10:30")), "the end is exclusive")
        XCTAssertFalse(MeetingClock.inMeeting(events, at: date("2026-09-21 11:10")), "focus time alone is not a meeting")
        XCTAssertTrue(MeetingClock.inMeeting(events, at: date("2026-09-21 12:10")), "a meeting link counts without guests")
        XCTAssertFalse(MeetingClock.inMeeting(events, at: date("2026-09-21 13:10")))
        XCTAssertFalse(MeetingClock.inMeeting([], at: date("2026-09-21 10:10")), "never synced: no effect")
    }

    func testOneTimerToTheNextBoundary() {
        let events = [event("a", "2026-09-21 10:00"), event("b", "2026-09-21 10:15", minutes: 45), event("solo", "2026-09-21 09:00", attendees: 0)]
        XCTAssertEqual(MeetingClock.nextBoundary(events, after: date("2026-09-21 08:00")), date("2026-09-21 10:00"), "a non-meeting sets no timer")
        XCTAssertEqual(MeetingClock.nextBoundary(events, after: date("2026-09-21 10:00")), date("2026-09-21 10:15"))
        XCTAssertEqual(MeetingClock.nextBoundary(events, after: date("2026-09-21 10:15")), date("2026-09-21 10:30"))
        XCTAssertTrue(MeetingClock.inMeeting(events, at: date("2026-09-21 10:30")), "back-to-back: still quiet")
        XCTAssertEqual(MeetingClock.nextBoundary(events, after: date("2026-09-21 10:30")), date("2026-09-21 11:00"))
        XCTAssertNil(MeetingClock.nextBoundary(events, after: date("2026-09-21 11:00")), "nothing ahead: no timer at all")
    }
}
