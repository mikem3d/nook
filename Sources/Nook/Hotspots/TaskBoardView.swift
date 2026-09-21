import SwiftUI

/// What one agent's notice board shows: the shared list filtered to that agent. The driver pushes
/// changes in; edits go back through `TaskHub`, the same way the hub's do.
final class TaskBoardModel: ObservableObject {
    private weak var feature: Hotspots?
    private(set) weak var window: AgentWindow?
    let label: String
    let agent: String

    @Published private(set) var tasks: [NookTask] = []
    @Published private(set) var todos: [AgentTodo] = []
    @Published private(set) var auto = false
    @Published private(set) var free = true
    @Published private(set) var now = Date()
    @Published var message = ""
    @Published var limit = TaskScheduler.limit {
        didSet { if limit != oldValue { UserDefaults.standard.set(limit, forKey: TaskScheduler.limitKey) } }
    }
    private var sizeObserver: NSObjectProtocol?

    init(feature: Hotspots, window: AgentWindow) {
        self.feature = feature
        self.window = window
        label = window.session.label
        agent = Hotspots.key(for: window.session)
        sizeObserver = NotificationCenter.default.addObserver(forName: TextSize.changed, object: nil, queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
        reload()
    }

    deinit { sizeObserver.map(NotificationCenter.default.removeObserver) }

    /// The driver calls this on real changes only, never per streamed token.
    func reload() {
        guard let feature, let window else { return }
        tasks = TaskHub.shared.tasks
        todos = window.session.todos
        auto = feature.isAuto(agent)
        free = Hotspots.isFree(window.session)
        now = Date()
    }

    private var mine: [NookTask] { tasks.filter { $0.agent == agent } }
    var out: NookTask? { tasks.out(for: agent) }
    /// Everything waiting, sendable or not, in the order it would go.
    var queued: [NookTask] { mine.filter { $0.status == .queued }.inBoardOrder() }
    var next: NookTask? { tasks.ready(for: agent).first }
    /// Newest first.
    var finished: [NookTask] { mine.filter(\.status.isFinished).sorted { ($0.finished ?? .distantPast) > ($1.finished ?? .distantPast) } }

    func blockText(_ task: NookTask) -> String? {
        tasks.blocker(of: task).map { tasks.blockText($0, labels: TaskHub.shared.label(forAgent:)) }
    }

    func add(_ line: String) { TaskHub.shared.add(line, defaultAgent: agent) }
    func edit(_ change: (inout [NookTask]) -> Void) { TaskHub.shared.edit(change) }
    func sendNext() { message = next.flatMap { TaskHub.shared.sendNow($0.id) } ?? "" }
    func setAuto(_ on: Bool) { feature?.setAuto(on, for: agent) }

    /// A drag within the list. Priority and due date still come first, so a move only sticks among equals.
    func move(from: IndexSet, to: Int) {
        var order = queued.map(\.id)
        order.move(fromOffsets: from, toOffset: to)
        edit { $0.reorder(order) }
    }
}

struct TaskBoardView: View {
    @ObservedObject var model: TaskBoardModel
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Task board: \(model.label)").font(HotspotText.title).lineLimit(1)
            plan
            Divider()
            queue
            Divider()
            controls
            if !model.finished.isEmpty {
                Divider()
                done
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { adding = true }
    }

    // MARK: the agent's own plan

    private var plan: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("AGENT'S PLAN").font(HotspotText.heading).foregroundStyle(.secondary)
            if model.todos.isEmpty {
                Text("No plan reported yet.").font(HotspotText.caption).foregroundStyle(.secondary)
            }
            ScrollView { AgentPlanList(todos: model.todos) }
                .frame(maxHeight: model.todos.isEmpty ? 0 : 120)
        }
    }

    // MARK: the user's queue

    private var queue: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR QUEUE").font(HotspotText.heading).foregroundStyle(.secondary)
            TextField("Add a task:  fix the login bug !high due fri #auth", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(HotspotText.body)
                .focused($adding)
                .onSubmit {
                    model.add(draft)
                    draft = ""
                    adding = true
                }
            if let out = model.out { TaskRow(task: out, now: model.now) }
            // A List, for its drag to reorder.
            List {
                ForEach(model.queued) { task in
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        TaskRow(task: task, block: model.blockText(task), now: model.now)
                        Button { model.edit { $0.cancelOrRemove(task.id, at: Date()) } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Cancel")
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
                .onMove(perform: model.move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 60, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Send Next") { model.sendNext() }
                    .disabled(model.next == nil || !model.free || model.out != nil)
                Spacer()
                Toggle("Auto", isOn: Binding(get: { model.auto }, set: model.setAuto))
                    .toggleStyle(.switch)
                Stepper("up to \(model.limit)", value: $model.limit, in: 1...20).fixedSize()
            }
            .font(HotspotText.body)
            if !model.message.isEmpty { Text(model.message).font(HotspotText.caption).foregroundStyle(.orange) }
            Text(model.auto
                 ? "Auto is on: the next task is sent each time a turn ends well, up to \(model.limit) in a row. Permission questions still wait for you."
                 : "Auto sends the next task each time a turn ends well, with nobody watching. It is off. Priorities, chains and every agent: Task Board in the menu bar.")
                .font(HotspotText.caption)
                .foregroundStyle(model.auto ? .yellow : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DONE").font(HotspotText.heading).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.finished) { TaskRow(task: $0, now: model.now) }
                }
            }
            .frame(maxHeight: 110)
        }
    }
}
