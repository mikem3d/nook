import SwiftUI

/// The board across every agent: the inbox and one column per agent, with the editor beside them.
struct TaskHubView: View {
    @ObservedObject var model: TaskHubModel
    let close: () -> Void
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: 12) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(model.columns) { column in
                            HubColumnView(model: model, column: column)
                        }
                    }
                }
                if let id = model.editing, let task = model.tasks.task(id) {
                    Divider()
                    TaskEditorView(model: model, draft: task).id(id)
                        .frame(width: TextSize.metric(320))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .padding(16)
        .onAppear { adding = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Task Board").font(HotspotText.title)
                Spacer()
                Picker("Show", selection: $model.filter.show) {
                    Text("Open").tag(TaskFilter.Show.open)
                    Text("All").tag(TaskFilter.Show.all)
                    Divider()
                    ForEach(NookTask.Status.allCases, id: \.self) { Text($0.rawValue.capitalized).tag(TaskFilter.Show.only($0)) }
                }
                Picker("Priority", selection: $model.filter.priority) {
                    Text("Any").tag(NookTask.Priority.none)
                    ForEach([NookTask.Priority.low, .medium, .high, .urgent], id: \.self) { Text($0.title + " and up").tag($0) }
                }
                Picker("Tag", selection: $model.filter.tag) {
                    Text("Any").tag(String?.none)
                    ForEach(model.tags, id: \.self) { Text("#" + $0).tag(String?.some($0)) }
                }
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Close (Esc)")
            }
            .font(HotspotText.body)
            .fixedSize(horizontal: false, vertical: true)
            TextField("Add a task:  fix the login bug @agent !high due fri #auth", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(HotspotText.body)
                .focused($adding)
                .onSubmit {
                    model.add(draft)
                    draft = ""
                    adding = true
                }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.message.isEmpty ? "↑↓←→ select · Return edit · ⌘Return send now · Delete cancel · drag a task onto an agent to assign it" : model.message)
                .font(HotspotText.caption)
                .foregroundStyle(model.message.isEmpty ? Color.secondary : Color.orange)
                .lineLimit(1)
            Spacer()
            Stepper("Auto sends up to \(model.limit) in a row", value: $model.limit, in: 1...20).font(HotspotText.caption).fixedSize()
        }
    }
}

/// The inbox or one agent: its state, its own plan, and its tasks. Dropping a task here assigns it.
private struct HubColumnView: View {
    @ObservedObject var model: TaskHubModel
    let column: HubLayout.Column
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if let todos = column.agent?.todos, !todos.isEmpty {
                        Text("AGENT'S PLAN").font(HotspotText.heading).foregroundStyle(.secondary)
                        AgentPlanList(todos: todos)
                        Divider()
                    }
                    ForEach(column.tasks) { task in row(task) }
                    if column.tasks.isEmpty {
                        Text(column.agent == nil ? "Tasks with no agent wait here." : "Nothing here.")
                            .font(HotspotText.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: TextSize.metric(250), alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(targeted ? 0.14 : 0.04)))
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            model.assign(id, to: column.agent?.key)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(column.agent?.label ?? "Inbox").font(HotspotText.body.weight(.semibold)).lineLimit(1)
                Spacer()
                if let agent = column.agent, agent.state != nil {
                    Toggle("Auto", isOn: Binding(get: { agent.auto }, set: { model.setAuto($0, for: agent.key) }))
                        .toggleStyle(.switch).controlSize(.mini).font(HotspotText.caption)
                        .help("Send this agent's queued tasks as each turn ends well, with nobody watching. Off at every launch.")
                }
            }
            if let agent = column.agent {
                Text(Self.stateText(agent)).font(HotspotText.caption).foregroundStyle(agent.auto ? Color.yellow : Color.secondary)
            }
        }
    }

    private static func stateText(_ agent: HubAgent) -> String {
        guard let state = agent.state else { return "Closed: nothing is sent until it is open" }
        let text: String
        switch state {
        case .idle: text = "Idle"
        case .busy: text = "Working"
        case .pendingPermission: text = "Waiting for your permission"
        case .lastTurnFailed: text = "Idle: the last turn did not end well"
        }
        return text + (agent.auto ? " · auto is on" : "")
    }

    private func row(_ task: NookTask) -> some View {
        TaskRow(task: task, block: model.blockText(task), now: model.now, selected: model.selection == task.id)
            .onTapGesture(count: 2) {
                model.selection = task.id
                model.editing = task.id
            }
            .onTapGesture { model.selection = task.id }
            .draggable(task.id.uuidString)
            .contextMenu {
                Button("Edit…") { model.editing = task.id }
                if task.status == .queued { Button("Send Now") { model.send(task.id) } }
                if task.status.isFinished, task.status != .done { Button("Queue Again") { model.edit { $0.requeue(task.id) } } }
                if !task.status.isOut {
                    Menu("Assign To") {
                        Button("Inbox") { model.assign(task.id, to: nil) }
                        ForEach(model.agents) { agent in Button(agent.label) { model.assign(task.id, to: agent.key) } }
                    }
                    Button(task.status == .queued ? "Cancel" : "Remove") { model.cancel(task.id) }
                }
            }
    }
}

/// The editor works on a copy; Save writes it back, refusing a chain that would loop.
struct TaskEditorView: View {
    @ObservedObject var model: TaskHubModel
    @State var draft: NookTask
    @State private var tags = ""
    @State private var problem = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("EDIT TASK").font(HotspotText.heading).foregroundStyle(.secondary)
                TextField("Title", text: $draft.title).textFieldStyle(.roundedBorder)
                Text("Notes, sent to the agent under the title").font(HotspotText.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.notes).frame(height: TextSize.metric(90))
                    .scrollContentBackground(.hidden).background(Color.primary.opacity(0.06)).cornerRadius(6)
                Picker("Priority", selection: $draft.priority) {
                    ForEach(NookTask.Priority.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Agent", selection: $draft.agent) {
                    Text("Inbox").tag(String?.none)
                    ForEach(model.agents) { Text($0.label).tag(String?.some($0.key)) }
                }
                .disabled(draft.status.isOut)
                due
                TextField("Tags, separated by spaces", text: $tags).textFieldStyle(.roundedBorder)
                Divider()
                chain
                Divider()
                status
                if !problem.isEmpty { Text(problem).font(HotspotText.caption).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") { model.editing = nil }
                    Spacer()
                    Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .font(HotspotText.body)
        }
        .onAppear { tags = draft.tags.joined(separator: " ") }
    }

    private var due: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Due date", isOn: Binding(get: { draft.due != nil }, set: { draft.due = $0 ? (draft.due ?? Date()) : nil }))
            if draft.due != nil {
                let date = Binding(get: { draft.due ?? Date() }, set: { draft.due = $0 })
                DatePicker("Day", selection: date, displayedComponents: .date)
                Toggle("At a time", isOn: $draft.dueHasTime)
                if draft.dueHasTime { DatePicker("Time", selection: date, displayedComponents: .hourAndMinute) }
            }
        }
    }

    private var chain: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WAITS ON").font(HotspotText.heading).foregroundStyle(.secondary)
            ForEach(draft.after, id: \.self) { id in
                HStack {
                    Text(title(id)).font(HotspotText.caption).lineLimit(2)
                    Spacer()
                    Button { draft.after.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            // Only tasks that would not close a loop are offered; Save checks again.
            let candidates = model.tasks.filter { other in
                other.id != draft.id && !draft.after.contains(other.id) && other.status != .cancelled
                    && !model.tasks.wouldCycle(draft.id, waitingOn: other.id)
            }
            Menu("Add a task to wait on") {
                ForEach(candidates) { other in Button(title(other.id)) { draft.after.append(other.id) } }
            }
            .disabled(candidates.isEmpty || draft.status != .queued)
            Toggle("Run automatically when unblocked", isOn: $draft.autoRun).disabled(draft.after.isEmpty)
            Text("When everything it waits on has finished well, Nook sends it with their results as context, even if this agent's auto queue is off. It never runs past a failure, and it counts toward the automatic limit.")
                .font(HotspotText.caption).foregroundStyle(draft.autoRun && !draft.after.isEmpty ? Color.yellow : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status: \(draft.status.rawValue)" + (draft.result.isEmpty ? "" : " · " + draft.result))
                .font(HotspotText.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if draft.status == .queued { Button("Send Now") { if save() { model.send(draft.id) } } }
                if draft.status.isFinished, draft.status != .done {
                    Button("Queue Again") {
                        model.edit { $0.requeue(draft.id) }
                        model.editing = nil
                    }
                }
                if !draft.status.isOut {
                    Button(draft.status == .queued ? "Cancel Task" : "Remove") { model.cancel(draft.id) }
                }
            }
        }
    }

    private func title(_ id: UUID) -> String {
        guard let task = model.tasks.task(id) else { return "A deleted task" }
        return task.title + " · " + (task.agent.map(model.label) ?? "Inbox") + " · " + task.status.rawValue
    }

    @discardableResult
    private func save() -> Bool {
        var saved = true
        let words = tags.lowercased().split(whereSeparator: { $0 == " " || $0 == "," || $0 == "#" }).map(String.init)
        model.edit { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == draft.id }) else { return }
            guard tasks.setPrerequisites(draft.after, of: draft.id) else {
                saved = false
                return
            }
            // Only what the editor edits: the task may have been sent or finished while it was open.
            var task = tasks[index]
            (task.title, task.notes, task.priority) = (draft.title.trimmingCharacters(in: .whitespacesAndNewlines), draft.notes, draft.priority)
            (task.due, task.dueHasTime, task.tags) = (draft.due, draft.due != nil && draft.dueHasTime, words.reduce(into: []) { if !$0.contains($1) { $0.append($1) } })
            task.autoRun = draft.autoRun && !task.after.isEmpty
            if !task.status.isOut { task.agent = draft.agent }
            tasks[index] = task
        }
        problem = saved ? "" : "That would make a loop: one of those tasks already waits on this one."
        if saved { model.editing = nil }
        return saved
    }
}
