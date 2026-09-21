import XCTest
@testable import Nook

/// Runs real, paid bridge jobs against the user's own calendar, so it is skipped unless
/// NOOK_LIVE_CALENDAR names a step. Prints counts and shapes only, never anything from an event.
final class CalendarLiveTests: XCTestCase {
    private func run(_ job: CalendarBridge.Job) throws -> BridgeOutput {
        let bridge = CalendarBridge()
        let done = expectation(description: "job")
        var result: Result<BridgeOutput, CalendarBridge.Failure>?
        bridge.run(job) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 300)
        return try XCTUnwrap(result).get()
    }

    func testLive() throws {
        let step = ProcessInfo.processInfo.environment["NOOK_LIVE_CALENDAR"] ?? ""
        try XCTSkipIf(step.isEmpty, "live bridge jobs cost money; set NOOK_LIVE_CALENDAR=discover or list")
        let started = Date()
        let tools = CalendarTools.discover(in: try run(.discover).tools ?? [])
        print("LIVE discover: read=\(tools.read.count) create=\(tools.create != nil) others=\(tools.others.count) canRead=\(tools.canRead) seconds=\(Int(Date().timeIntervalSince(started)))")
        guard step == "list" else { return }
        let window = CalendarCache.window(around: Date())
        let listed = Date()
        let output = try run(.list(window, tools))
        let rows = (output.structured as? [String: Any])?["events"] as? [[String: Any]] ?? []
        let events = try XCTUnwrap(EventDecoding.events(from: output.structured))
        let keys = Set(rows.flatMap(\.keys)).sorted()
        print("LIVE list: rows=\(rows.count) decoded=\(events.count) keys=\(keys) allDay=\(events.filter(\.allDay).count) meetings=\(events.filter(\.isMeeting).count) "
              + "inWindow=\(events.filter { $0.overlaps(window) }.count) cost=\(output.costUSD) seconds=\(Int(Date().timeIntervalSince(listed)))")
    }
}
