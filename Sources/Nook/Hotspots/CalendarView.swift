import SwiftUI

/// What the calendar panel shows. The feature pushes changes in; the view sends edits back through it.
final class CalendarModel: ObservableObject {
    private weak var feature: Hotspots?
    private(set) weak var window: AgentWindow?
    let label: String

    @Published private(set) var calendar = AgentCalendar()
    @Published var month = Date()
    @Published var selected: Date?
    /// The item in the editor; nil while the list shows.
    @Published var editing: AgentCalendar.Item?
    private var sizeObserver: NSObjectProtocol?

    init(feature: Hotspots, window: AgentWindow) {
        self.feature = feature
        self.window = window
        label = window.session.label
        sizeObserver = NotificationCenter.default.addObserver(forName: TextSize.changed, object: nil, queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
        reload()
    }

    deinit { sizeObserver.map(NotificationCenter.default.removeObserver) }

    func reload() {
        guard let feature, let window else { return }
        let now = feature.calendar(for: window)
        if now != calendar { calendar = now }
    }

    func newItem() {
        var schedule = Schedule()
        schedule.date = Date().addingTimeInterval(3600)
        editing = AgentCalendar.Item(prompt: "", schedule: schedule, checkedUntil: Date())
    }

    /// Saving counts every earlier run as dealt with: moving a time to earlier today must not send
    /// it at once, and nothing is "missed" from before the schedule existed in this form.
    func save(_ item: AgentCalendar.Item) {
        var item = item
        item.prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.prompt.isEmpty else { return }
        item.checkedUntil = Date()
        item.missed = nil
        edit { calendar in
            if let index = calendar.items.firstIndex(where: { $0.id == item.id }) { calendar.items[index] = item } else { calendar.items.append(item) }
        }
        editing = nil
    }

    func delete(_ id: UUID) {
        edit { $0.items.removeAll { $0.id == id } }
        editing = nil
    }

    func setEnabled(_ on: Bool, _ id: UUID) {
        edit { calendar in
            guard let index = calendar.items.firstIndex(where: { $0.id == id }) else { return }
            calendar.items[index].enabled = on
            if on { calendar.items[index].checkedUntil = Date() }
        }
    }

    func dismissMissed(_ id: UUID) {
        edit { calendar in
            if let index = calendar.items.firstIndex(where: { $0.id == id }) { calendar.items[index].missed = nil }
        }
    }

    func runNow(_ id: UUID) { window.map { feature?.runNow(id, on: $0) } }

    private func edit(_ change: (inout AgentCalendar) -> Void) { window.map { feature?.editCalendar($0, change) } }

    // MARK: what the view reads

    /// Enabled items by their next run; items with nothing left to run come last.
    var upcoming: [(item: AgentCalendar.Item, next: Date?)] {
        let now = Date()
        return calendar.items.map { ($0, $0.enabled ? $0.schedule.next(after: now) : nil) }
            .sorted { ($0.1 ?? .distantFuture, $0.0.prompt) < ($1.1 ?? .distantFuture, $1.0.prompt) }
    }

    func turns(on day: Date) -> [AgentCalendar.Turn] {
        calendar.history.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    /// Schedule dots only from today on: a repeating schedule says nothing about days gone by.
    func isScheduled(_ day: Date) -> Bool {
        day >= Calendar.current.startOfDay(for: Date()) && calendar.hasRun(on: day)
    }
}

struct CalendarView: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar: \(model.label)").font(HotspotText.title).lineLimit(1)
            if let item = model.editing {
                ScheduleEditor(item: item, isNew: !model.calendar.items.contains { $0.id == item.id }, model: model)
            } else {
                monthView
                Divider()
                if let day = model.selected { dayDetail(day) } else { upcoming }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: month

    private var monthView: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        return VStack(spacing: 6) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(model.month.formatted(.dateTime.month(.wide).year())).font(HotspotText.body.weight(.semibold))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, name in
                    Text(name).font(HotspotText.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(MonthGrid.days(of: model.month).enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 1) }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = model.selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let worked = !model.turns(on: day).isEmpty
        return Button {
            model.selected = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))").font(HotspotText.day)
                HStack(spacing: 3) {
                    Circle().fill(worked ? Color.green : .clear).frame(width: 5, height: 5)
                    Circle().fill(model.isScheduled(day) ? Color.yellow : .clear).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.35) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(calendar.isDateInToday(day) ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shift(_ months: Int) {
        model.month = Calendar.current.date(byAdding: .month, value: months, to: model.month) ?? model.month
        model.selected = nil
    }

    // MARK: lists

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SCHEDULED PROMPTS").font(HotspotText.heading).foregroundStyle(.secondary)
                Spacer()
                Button("Add…") { model.newItem() }
            }
            if model.calendar.items.isEmpty {
                Text("Nothing scheduled. A scheduled prompt is sent to this agent at its time, while Nook is running, with nobody watching.")
                    .font(HotspotText.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(model.upcoming, id: \.item.id) { entry in row(entry.item, next: entry.next) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ item: AgentCalendar.Item, next: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Toggle("", isOn: Binding(get: { item.enabled }, set: { model.setEnabled($0, item.id) })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                Text(item.prompt).font(HotspotText.body).lineLimit(2)
                Spacer()
                Button("Edit") { model.editing = item }.buttonStyle(.link)
            }
            Text(item.schedule.summary() + (next.map { " · next " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
                .font(HotspotText.caption).foregroundStyle(.secondary)
            if let last = item.lastRun {
                Text("Last run " + last.formatted(date: .abbreviated, time: .shortened) + (item.lastSummary.isEmpty ? "" : ": " + item.lastSummary))
                    .font(HotspotText.caption).foregroundStyle(item.lastFailed ? .red : .secondary).lineLimit(2)
            }
            if let missed = item.missed {
                HStack {
                    Label("Missed " + missed.formatted(date: .abbreviated, time: .shortened), systemImage: "exclamationmark.circle.fill")
                        .font(HotspotText.caption).foregroundStyle(.orange)
                    Spacer()
                    Button("Run Now") { model.runNow(item.id) }
                    Button("Dismiss") { model.dismissMissed(item.id) }
                }
                .controlSize(.small)
            }
        }
    }

    private func dayDetail(_ day: Date) -> some View {
        let turns = model.turns(on: day)
        let planned = model.calendar.items.filter { $0.enabled && model.isScheduled(day) && $0.schedule.occurs(on: day) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.formatted(date: .complete, time: .omitted).uppercased()).font(HotspotText.heading).foregroundStyle(.secondary)
                Spacer()
                Button("All Scheduled") { model.selected = nil }.buttonStyle(.link)
            }
            if turns.isEmpty && planned.isEmpty {
                Text("Nothing happened and nothing is planned.").font(HotspotText.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(planned) { item in
                        Label(item.prompt + " · " + item.schedule.summary(), systemImage: "clock").font(HotspotText.body).foregroundStyle(.yellow).lineLimit(2)
                    }
                    ForEach(turns) { turn in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(turn.date.formatted(date: .omitted, time: .shortened) + (turn.source.isEmpty ? "" : " · " + turn.source))
                                .font(HotspotText.caption).foregroundStyle(.secondary)
                            Text(turn.summary.isEmpty ? "Turn finished" : turn.summary)
                                .font(HotspotText.body).foregroundStyle(turn.failed ? .red : .primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The editor for one scheduled prompt. Field-style pickers only: a popover would take the keyboard
/// from the panel, and a panel that loses the keyboard closes.
private struct ScheduleEditor: View {
    @State var item: AgentCalendar.Item
    let isNew: Bool
    let model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "NEW SCHEDULED PROMPT" : "EDIT SCHEDULED PROMPT").font(HotspotText.heading).foregroundStyle(.secondary)
            TextField("What should the agent do?", text: $item.prompt, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .font(HotspotText.body)
            Picker("", selection: $item.schedule.kind) {
                Text("Once").tag(Schedule.Kind.once)
                Text("Daily").tag(Schedule.Kind.daily)
                Text("Weekdays").tag(Schedule.Kind.weekdays)
                Text("Weekly").tag(Schedule.Kind.weekly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if item.schedule.kind == .once {
                DatePicker("On", selection: $item.schedule.date, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.field)
            } else {
                DatePicker("At", selection: time, displayedComponents: .hourAndMinute).datePickerStyle(.field)
            }
            if item.schedule.kind == .weekly { weekdays }
            Toggle("Enabled", isOn: $item.enabled)
            Text("Sent only while Nook is running. A run that comes due while Nook is closed or the Mac sleeps is shown as missed, never sent late by itself. It waits for a turn in progress or a permission question to finish.")
                .font(HotspotText.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if !isNew { Button("Delete", role: .destructive) { model.delete(item.id) } }
                Spacer()
                Button("Cancel") { model.editing = nil }
                Button("Save") { model.save(item) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (item.schedule.kind == .weekly && item.schedule.days.isEmpty))
            }
        }
        .font(HotspotText.body)
    }

    /// The hour and minute as a date today, which is what a DatePicker edits.
    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: item.schedule.hour, minute: item.schedule.minute, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            item.schedule.hour = parts.hour ?? item.schedule.hour
            item.schedule.minute = parts.minute ?? item.schedule.minute
        })
    }

    private var weekdays: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { ($0 + calendar.firstWeekday - 1) % 7 + 1 }
        return HStack(spacing: 4) {
            ForEach(order, id: \.self) { day in
                let on = item.schedule.days.contains(day)
                Button(calendar.shortWeekdaySymbols[day - 1]) {
                    if on { item.schedule.days.remove(day) } else { item.schedule.days.insert(day) }
                }
                .buttonStyle(.plain)
                .font(HotspotText.caption)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08)))
            }
        }
    }
}
