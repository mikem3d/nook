import Foundation

/// One piece of work the user wants done. Tasks live in a single list (see `TaskStore`); the hub
/// and each agent's notice board are views of it.
struct NookTask: Codable, Equatable, Identifiable {
    enum Priority: Int, Codable, CaseIterable, Comparable {
        case none, low, medium, high, urgent

        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .urgent: return "Urgent"
            }
        }
    }

    enum Status: String, Codable, CaseIterable {
        /// Waiting to be sent.
        case queued
        /// Handed to the agent; its turn has not visibly started.
        case sent
        case running
        case done, failed, cancelled

        /// With the agent now.
        var isOut: Bool { self == .sent || self == .running }
        var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
    }

    var id = UUID()
    /// What is sent to the agent, with `notes` under it.
    var title: String
    var notes = ""
    var priority = Priority.none
    var due: Date?
    /// False when only a day was given: the task is then due by the end of that day.
    var dueHasTime = false
    /// The assigned agent's folder path (`Hotspots.key`); nil while the task is in the inbox.
    var agent: String?
    var status = Status.queued
    var created = Date()
    var sent: Date?
    var finished: Date?
    /// `session.summary` of the turn that handled it, or why it never ran.
    var result = ""
    /// Tasks that must finish successfully first, on any agent.
    var after: [UUID] = []
    var tags: [String] = []
    /// The user's explicit "run automatically when unblocked". Only counts while `after` is not empty.
    var autoRun = false
    /// Sent by Nook rather than by the user's own click.
    var automatic = false

    /// The moment it becomes overdue.
    func deadline(_ calendar: Calendar = .current) -> Date? {
        guard let due else { return nil }
        if dueHasTime { return due }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due))
    }

    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !status.isFinished, let deadline = deadline(calendar) else { return false }
        return now >= deadline
    }

    func isDueToday(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !status.isFinished, let due, !isOverdue(at: now, calendar: calendar) else { return false }
        return calendar.isDate(due, inSameDayAs: now)
    }

    /// "Fri 25 Sep", with the time only when one was given.
    func dueText(_ calendar: Calendar = .current) -> String? {
        guard let due else { return nil }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        if dueHasTime { style = style.hour().minute() }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return due.formatted(style)
    }

    /// The folder's name, for an agent that is not open to ask for its label.
    static func label(forAgent key: String) -> String {
        key.hasPrefix("demo:") ? String(key.dropFirst(5)) : URL(fileURLWithPath: key).lastPathComponent
    }
}

/// Why a queued task cannot be sent yet.
enum TaskBlock: Equatable {
    /// Prerequisites that have not finished.
    case waiting([UUID])
    /// A prerequisite failed or was cancelled. Nothing runs past it until the user steps in.
    case broken(UUID, NookTask.Status)
    /// A prerequisite was deleted before it succeeded.
    case missing
}

/// The rules of the board, as pure functions over the one list of tasks.
extension Array where Element == NookTask {
    func task(_ id: UUID) -> NookTask? { first { $0.id == id } }

    func blocker(of task: NookTask) -> TaskBlock? {
        var waiting: [UUID] = []
        for id in task.after {
            guard let other = self.task(id) else { return .missing }
            switch other.status {
            case .done: continue
            case .failed, .cancelled: return .broken(id, other.status)
            case .queued, .sent, .running: waiting.append(id)
            }
        }
        return waiting.isEmpty ? nil : .waiting(waiting)
    }

    /// In words, for the row and the editor.
    func blockText(_ block: TaskBlock, labels: (String) -> String = NookTask.label(forAgent:)) -> String {
        func name(_ id: UUID) -> String {
            guard let other = task(id) else { return "a deleted task" }
            return "“\(other.title)”" + (other.agent.map { " (\(labels($0)))" } ?? " (inbox)")
        }
        switch block {
        case .waiting(let ids): return "Waits on " + ids.map(name).joined(separator: ", ")
        case .broken(let id, let status): return "Blocked: \(name(id)) \(status == .failed ? "failed" : "was cancelled")"
        case .missing: return "Blocked: a task it waited on was deleted before it succeeded"
        }
    }

    /// True if making `task` wait on `prerequisite` would close a loop (or is the task itself).
    func wouldCycle(_ task: UUID, waitingOn prerequisite: UUID) -> Bool {
        var (stack, visited) = ([prerequisite], Set<UUID>())
        while let id = stack.popLast() {
            if id == task { return true }
            guard visited.insert(id).inserted else { continue }
            stack.append(contentsOf: self.task(id)?.after ?? [])
        }
        return false
    }

    /// Sets a task's prerequisites, refusing a loop. Returns false, changing nothing, if there is one.
    mutating func setPrerequisites(_ ids: [UUID], of task: UUID) -> Bool {
        guard let index = firstIndex(where: { $0.id == task }) else { return false }
        if ids.contains(where: { wouldCycle(task, waitingOn: $0) }) { return false }
        var unique: [UUID] = []
        for id in ids where !unique.contains(id) { unique.append(id) }
        self[index].after = unique
        return true
    }

    /// Highest priority first, then the nearest due date (no date last), then the order of the list,
    /// which is the order the user gave it by dragging.
    func inBoardOrder() -> [NookTask] {
        enumerated().sorted { a, b in
            if a.element.priority != b.element.priority { return a.element.priority > b.element.priority }
            let (x, y) = (a.element.deadline() ?? .distantFuture, b.element.deadline() ?? .distantFuture)
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    /// What could be sent to an agent now, best first.
    func ready(for agent: String) -> [NookTask] {
        filter { $0.agent == agent && $0.status == .queued && blocker(of: $0) == nil }.inBoardOrder()
    }

    /// The task an agent has now, if any.
    func out(for agent: String) -> NookTask? { first { $0.agent == agent && $0.status.isOut } }

    /// A queued task becomes cancelled; a finished one leaves the board. A task that is with its
    /// agent is left alone: the turn cannot be taken back. Returns false if nothing changed.
    @discardableResult
    mutating func cancelOrRemove(_ id: UUID, at now: Date) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }) else { return false }
        switch self[index].status {
        case .queued:
            self[index].status = .cancelled
            self[index].finished = now
            self[index].result = "Cancelled"
        case .sent, .running:
            return false
        case .done:
            // Its dependants keep going without its context; a failure is never stepped over this way.
            for other in indices { self[other].after.removeAll { $0 == id } }
            remove(at: index)
        case .failed, .cancelled:
            remove(at: index)
        }
        return true
    }

    /// Back to the queue after a failure or a cancel, which also unblocks whatever waited on it.
    mutating func requeue(_ id: UUID) {
        guard let index = firstIndex(where: { $0.id == id }), self[index].status.isFinished else { return }
        self[index].status = .queued
        (self[index].sent, self[index].finished, self[index].result, self[index].automatic) = (nil, nil, "", false)
    }

    /// The turn that carried a task ended.
    mutating func finish(_ id: UUID, summary: String, failed: Bool, at now: Date) {
        guard let index = firstIndex(where: { $0.id == id }), self[index].status.isOut else { return }
        self[index].status = failed ? .failed : .done
        self[index].finished = now
        self[index].result = summary
    }

    /// Rewrites the list so the given tasks appear in this order, in the places they already occupy.
    mutating func reorder(_ ids: [UUID]) {
        let places = indices.filter { ids.contains(self[$0].id) }
        let moved = ids.compactMap(task)
        guard places.count == moved.count else { return }
        for (place, task) in zip(places, moved) { self[place] = task }
    }

    /// Keeps each agent's newest `limit` finished tasks, and any older one that open work still waits on.
    mutating func trimFinished(limit: Int) {
        let needed = Set(filter { !$0.status.isFinished }.flatMap(\.after))
        var kept: [String?: Int] = [:]
        var drop = Set<UUID>()
        for task in filter({ $0.status.isFinished }).sorted(by: { ($0.finished ?? .distantPast) > ($1.finished ?? .distantPast) }) {
            kept[task.agent, default: 0] += 1
            if kept[task.agent, default: 0] > limit, !needed.contains(task.id) { drop.insert(task.id) }
        }
        if !drop.isEmpty { removeAll { drop.contains($0.id) } }
    }

    /// Open tasks that are overdue or due before `horizon`, soonest first.
    func dueSoon(now: Date, horizon: Date, calendar: Calendar = .current) -> [NookTask] {
        filter { task in
            guard !task.status.isFinished, let deadline = task.deadline(calendar) else { return false }
            return deadline <= horizon || task.isOverdue(at: now, calendar: calendar)
        }.sorted { ($0.deadline(calendar) ?? .distantFuture) < ($1.deadline(calendar) ?? .distantFuture) }
    }

    /// Whether an agent's notice board has something the user has not looked at since `seen`:
    /// a task that came back, or one that went overdue.
    func hasNews(for agent: String, since seen: Date, now: Date, calendar: Calendar = .current) -> Bool {
        contains { task in
            guard task.agent == agent else { return false }
            if let finished = task.finished, task.status != .cancelled, finished > seen { return true }
            if let deadline = task.deadline(calendar), task.isOverdue(at: now, calendar: calendar), deadline > seen { return true }
            return false
        }
    }
}

/// What the board shows of the list.
struct TaskFilter: Equatable {
    enum Show: Hashable {
        /// Queued or with an agent.
        case open
        case all
        case only(NookTask.Status)
    }

    var show = Show.open
    /// This priority or higher.
    var priority = NookTask.Priority.none
    var tag: String?

    func matches(_ task: NookTask) -> Bool {
        switch show {
        case .open: if task.status.isFinished { return false }
        case .all: break
        case .only(let status): if task.status != status { return false }
        }
        if task.priority < priority { return false }
        if let tag, !task.tags.contains(tag) { return false }
        return true
    }
}
