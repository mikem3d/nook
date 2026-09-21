import Foundation

extension Notification.Name {
    /// A task was added, edited, moved on, removed, or went overdue. Object: the TaskStore.
    /// userInfo: see `TaskStore.info`, plus a true "removed" or "overdue" when that is what happened.
    static let nookTaskChanged = Notification.Name("nookTaskChanged")
    /// A task's turn ended. Object: the TaskStore; userInfo as above, the task's status `.done` or `.failed`.
    static let nookTaskFinished = Notification.Name("nookTaskFinished")
}

/// Every task, in Application Support/Nook/tasks.json: read once, written atomically, and only
/// when something changed. The one source of truth for the hub and the notice boards.
///
/// The file carries a schema version. A version 1 file (one queue per agent) is copied to
/// `tasks.v1.backup.json` and carried forward; a file this build cannot read is copied aside
/// before anything is written over it, so no launch can lose tasks.
final class TaskStore {
    static let version = 2
    static let finishedLimit = 50
    /// Posted once per edit, after the per-task notifications, for views that reload the lot.
    static let changed = Notification.Name("nookTaskStoreChanged")

    struct File: Codable, Equatable {
        var version = TaskStore.version
        var tasks: [NookTask] = []
        /// When each agent's notice board was last opened, by agent key.
        var seen: [String: Date] = [:]
    }

    private let file: URL
    private var contents: File
    /// How an agent key reads in a notification; the hub supplies the open windows' labels.
    var labels: (String) -> String = NookTask.label(forAgent:)

    var tasks: [NookTask] { contents.tasks }

    init(folder: URL? = nil, now: Date = Date()) {
        let folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nook")
        file = folder.appendingPathComponent("tasks.json")
        guard let data = try? Data(contentsOf: file) else {
            contents = File()
            return
        }
        if let current = Self.decode(data) {
            contents = current
        } else if let old = try? JSONDecoder().decode(LegacyFile.self, from: data), old.version == 1 {
            Self.backUp(file, as: "tasks.v1.backup.json")
            contents = Self.migrate(agents: old.agents, now: now)
            save()
        } else {
            Self.backUp(file, as: "tasks.unreadable-\(Int(now.timeIntervalSince1970)).json")
            contents = File()
        }
    }

    /// Only this build's version: a newer file may mean things this build would drop on saving.
    private static func decode(_ data: Data) -> File? {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == version else { return nil }
        return file
    }

    /// Never replaces an earlier backup: the first copy is the one made before anything was changed.
    private static func backUp(_ file: URL, as name: String) {
        let copy = file.deletingLastPathComponent().appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: file, to: copy) }
    }

    // MARK: version 1

    private struct LegacyFile: Decodable {
        var version: Int
        var agents: [String: TaskQueue]
    }

    /// One queue per agent becomes one list, in the same order, with nothing dropped. Version 1 kept
    /// no creation times, so tasks are stamped a second apart to keep their order under any sort.
    static func migrate(agents: [String: TaskQueue], now: Date) -> File {
        var result = File()
        for key in agents.keys.sorted() {
            guard let queue = agents[key] else { continue }
            let count = queue.queued.count + queue.done.count + 1
            func stamp(_ n: Int) -> Date { now.addingTimeInterval(TimeInterval(n - count)) }
            for (n, item) in queue.done.reversed().enumerated() {
                result.tasks.append(NookTask(id: item.id, title: item.text, agent: key, status: item.failed ? .failed : .done, created: stamp(n),
                                             sent: nil, finished: item.finished, result: item.summary, automatic: item.automatic))
            }
            if let item = queue.sending {
                result.tasks.append(NookTask(id: item.id, title: item.text, agent: key, status: .sent, created: stamp(queue.done.count),
                                             sent: now, automatic: queue.sentAutomatically))
            }
            for (n, item) in queue.queued.enumerated() {
                result.tasks.append(NookTask(id: item.id, title: item.text, agent: key, created: stamp(queue.done.count + 1 + n)))
            }
            result.seen[key] = queue.unseen ? .distantPast : now
        }
        return result
    }

    // MARK: notifications

    /// What every task notification carries: the whole task under "task", and its plain fields for
    /// listeners that do not know the type: "id" (UUID string), "title", "done" (finished, cancelled
    /// or removed), "agent" (its label, when assigned) and "due" (the moment it becomes overdue: the
    /// time given, or the end of the day when only a day was).
    func info(_ task: NookTask, removed: Bool = false, overdue: Bool = false) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = ["task": task, "id": task.id.uuidString, "title": task.title, "done": removed || task.status.isFinished]
        if let agent = task.agent { info["agent"] = labels(agent) }
        if let deadline = task.deadline() { info["due"] = deadline }
        if removed { info["removed"] = true }
        if overdue { info["overdue"] = true }
        return info
    }

    // MARK: edits

    /// Changes the list, saves if that changed anything, and says what changed. Returns true if it did.
    @discardableResult
    func edit(_ change: (inout [NookTask]) -> Void) -> Bool {
        let before = contents.tasks
        var tasks = before
        change(&tasks)
        tasks.trimFinished(limit: Self.finishedLimit)
        guard tasks != before else { return false }
        contents.tasks = tasks
        save()

        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let centre = NotificationCenter.default
        for task in tasks where old[task.id] != task {
            centre.post(name: .nookTaskChanged, object: self, userInfo: info(task))
            if task.status == .done || task.status == .failed, old[task.id]?.status.isOut == true {
                centre.post(name: .nookTaskFinished, object: self, userInfo: info(task))
            }
        }
        for task in before where new[task.id] == nil {
            centre.post(name: .nookTaskChanged, object: self, userInfo: info(task, removed: true))
        }
        centre.post(name: Self.changed, object: self)
        return true
    }

    func seen(_ agent: String) -> Date { contents.seen[agent] ?? .distantPast }

    /// The agent's notice board was looked at.
    func markSeen(_ agent: String, at now: Date) {
        contents.seen[agent] = now
        save()
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Dates keep JSONEncoder's default form, as in HotspotStore: it round-trips exactly.
        guard let data = try? encoder.encode(contents) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
