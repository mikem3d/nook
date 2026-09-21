import Foundation

/// "Is the user in a meeting right now", from cached events. Pure, so quiet mode can run on one
/// timer set to the next time the answer changes.
enum MeetingClock {
    static func inMeeting(_ events: [CalendarEvent], at now: Date) -> Bool {
        events.contains { $0.isMeeting && $0.start <= now && now < $0.end }
    }

    /// The next start or end of a meeting after `now`; nil when no meeting lies ahead.
    static func nextBoundary(_ events: [CalendarEvent], after now: Date) -> Date? {
        events.filter(\.isMeeting).flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
    }
}
