import Foundation

/// One agent's scheduled prompts and the record of the days it worked.
struct AgentCalendar: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        var prompt: String
        var schedule = Schedule()
        var enabled = true
        var lastRun: Date?
        var lastSummary = ""
        var lastFailed = false
        /// Every run up to here has been dealt with: sent, or marked missed.
        var checkedUntil: Date
        /// A run that came due while Nook was closed, the Mac slept or the agent was not open. Never
        /// sent by itself; the panel offers "Run now".
        var missed: Date?
    }

    struct Turn: Codable, Equatable, Identifiable {
        var id = UUID()
        var date: Date
        var summary: String
        var failed: Bool
        /// "Scheduled", "Queued task" or empty for a turn the user started.
        var source: String
    }

    static let historyLimit = 400

    var items: [Item] = []
    /// Oldest first.
    var history: [Turn] = []

    mutating func record(_ turn: Turn) {
        history.append(turn)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    func hasRun(on day: Date, calendar: Calendar = .current) -> Bool {
        items.contains { $0.enabled && $0.schedule.occurs(on: day, calendar: calendar) }
    }
}

/// Decides which scheduled prompts are due, as pure functions of the clock.
enum ScheduleClock {
    /// A run this late (the Mac was asleep) is reported as missed instead of sent hours after its time.
    static let grace: TimeInterval = 15 * 60

    /// Brings `items` up to `now` and returns the ids to send. At launch nothing is ever sent: what
    /// came due while Nook was closed is marked missed. A one-off is switched off once its time has passed.
    static func reconcile(_ items: inout [AgentCalendar.Item], now: Date, launching: Bool, calendar: Calendar = .current) -> [UUID] {
        var due: [UUID] = []
        for index in items.indices where items[index].enabled {
            var item = items[index]
            var latest: Date?
            var cursor = item.checkedUntil
            // A long absence holds many runs; only the most recent one matters. Bounded, in case of a bad clock.
            for _ in 0..<1000 {
                guard let run = item.schedule.next(after: cursor, calendar: calendar), run <= now else { break }
                latest = run
                cursor = run
            }
            item.checkedUntil = max(item.checkedUntil, now)
            if let latest {
                if launching || now.timeIntervalSince(latest) > grace { item.missed = latest } else { due.append(item.id) }
                if item.schedule.kind == .once { item.enabled = false }
            }
            items[index] = item
        }
        return due
    }

    /// When the single timer should fire next; nil with nothing scheduled.
    static func nextWake(_ items: [AgentCalendar.Item], calendar: Calendar = .current) -> Date? {
        items.filter(\.enabled).compactMap { $0.schedule.next(after: $0.checkedUntil, calendar: calendar) }.min()
    }
}
