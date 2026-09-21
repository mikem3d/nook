import Foundation

/// Tasks with a due time, as the notifications feature knows them. The task board announces its
/// changes with `nookTaskChanged` / `nookTaskFinished`; this file was written before that code
/// existed, so it reads userInfo defensively and ignores anything it does not understand.
struct DueTasks {
    struct Item: Equatable {
        var id: String
        var title: String
        var agent: String?
        var due: Date
    }

    /// Later than this after its time, a task is announced as overdue rather than due.
    static let grace: TimeInterval = 60

    private(set) var items: [String: Item] = [:]
    private var announced: Set<String> = []

    /// A finished task, or one that lost its due time, is forgotten. A moved due time is announced again.
    mutating func track(id: String, title: String, agent: String?, due: Date?, done: Bool) {
        guard let due, !done else { return forget(id) }
        if items[id]?.due != due { announced.remove(id) }
        items[id] = Item(id: id, title: title, agent: agent, due: due)
    }

    mutating func forget(_ id: String) {
        items[id] = nil
        announced.remove(id)
    }

    /// When the next unannounced task falls due; the caller sets one timer for it.
    var nextDue: Date? { items.values.filter { !announced.contains($0.id) }.map(\.due).min() }

    /// Everything that has fallen due and was not announced yet, oldest first. Each comes out once.
    mutating func takeDue(now: Date) -> [(item: Item, overdue: Bool)] {
        let due = items.values.filter { $0.due <= now && !announced.contains($0.id) }.sorted { $0.due < $1.due }
        announced.formUnion(due.map(\.id))
        return due.map { ($0, now.timeIntervalSince($0.due) > Self.grace) }
    }

    /// The fields of a task notification's userInfo, under the names the task board is likely to use.
    static func parse(_ info: [AnyHashable: Any]?) -> (id: String, title: String, agent: String?, due: Date?, done: Bool)? {
        guard let info else { return nil }
        func first<T>(_ keys: [String], _ convert: (Any) -> T?) -> T? {
            for key in keys { if let value = info[key].flatMap(convert) { return value } }
            return nil
        }
        let id = first(["id", "taskID", "task"]) { ($0 as? String) ?? ($0 as? UUID)?.uuidString }
        let title = first(["title", "text", "name"]) { $0 as? String }
        guard let id, let title else { return nil }
        let due = first(["due", "dueDate"]) { ($0 as? Date) ?? ($0 as? TimeInterval).map(Date.init(timeIntervalSince1970:)) }
        return (id, title, first(["agent", "label"]) { $0 as? String }, due,
                first(["done", "finished", "completed"]) { $0 as? Bool } ?? false)
    }
}
