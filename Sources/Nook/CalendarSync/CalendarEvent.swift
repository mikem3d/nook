import Foundation

/// One event from the user's real calendar, as the bridge job reported it. Private data: it lives
/// in memory and in the cache file only, and is never logged.
struct CalendarEvent: Codable, Equatable, Identifiable {
    var id: String
    var calendar = ""
    var title: String
    var start: Date
    /// Exclusive. For an all-day event, the start of the day after its last day.
    var end: Date
    var allDay = false
    var location = ""
    var attendees = 0
    var busy = true
    var link: String?

    /// Time the user is likely in a call: busy, timed, and with other people or a meeting link.
    var isMeeting: Bool { busy && !allDay && (attendees > 0 || link != nil) }

    func overlaps(_ span: DateInterval) -> Bool { start < span.end && end > span.start }

    func falls(on day: Date, calendar: Calendar = .current) -> Bool {
        calendar.dateInterval(of: .day, for: day).map(overlaps) ?? false
    }
}

/// Turns the job's structured result into events. The schema is enforced by the CLI, but the
/// values inside come from a model copying a tool's output, so every field is read defensively:
/// a bad event is dropped, never a reason to fail the sync.
enum EventDecoding {
    static func events(from result: Any?, calendar: Calendar = .current) -> [CalendarEvent]? {
        guard let object = result as? [String: Any], let rows = object["events"] as? [Any] else { return nil }
        var seen = Set<String>()
        var events: [CalendarEvent] = []
        for case let row as [String: Any] in rows {
            guard let event = event(from: row, calendar: calendar) else { continue }
            // A repeating event may reuse one id for every instance.
            guard seen.insert("\(event.id)|\(event.start.timeIntervalSince1970)").inserted else { continue }
            events.append(event)
        }
        return events.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    static func event(from row: [String: Any], calendar: Calendar = .current) -> CalendarEvent? {
        guard let id = text(row["id"]), !id.isEmpty,
              let startText = text(row["start"]), let start = date(startText, calendar: calendar) else { return nil }
        let dateOnly = startText.count == 10
        let allDay = (row["allDay"] as? Bool) ?? dateOnly
        var end = text(row["end"]).flatMap { date($0, calendar: calendar) } ?? start
        if allDay {
            // Whole days: end is exclusive, and an event always covers at least its first day.
            let first = calendar.startOfDay(for: start)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: first) ?? first.addingTimeInterval(86400)
            end = max(calendar.startOfDay(for: end), nextDay)
        } else if end < start {
            end = start
        }
        let link = text(row["link"]).flatMap { $0.lowercased().hasPrefix("http") ? $0 : nil }
        return CalendarEvent(id: id, calendar: text(row["calendar"]) ?? "",
                             title: text(row["title"]).flatMap { $0.isEmpty ? nil : $0 } ?? "(No title)",
                             start: allDay ? calendar.startOfDay(for: start) : start, end: end, allDay: allDay,
                             location: text(row["location"]) ?? "", attendees: max(0, number(row["attendees"]) ?? 0),
                             busy: (row["busy"] as? Bool) ?? true, link: link)
    }

    /// RFC 3339 with or without fractional seconds, a local date-time with no zone, or a bare date.
    static func date(_ raw: String, calendar: Calendar = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            iso.formatOptions = options
            if let date = iso.date(from: text) { return date }
        }
        let local = DateFormatter()
        local.calendar = calendar
        local.timeZone = calendar.timeZone
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ value: Any?) -> Int? {
        // JSON true is an NSNumber too; only a real number counts.
        if let number = value as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : number.intValue }
        return (value as? String).flatMap(Int.init)
    }
}
