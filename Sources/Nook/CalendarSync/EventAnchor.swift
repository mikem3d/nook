import Foundation

/// Ties a scheduled prompt to a real event: "10 minutes before the standup". Holds the event's id
/// and time only, never its title; the panel looks the title up in the cache.
struct EventAnchor: Codable, Equatable {
    var eventID: String
    /// The event's start when last seen. Tells a repeating event's instances apart, and says
    /// whether a sync that lacks the event looked at its day at all.
    var eventStart: Date
    /// How long before the event starts the prompt is sent.
    var lead: TimeInterval
    /// The event was gone from a sync that covered its day. The prompt stays, switched off, for the user to decide.
    var orphaned = false

    var runDate: Date { eventStart.addingTimeInterval(-lead) }
}

/// Keeps anchored prompts in step with the calendar after each sync. Pure.
enum EventAnchoring {
    static func item(prompt: String, before event: CalendarEvent, lead: TimeInterval, now: Date) -> AgentCalendar.Item {
        let anchor = EventAnchor(eventID: event.id, eventStart: event.start, lead: lead)
        return AgentCalendar.Item(prompt: prompt, schedule: Schedule(kind: .once, date: anchor.runDate), checkedUntil: now, anchor: anchor)
    }

    /// An event that moved takes its prompt along. An event that disappeared from inside the synced
    /// window orphans its prompt, which is switched off rather than sent before a meeting that is
    /// not happening. Outside the window, or after a sync that could not return everything,
    /// nothing is known, so nothing changes.
    static func reanchor(_ items: inout [AgentCalendar.Item], events: [CalendarEvent], window: DateInterval, complete: Bool = true, now: Date) {
        for index in items.indices {
            guard var anchor = items[index].anchor else { continue }
            let candidates = events.filter { $0.id == anchor.eventID }
            if let event = candidates.min(by: { abs($0.start.timeIntervalSince(anchor.eventStart)) < abs($1.start.timeIntervalSince(anchor.eventStart)) }) {
                let moved = event.start != anchor.eventStart
                let wasOrphaned = anchor.orphaned
                guard moved || wasOrphaned else { continue }
                anchor.eventStart = event.start
                anchor.orphaned = false
                items[index].anchor = anchor
                items[index].schedule = Schedule(kind: .once, date: anchor.runDate)
                // Only what the orphaning switched off comes back on; the user's own "off" stays off.
                if wasOrphaned, anchor.runDate > now {
                    items[index].enabled = true
                    items[index].checkedUntil = now
                }
            } else if complete, !anchor.orphaned, window.contains(anchor.eventStart), anchor.runDate > now {
                anchor.orphaned = true
                items[index].anchor = anchor
                items[index].enabled = false
            }
        }
    }
}
