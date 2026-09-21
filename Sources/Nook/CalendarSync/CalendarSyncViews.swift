import SwiftUI

/// The parts of the calendar panel that show the user's real calendar. Real events are blue and
/// carry a calendar icon; the agent's scheduled prompts stay yellow, its history green.

extension CalendarEvent {
    /// One id can stand for every instance of a repeating event.
    var agendaID: String { "\(id)|\(start.timeIntervalSince1970)" }

    var timeText: String {
        allDay ? "All day" : start.formatted(date: .omitted, time: .shortened) + " – " + end.formatted(date: .omitted, time: .shortened)
    }
}

/// Last sync, what it cost, Refresh; or how to connect a calendar when none is reachable.
struct SyncStrip: View {
    @ObservedObject var model: CalendarModel
    @State private var showOptions = false

    var body: some View {
        if let sync = model.sync {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").foregroundStyle(.blue)
                    Text(summary(sync)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if sync.status.busy {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { sync.cancel() }
                    } else {
                        Button(sync.cache == nil ? "Connect" : "Refresh") { sync.refresh() }
                    }
                    Button { showOptions.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain)
                }
                .controlSize(.small)
                if let note = note(sync) {
                    Text(note).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if showOptions { CalendarOptions() }
            }
            .font(HotspotText.caption)
        }
    }

    private func summary(_ sync: CalendarSync) -> String {
        switch sync.status {
        case .discovering: return "Looking for calendar tools…"
        case .syncing: return "Reading your calendar…"
        default:
            guard let cache = sync.cache else { return "Your calendar is not shown yet" }
            return "Synced " + cache.syncedAt.formatted(.relative(presentation: .named)) + String(format: " · cost about $%.2f", cache.costUSD)
        }
    }

    private func note(_ sync: CalendarSync) -> String? {
        switch sync.status {
        case .notConnected:
            return "Claude Code has no calendar tools. Connect a calendar in Claude (Settings > Connectors, for example Google Calendar), or add a calendar MCP server with `claude mcp add`, then press Connect to retry."
        case .failed(let why):
            return why
        case .idle where sync.cache == nil:
            return "Connect reads your events through your own Claude Code, using its calendar tools only. Each sync is a small paid job."
        case .idle where sync.cache?.truncated == true:
            return "The last sync could not return every event."
        default:
            return nil
        }
    }
}

/// The calendar switches, here because they only make sense next to what they govern. All default
/// to the careful choice.
private struct CalendarOptions: View {
    @AppStorage(CalendarSync.backgroundKey) private var background = false
    @AppStorage(CalendarSync.writesKey) private var writes = false
    @AppStorage(QuietMode.calendarKey) private var quiet = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Sync hourly in the background (each sync costs a little)", isOn: $background)
            Toggle("Quiet mode during my meetings", isOn: $quiet)
            Toggle("Allow \"Add to My Calendar\" (always asks first)", isOn: $writes)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
    }
}

/// One real event in the day's agenda.
struct EventRow: View {
    let event: CalendarEvent
    let model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(event.timeText + (event.calendar.isEmpty ? "" : " · " + event.calendar))
                if event.link != nil { Image(systemName: "video") }
                if event.attendees > 0 { Label("\(event.attendees)", systemImage: "person.2") }
                if !event.busy { Text("free") }
            }
            .font(HotspotText.caption).foregroundStyle(.secondary).lineLimit(1)
            Label(event.title, systemImage: "calendar").font(HotspotText.body).foregroundStyle(.blue).lineLimit(2)
            if !event.allDay, event.start > Date() {
                Button("Schedule a Prompt Before This…") { model.newItem(before: event) }.buttonStyle(.link).font(HotspotText.caption)
            }
        }
    }
}

/// Under a scheduled prompt that is tied to an event.
struct AnchorLine: View {
    let anchor: EventAnchor
    let event: CalendarEvent?

    var body: some View {
        if anchor.orphaned {
            Label("Its event is gone from your calendar, so this prompt was switched off.", systemImage: "link.badge.plus")
                .font(HotspotText.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        } else {
            Label(AnchorText.lead(anchor.lead) + " before " + (event?.title ?? "its event"), systemImage: "link")
                .font(HotspotText.caption).foregroundStyle(.blue).lineLimit(1)
        }
    }
}

enum AnchorText {
    static let choices: [TimeInterval] = [5, 10, 15, 30, 60].map { $0 * 60 }

    static func lead(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes % 60 == 0 && minutes > 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}

/// Replaces the date controls for a prompt tied to an event: the only thing to choose is how long before.
struct AnchorEditor: View {
    @Binding var anchor: EventAnchor
    let event: CalendarEvent?
    let detach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label((event?.title ?? "Calendar event") + " · " + anchor.eventStart.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                .foregroundStyle(.blue).lineLimit(2)
            Picker("Send", selection: $anchor.lead) {
                ForEach(AnchorText.choices, id: \.self) { Text(AnchorText.lead($0) + " before").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                Text("Follows the event if it moves; switched off if it disappears.").font(HotspotText.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Detach", action: detach).buttonStyle(.link).font(HotspotText.caption)
            }
        }
    }
}

/// Shows exactly what "Add to my calendar" would create. Nothing has been sent when this appears.
struct EventConfirmation: View {
    let draft: CalendarBridge.EventDraft
    @ObservedObject var model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD THIS EVENT TO YOUR CALENDAR?").font(HotspotText.heading).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title).font(HotspotText.body.weight(.semibold))
                Text(draft.start.formatted(date: .complete, time: .shortened) + " – " + draft.end.formatted(date: .omitted, time: .shortened))
                Text(draft.notes).foregroundStyle(.secondary)
            }
            .font(HotspotText.body)
            .fixedSize(horizontal: false, vertical: true)
            Text("One event, on your primary calendar, with no guests. It is created by a Claude Code job that may use the calendar's create tool and nothing else. Nook does not change or delete it afterwards.")
                .font(HotspotText.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.writing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { model.confirming = nil }.disabled(model.writing)
                Button("Create Event") { model.createConfirmedEvent() }.disabled(model.writing)
            }
        }
    }
}
