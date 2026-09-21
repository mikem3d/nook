import Foundation

/// When a scheduled prompt runs. Pure value and pure maths, so the awkward days (clock changes,
/// month ends, leap days) are unit tested.
struct Schedule: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable { case once, daily, weekdays, weekly }

    var kind: Kind = .daily
    /// `once` only.
    var date = Date()
    /// Wall-clock time of the repeating kinds.
    var hour = 9
    var minute = 0
    /// `weekly` only: Calendar weekday numbers, 1 Sunday to 7 Saturday.
    var days: Set<Int> = [2]

    static let workdays: Set<Int> = [2, 3, 4, 5, 6]

    /// The first run strictly after `after`; nil when there is none (a `once` in the past, a week with no days).
    ///
    /// Clock changes: a time that does not exist on the day the clocks go forward runs at the next
    /// time that does (02:30 becomes 03:00); a time that happens twice when they go back runs the
    /// first time only.
    func next(after: Date, calendar: Calendar = .current) -> Date? {
        switch kind {
        case .once:
            return date > after ? date : nil
        case .daily:
            return Self.next(after: after, weekday: nil, hour: hour, minute: minute, calendar: calendar)
        case .weekdays, .weekly:
            let wanted = kind == .weekdays ? Self.workdays : days
            return wanted.compactMap { Self.next(after: after, weekday: $0, hour: hour, minute: minute, calendar: calendar) }.min()
        }
    }

    /// True if a run falls on the calendar day containing `day`.
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let run = next(after: start.addingTimeInterval(-1), calendar: calendar) else { return false }
        return run < end
    }

    private static func next(after: Date, weekday: Int?, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.weekday = weekday
        parts.hour = min(max(hour, 0), 23)
        parts.minute = min(max(minute, 0), 59)
        parts.second = 0
        var from = after
        // Searching from just after the first 01:30 of the night the clocks go back finds the second
        // one. Its first occurrence was at or before `after`, so it has run: step past the repeat.
        let wall: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        for _ in 0..<2 {
            guard let found = calendar.nextDate(after: from, matching: parts, matchingPolicy: .nextTime,
                                                repeatedTimePolicy: .first, direction: .forward) else { return nil }
            let hourBefore = found.addingTimeInterval(-3600)
            if calendar.dateComponents(wall, from: hourBefore) != calendar.dateComponents(wall, from: found) { return found }
            from = found
        }
        return nil
    }

    /// "Daily at 09:00", "Mon, Wed at 17:30", "12 Mar 2027 at 08:00".
    func summary(calendar: Calendar = .current) -> String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .once:
            let format = DateFormatter()
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            format.dateStyle = .medium
            format.timeStyle = .short
            return format.string(from: date)
        case .daily: return "Daily at \(time)"
        case .weekdays: return "Weekdays at \(time)"
        case .weekly:
            let names = calendar.shortWeekdaySymbols
            let listed = days.sorted().compactMap { names.indices.contains($0 - 1) ? names[$0 - 1] : nil }
            return (listed.isEmpty ? "No days" : listed.joined(separator: ", ")) + " at \(time)"
        }
    }
}

/// The days a month view shows: whole weeks, padded with nil before the 1st and after the last day.
enum MonthGrid {
    static func days(of month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let span = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let lead = (calendar.component(.weekday, from: span.start) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for day in 0..<count { cells.append(calendar.date(byAdding: .day, value: day, to: span.start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
