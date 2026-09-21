import SwiftUI

/// How the hub lays the list out, and how the keyboard moves through it. Pure, so it is unit tested.
enum HubLayout {
    struct Column: Equatable, Identifiable {
        /// nil is the inbox.
        var agent: HubAgent?
        var tasks: [NookTask]

        var id: String { agent?.key ?? "" }
    }

    enum Move { case up, down, left, right }

    /// The inbox, then one column per agent, each in board order. A task assigned to an agent that
    /// is not listed still shows, in the inbox, rather than disappearing.
    static func columns(tasks: [NookTask], agents: [HubAgent], filter: TaskFilter) -> [Column] {
        let shown = tasks.filter(filter.matches).inBoardOrder()
        let known = Set(agents.map(\.key))
        let inbox = shown.filter { $0.agent.map { !known.contains($0) } ?? true }
        return [Column(agent: nil, tasks: inbox)] + agents.map { agent in Column(agent: agent, tasks: shown.filter { $0.agent == agent.key }) }
    }

    /// The task the selection moves to. Sideways it lands on the same row of the next column that
    /// has any tasks; with nothing selected, any move picks the first task on the board.
    static func move(_ selection: UUID?, _ move: Move, in columns: [[UUID]]) -> UUID? {
        guard let selection, let column = columns.firstIndex(where: { $0.contains(selection) }),
              let row = columns[column].firstIndex(of: selection) else { return columns.first { !$0.isEmpty }?.first }
        switch move {
        case .up: return columns[column][max(row - 1, 0)]
        case .down: return columns[column][min(row + 1, columns[column].count - 1)]
        case .left, .right:
            let step = move == .left ? -1 : 1
            var next = column + step
            while columns.indices.contains(next), columns[next].isEmpty { next += step }
            guard columns.indices.contains(next) else { return selection }
            return columns[next][min(row, columns[next].count - 1)]
        }
    }
}

/// What the hub panel shows. The hub pushes changes in; the view sends the user's actions back through it.
final class TaskHubModel: ObservableObject {
    enum Key { case move(HubLayout.Move), edit, send, cancel }

    private weak var hub: TaskHub?
    @Published private(set) var tasks: [NookTask] = []
    @Published private(set) var agents: [HubAgent] = []
    @Published private(set) var now = Date()
    @Published var filter = TaskFilter()
    @Published var selection: UUID?
    /// The task open in the editor.
    @Published var editing: UUID?
    /// Why the last action did nothing.
    @Published var message = ""
    @Published var limit = TaskScheduler.limit {
        didSet { if limit != oldValue { UserDefaults.standard.set(limit, forKey: TaskScheduler.limitKey) } }
    }
    private var sizeObserver: NSObjectProtocol?

    init(hub: TaskHub) {
        self.hub = hub
        sizeObserver = NotificationCenter.default.addObserver(forName: TextSize.changed, object: nil, queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
        reloadTasks()
        reloadAgents()
    }

    deinit { sizeObserver.map(NotificationCenter.default.removeObserver) }

    func reloadTasks() {
        guard let hub else { return }
        tasks = hub.tasks
        now = Date()
        if let selection, tasks.task(selection) == nil { self.selection = nil }
        if let editing, tasks.task(editing) == nil { self.editing = nil }
        reloadAgents() // a closed agent is listed only while it has tasks
    }

    func reloadAgents() {
        guard let hub else { return }
        let fresh = hub.agents()
        if fresh != agents { agents = fresh }
    }

    var columns: [HubLayout.Column] { HubLayout.columns(tasks: tasks, agents: agents, filter: filter) }
    var tags: [String] { Array(Set(tasks.flatMap(\.tags))).sorted() }

    func label(_ key: String) -> String { agents.first { $0.key == key }?.label ?? NookTask.label(forAgent: key) }

    func blockText(_ task: NookTask) -> String? {
        guard task.status == .queued else { return nil }
        return tasks.blocker(of: task).map { tasks.blockText($0, labels: label) }
    }

    // MARK: actions

    func add(_ line: String) {
        if let task = hub?.add(line) { selection = task.id }
    }

    func edit(_ change: (inout [NookTask]) -> Void) { hub?.edit(change) }

    func assign(_ id: UUID, to agent: String?) {
        edit { tasks in
            // A task that is with an agent stays where it is.
            if let index = tasks.firstIndex(where: { $0.id == id }), !tasks[index].status.isOut { tasks[index].agent = agent }
        }
    }

    func send(_ id: UUID) { message = hub?.sendNow(id) ?? "" }

    func cancel(_ id: UUID) {
        let next = HubLayout.move(id, .down, in: columns.map { $0.tasks.map(\.id) })
        var changed = false
        edit { changed = $0.cancelOrRemove(id, at: Date()) }
        message = changed ? "" : "It is with the agent now and cannot be cancelled"
        if changed, tasks.task(id) == nil || !filter.matches(tasks.task(id)!) { selection = next == id ? nil : next }
    }

    func setAuto(_ on: Bool, for agent: String) { hub?.setAuto(on, for: agent) }

    /// A key the panel did not give to a text field. Returns false to let it through.
    func handle(_ key: Key) -> Bool {
        switch key {
        case .move(let move):
            selection = HubLayout.move(selection, move, in: columns.map { $0.tasks.map(\.id) })
        case .edit:
            guard let selection else { return false }
            editing = selection
        case .send:
            guard let selection else { return false }
            send(selection)
        case .cancel:
            guard let selection else { return false }
            cancel(selection)
        }
        return true
    }
}
