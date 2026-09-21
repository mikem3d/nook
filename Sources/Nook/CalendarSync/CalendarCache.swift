import Foundation

/// The last sync, kept in Application Support/Nook/calendar-cache.json, readable by the user only.
struct CalendarCache: Codable, Equatable {
    static let daysBack = 7
    static let daysAhead = 30

    var version = 1
    var syncedAt: Date
    /// The period the sync asked for: an event missing from `events` inside it is really gone.
    var window: DateInterval
    var costUSD: Double
    var truncated = false
    var events: [CalendarEvent]

    /// Whole days: from the start of the day a week ago to the end of the day 30 days ahead.
    static func window(around now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: daysAhead + 1, to: today) ?? today
        return DateInterval(start: start, end: end)
    }

    static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nook").appendingPathComponent("calendar-cache.json")
    }

    static func load(from file: URL = defaultFile) -> CalendarCache? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(CalendarCache.self, from: $0) }
    }

    func save(to file: URL = Self.defaultFile) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written to a private temporary file first, so the events are never readable by anyone else, even briefly.
        let scratch = file.deletingLastPathComponent().appendingPathComponent(".calendar-cache-" + UUID().uuidString)
        guard manager.createFile(atPath: scratch.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if (try? manager.replaceItemAt(file, withItemAt: scratch)) == nil { try? manager.removeItem(at: scratch) }
    }
}

/// When a sync may run. Every sync costs the user money, so the rules are few and strict.
enum SyncPolicy {
    enum Reason { case panelOpened, refreshButton, background }

    static let panelMaxAge: TimeInterval = 15 * 60
    static let backgroundInterval: TimeInterval = 60 * 60

    static func shouldSync(_ reason: Reason, lastSync: Date?, lastAttempt: Date? = nil, now: Date, backgroundEnabled: Bool) -> Bool {
        switch reason {
        case .refreshButton: return true
        // Never synced: connecting is the user's own click, not a side effect of opening a panel.
        case .panelOpened: return lastSync.map { now.timeIntervalSince(max($0, lastAttempt ?? $0)) > panelMaxAge } ?? false
        case .background: return nextBackgroundSync(lastSync: lastSync, lastAttempt: lastAttempt, enabled: backgroundEnabled).map { $0 <= now } ?? false
        }
    }

    /// When the one background timer fires; nil when background sync is off or the calendar has
    /// never been synced (the first sync is always the user's own act). A failed attempt counts:
    /// a broken connection is retried hourly, not in a loop.
    static func nextBackgroundSync(lastSync: Date?, lastAttempt: Date?, enabled: Bool) -> Date? {
        guard enabled, let lastSync else { return nil }
        return max(lastSync, lastAttempt ?? lastSync).addingTimeInterval(backgroundInterval)
    }
}

/// What the job said went wrong, turned into words for the panel. The connector's own message is
/// an error text, not calendar data, but it is still shown only to the user and never logged.
enum SyncProblem {
    /// The connector is present but was never granted calendar access. This is the common case,
    /// and no amount of retrying inside Nook fixes it: the grant happens in Claude.
    static let notAuthorised = """
        Your calendar connector is connected to Claude but has not been granted permission to read \
        your calendar, so every request is refused.

        To fix it: open Claude (the desktop or web app) > Settings > Connectors, disconnect Google \
        Calendar, connect it again, and approve calendar access when Google asks. Then press Refresh here.
        """

    /// True when a message is the connector refusing for want of permission, rather than a real fault.
    static func isAuthorisation(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["scope", "unauthor", "not authorized", "not authorised", "permission", "forbidden", "401", "403", "access denied", "consent", "re-authenticate", "reauthenticate"]
        return words.contains { lower.contains($0) }
    }

    /// Nil when the result can be trusted as the calendar's real contents.
    static func message(problem: String?, eventCount: Int) -> String? {
        guard let problem = problem?.trimmingCharacters(in: .whitespacesAndNewlines), !problem.isEmpty, eventCount == 0 else { return nil }
        if isAuthorisation(problem) { return notAuthorised }
        return "The calendar connector reported a problem: " + String(problem.prefix(200))
    }
}
