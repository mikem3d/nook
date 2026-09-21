import XCTest
@testable import Nook

final class ScheduleTests: XCTestCase {
    private func calendar(_ zone: String, firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ text: String, _ calendar: Calendar) -> Date {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.date(from: text)!
    }

    private func text(_ date: Date?, _ calendar: Calendar) -> String {
        guard let date else { return "nil" }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH:mm EEE"
        return format.string(from: date)
    }

    private func daily(_ hour: Int, _ minute: Int) -> Schedule { Schedule(kind: .daily, hour: hour, minute: minute) }

    // MARK: next run

    func testOnce() {
        let cal = calendar("Europe/Berlin")
        let when = date("2026-09-25 14:30", cal)
        let once = Schedule(kind: .once, date: when)
        XCTAssertEqual(once.next(after: date("2026-09-21 09:00", cal), calendar: cal), when)
        XCTAssertNil(once.next(after: when, calendar: cal), "strictly after: a run is never found twice")
        XCTAssertNil(once.next(after: date("2026-09-26 00:00", cal), calendar: cal))
    }

    func testDailyTodayThenTomorrow() {
        let cal = calendar("America/New_York")
        let nine = daily(9, 0)
        XCTAssertEqual(text(nine.next(after: date("2026-09-21 08:59", cal), calendar: cal), cal), "2026-09-21 09:00 Mon")
        XCTAssertEqual(text(nine.next(after: date("2026-09-21 09:00", cal), calendar: cal), cal), "2026-09-22 09:00 Tue", "strictly after")
        XCTAssertEqual(text(nine.next(after: date("2026-09-21 23:59", cal), calendar: cal), cal), "2026-09-22 09:00 Tue")
    }

    func testMonthEndsYearEndAndLeapDay() {
        let cal = calendar("Europe/Berlin")
        let late = daily(23, 30)
        XCTAssertEqual(text(late.next(after: date("2026-09-30 23:45", cal), calendar: cal), cal), "2026-10-01 23:30 Thu")
        XCTAssertEqual(text(late.next(after: date("2026-12-31 23:31", cal), calendar: cal), cal), "2027-01-01 23:30 Fri")
        XCTAssertEqual(text(late.next(after: date("2027-02-28 23:31", cal), calendar: cal), cal), "2027-03-01 23:30 Mon", "no leap day in 2027")
        XCTAssertEqual(text(late.next(after: date("2028-02-28 23:31", cal), calendar: cal), cal), "2028-02-29 23:30 Tue", "leap day in 2028")
        XCTAssertEqual(text(late.next(after: date("2028-02-29 23:31", cal), calendar: cal), cal), "2028-03-01 23:30 Wed")
    }

    func testWeekdaysSkipTheWeekend() {
        let cal = calendar("America/New_York")
        let work = Schedule(kind: .weekdays, hour: 8, minute: 15)
        XCTAssertEqual(text(work.next(after: date("2026-09-25 08:14", cal), calendar: cal), cal), "2026-09-25 08:15 Fri")
        XCTAssertEqual(text(work.next(after: date("2026-09-25 08:15", cal), calendar: cal), cal), "2026-09-28 08:15 Mon")
        XCTAssertEqual(text(work.next(after: date("2026-09-26 12:00", cal), calendar: cal), cal), "2026-09-28 08:15 Mon")
        XCTAssertEqual(text(work.next(after: date("2026-09-27 12:00", cal), calendar: cal), cal), "2026-09-28 08:15 Mon")
        // Weekday numbers do not depend on which day the locale starts its week.
        let monday = calendar("America/New_York", firstWeekday: 2)
        XCTAssertEqual(text(work.next(after: date("2026-09-26 12:00", monday), calendar: monday), monday), "2026-09-28 08:15 Mon")
    }

    func testWeeklyOnChosenDays() {
        let cal = calendar("Europe/Berlin")
        let some = Schedule(kind: .weekly, hour: 17, minute: 30, days: [2, 4, 7]) // Mon, Wed, Sat
        var cursor = date("2026-09-21 17:30", cal) // Monday, exactly at its time
        var seen: [String] = []
        for _ in 0..<4 {
            cursor = some.next(after: cursor, calendar: cal)!
            seen.append(text(cursor, cal))
        }
        XCTAssertEqual(seen, ["2026-09-23 17:30 Wed", "2026-09-26 17:30 Sat", "2026-09-28 17:30 Mon", "2026-09-30 17:30 Wed"])
        XCTAssertNil(Schedule(kind: .weekly, hour: 9, minute: 0, days: []).next(after: cursor, calendar: cal), "no days, no runs")
        let sundays = Schedule(kind: .weekly, hour: 0, minute: 0, days: [1])
        XCTAssertEqual(text(sundays.next(after: date("2026-12-27 00:00", cal), calendar: cal), cal), "2027-01-03 00:00 Sun", "across the year end")
    }

    // MARK: clock changes

    func testSpringForwardRunsAtTheNextTimeThatExists() {
        let cal = calendar("America/New_York") // 8 March 2026: 02:00 becomes 03:00
        let gap = daily(2, 30)
        XCTAssertEqual(text(gap.next(after: date("2026-03-07 02:30", cal), calendar: cal), cal), "2026-03-08 03:00 Sun")
        XCTAssertEqual(text(gap.next(after: date("2026-03-08 03:00", cal), calendar: cal), cal), "2026-03-09 02:30 Mon", "once that day, then back to normal")
        // A time outside the gap keeps its wall-clock hour although the day is 23 hours long.
        let nine = daily(9, 0)
        let before = nine.next(after: date("2026-03-07 08:00", cal), calendar: cal)!
        let after = nine.next(after: before, calendar: cal)!
        XCTAssertEqual(text(after, cal), "2026-03-08 09:00 Sun")
        XCTAssertEqual(after.timeIntervalSince(before), 23 * 3600)
    }

    func testFallBackRunsARepeatedTimeOnce() {
        let cal = calendar("America/New_York") // 1 November 2026: 02:00 becomes 01:00, so 01:30 happens twice
        let twice = daily(1, 30)
        let first = twice.next(after: date("2026-10-31 12:00", cal), calendar: cal)!
        XCTAssertEqual(text(first, cal), "2026-11-01 01:30 Sun")
        let second = twice.next(after: first, calendar: cal)!
        XCTAssertEqual(text(second, cal), "2026-11-02 01:30 Mon", "not the second 01:30 an hour later")
        XCTAssertEqual(second.timeIntervalSince(first), 25 * 3600)
        // Asked from between the two 01:30s, the answer is still tomorrow.
        XCTAssertEqual(text(twice.next(after: first.addingTimeInterval(1800), calendar: cal), cal), "2026-11-02 01:30 Mon")

        let berlin = calendar("Europe/Berlin") // 25 October 2026: 03:00 becomes 02:00
        let early = Schedule(kind: .weekly, hour: 2, minute: 15, days: [1])
        let a = early.next(after: date("2026-10-24 12:00", berlin), calendar: berlin)!
        XCTAssertEqual(text(a, berlin), "2026-10-25 02:15 Sun")
        XCTAssertEqual(text(early.next(after: a, calendar: berlin), berlin), "2026-11-01 02:15 Sun")
    }

    func testAYearOfDailyRunsNeverSkipsOrRepeatsADay() {
        for zone in ["America/New_York", "Europe/Berlin", "Australia/Lord_Howe", "Asia/Kolkata"] {
            let cal = calendar(zone)
            for schedule in [daily(2, 30), daily(1, 30), daily(0, 0), daily(23, 59)] {
                var cursor = date("2026-01-01 00:00", cal).addingTimeInterval(-60)
                var days: [Int] = []
                for _ in 0..<365 {
                    cursor = schedule.next(after: cursor, calendar: cal)!
                    days.append(cal.ordinality(of: .day, in: .year, for: cursor)!)
                }
                XCTAssertEqual(days, Array(1...365), "\(zone) \(schedule.hour):\(schedule.minute)")
            }
        }
    }

    func testOccursOn() {
        let cal = calendar("Europe/Berlin")
        let work = Schedule(kind: .weekdays, hour: 0, minute: 0)
        XCTAssertTrue(work.occurs(on: date("2026-09-21 15:00", cal), calendar: cal), "midnight belongs to the day it starts")
        XCTAssertFalse(work.occurs(on: date("2026-09-20 15:00", cal), calendar: cal), "Sunday")
        let once = Schedule(kind: .once, date: date("2026-09-25 23:59", cal))
        XCTAssertTrue(once.occurs(on: date("2026-09-25 00:00", cal), calendar: cal))
        XCTAssertFalse(once.occurs(on: date("2026-09-26 00:00", cal), calendar: cal))
    }

    // MARK: month grid

    func testMonthGridPadsToWholeWeeks() {
        let sunday = calendar("Europe/Berlin", firstWeekday: 1)
        var cells = MonthGrid.days(of: date("2026-09-15 12:00", sunday), calendar: sunday) // 1 Sep 2026 is a Tuesday
        XCTAssertEqual(cells.count, 35)
        XCTAssertEqual(cells.prefix(2).compactMap { $0 }.count, 0)
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
        XCTAssertEqual(sunday.component(.day, from: cells[2]!), 1)
        let monday = calendar("Europe/Berlin", firstWeekday: 2)
        cells = MonthGrid.days(of: date("2026-09-15 12:00", monday), calendar: monday)
        XCTAssertEqual(monday.component(.day, from: cells[1]!), 1)
        cells = MonthGrid.days(of: date("2026-02-10 12:00", sunday), calendar: sunday) // starts on a Sunday, 28 days
        XCTAssertEqual(cells.count, 28)
        XCTAssertEqual(cells.compactMap { $0 }.count, 28)
        XCTAssertEqual(MonthGrid.days(of: date("2028-02-10 12:00", sunday), calendar: sunday).compactMap { $0 }.count, 29)
        // October 2026 in Berlin has a 25 hour day; every cell is still its own day.
        let october = MonthGrid.days(of: date("2026-10-05 12:00", monday), calendar: monday).compactMap { $0 }
        XCTAssertEqual(october.map { monday.component(.day, from: $0) }, Array(1...31))
    }

    // MARK: what is due

    private func item(_ schedule: Schedule, checked: Date) -> AgentCalendar.Item {
        AgentCalendar.Item(prompt: "Run the tests", schedule: schedule, checkedUntil: checked)
    }

    func testDueRunIsSentAndNotFoundAgain() {
        let cal = calendar("Europe/Berlin")
        var items = [item(daily(9, 0), checked: date("2026-09-21 08:00", cal))]
        XCTAssertEqual(ScheduleClock.nextWake(items, calendar: cal), date("2026-09-21 09:00", cal))
        XCTAssertTrue(ScheduleClock.reconcile(&items, now: date("2026-09-21 08:30", cal), launching: false, calendar: cal).isEmpty)
        let now = date("2026-09-21 09:00", cal).addingTimeInterval(2)
        XCTAssertEqual(ScheduleClock.reconcile(&items, now: now, launching: false, calendar: cal), [items[0].id])
        XCTAssertNil(items[0].missed)
        XCTAssertTrue(ScheduleClock.reconcile(&items, now: now.addingTimeInterval(1), launching: false, calendar: cal).isEmpty)
        XCTAssertEqual(ScheduleClock.nextWake(items, calendar: cal), date("2026-09-22 09:00", cal))
    }

    func testNothingRunsAtLaunchWhatWasMissedIsMarked() {
        let cal = calendar("Europe/Berlin")
        var items = [item(daily(9, 0), checked: date("2026-09-18 12:00", cal)),
                     item(daily(9, 5), checked: date("2026-09-21 09:00", cal))]
        let now = date("2026-09-21 09:06", cal)
        XCTAssertTrue(ScheduleClock.reconcile(&items, now: now, launching: true, calendar: cal).isEmpty, "even one only a minute late")
        XCTAssertEqual(items[0].missed, date("2026-09-21 09:00", cal), "the most recent of the three it missed")
        XCTAssertEqual(items[1].missed, date("2026-09-21 09:05", cal))
        XCTAssertTrue(ScheduleClock.reconcile(&items, now: now.addingTimeInterval(60), launching: false, calendar: cal).isEmpty, "and they do not run later either")
        XCTAssertEqual(ScheduleClock.nextWake(items, calendar: cal), date("2026-09-22 09:00", cal))
    }

    func testARunSleptThroughIsMissedNotSentLate() {
        let cal = calendar("Europe/Berlin")
        var items = [item(daily(9, 0), checked: date("2026-09-21 08:00", cal))]
        XCTAssertTrue(ScheduleClock.reconcile(&items, now: date("2026-09-21 14:00", cal), launching: false, calendar: cal).isEmpty)
        XCTAssertEqual(items[0].missed, date("2026-09-21 09:00", cal))
        var near = [item(daily(9, 0), checked: date("2026-09-21 08:00", cal))]
        XCTAssertEqual(ScheduleClock.reconcile(&near, now: date("2026-09-21 09:10", cal), launching: false, calendar: cal).count, 1, "within the grace period")
    }

    func testOnceSwitchesOffAndDisabledItemsAreIgnored() {
        let cal = calendar("Europe/Berlin")
        var items = [item(Schedule(kind: .once, date: date("2026-09-21 10:00", cal)), checked: date("2026-09-21 08:00", cal))]
        XCTAssertEqual(ScheduleClock.reconcile(&items, now: date("2026-09-21 10:00", cal), launching: false, calendar: cal).count, 1)
        XCTAssertFalse(items[0].enabled)
        XCTAssertNil(ScheduleClock.nextWake(items, calendar: cal))

        var off = [item(daily(9, 0), checked: date("2026-09-20 08:00", cal))]
        off[0].enabled = false
        XCTAssertTrue(ScheduleClock.reconcile(&off, now: date("2026-09-21 09:00", cal), launching: false, calendar: cal).isEmpty)
        XCTAssertNil(off[0].missed)
        XCTAssertNil(ScheduleClock.nextWake(off, calendar: cal))
    }

    func testHistoryIsCapped() {
        var calendar = AgentCalendar()
        for n in 0..<(AgentCalendar.historyLimit + 10) {
            calendar.record(.init(date: Date(timeIntervalSince1970: Double(n)), summary: "\(n)", failed: false, source: ""))
        }
        XCTAssertEqual(calendar.history.count, AgentCalendar.historyLimit)
        XCTAssertEqual(calendar.history.first?.summary, "10", "the oldest go first")
    }
}
