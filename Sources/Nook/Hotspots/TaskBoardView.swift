import SwiftUI

/// What the task board panel shows. The feature pushes changes in; the view sends edits back through it.
final class TaskBoardModel: ObservableObject {
    private weak var feature: Hotspots?
    private(set) weak var window: AgentWindow?
    let label: String

    @Published private(set) var queue = TaskQueue()
    @Published private(set) var todos: [AgentTodo] = []
    @Published private(set) var auto = false
    @Published private(set) var free = true
    @Published var limit = AutoRun.limit {
        didSet { if limit != oldValue { UserDefaults.standard.set(limit, forKey: AutoRun.limitKey) } }
    }
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
        queue = feature.queue(for: window)
        todos = window.session.todos
        auto = feature.isAuto(window)
        reloadStatus()
    }

    /// Session changes arrive many times a second while an agent streams; only a real change redraws.
    func reloadStatus() {
        guard let window else { return }
        let now = Hotspots.isFree(window.session)
        if now != free { free = now }
    }

    func edit(_ change: (inout TaskQueue) -> Void) { window.map { feature?.editQueue($0, change) } }
    func sendNext() { window.map { feature?.sendNext($0) } }
    func setAuto(_ on: Bool) { window.map { feature?.setAuto(on, for: $0) } }
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
            if !model.queue.done.isEmpty {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(model.todos.enumerated()), id: \.offset) { _, todo in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: Self.icon(todo.status)).foregroundStyle(Self.tint(todo.status)).frame(width: 18)
                            Text(todo.status == .inProgress ? todo.activeForm : todo.content)
                                .font(HotspotText.body)
                                .strikethrough(todo.status == .completed)
                                .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: model.todos.isEmpty ? 0 : 120)
        }
    }

    private static func icon(_ status: AgentTodo.Status) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "arrow.right.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private static func tint(_ status: AgentTodo.Status) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .yellow
        case .completed: return .green
        }
    }

    // MARK: the user's queue

    private var queue: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR QUEUE").font(HotspotText.heading).foregroundStyle(.secondary)
            TextField("Add a task for this agent", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(HotspotText.body)
                .focused($adding)
                .onSubmit {
                    model.edit { $0.add(draft) }
                    draft = ""
                    adding = true
                }
            if let sending = model.queue.sending {
                Label(sending.text, systemImage: "paperplane.fill").font(HotspotText.body).foregroundStyle(.yellow).lineLimit(2)
            }
            // A List, for its drag to reorder.
            List {
                ForEach(model.queue.queued) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        TextField("Task", text: Binding(get: { item.text }, set: { text in
                            model.edit { queue in
                                if let index = queue.queued.firstIndex(where: { $0.id == item.id }) { queue.queued[index].text = text }
                            }
                        }))
                        .textFieldStyle(.plain)
                        .font(HotspotText.body)
                        Button { model.edit { $0.queued.removeAll { $0.id == item.id } } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Delete")
                    }
                }
                .onMove { from, to in model.edit { $0.queued.move(fromOffsets: from, toOffset: to) } }
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
                    .disabled(model.queue.queued.isEmpty || !model.free || model.queue.sending != nil)
                Spacer()
                Toggle("Auto", isOn: Binding(get: { model.auto }, set: model.setAuto))
                    .toggleStyle(.switch)
                Stepper("up to \(model.limit)", value: $model.limit, in: 1...20).fixedSize()
            }
            .font(HotspotText.body)
            Text(model.auto
                 ? "Auto is on: the next task is sent each time a turn ends well, up to \(model.limit) in a row. Permission questions still wait for you."
                 : "Auto sends the next task each time a turn ends well, with nobody watching. It is off.")
                .font(HotspotText.caption)
                .foregroundStyle(model.auto ? .yellow : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DONE").font(HotspotText.heading).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(model.queue.done) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Image(systemName: item.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(item.failed ? .red : .green)
                                Text(item.text).font(HotspotText.body).lineLimit(1)
                            }
                            Text((item.automatic ? "Auto · " : "") + item.finished.formatted(date: .abbreviated, time: .shortened)
                                 + (item.summary.isEmpty ? "" : " · " + item.summary))
                                .font(HotspotText.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
    }
}
