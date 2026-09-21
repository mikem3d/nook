import Foundation

/// One entry of the agent's own plan, as Claude Code reports it through its task tools.
struct AgentTodo: Equatable {
    enum Status: String { case pending, inProgress = "in_progress", completed }

    /// Claude Code's task id; nil for entries that came from a `TodoWrite` list.
    var id: String?
    var content: String
    var status: Status
    /// The present-tense wording Claude Code shows while the entry is in progress.
    var activeForm: String
}

/// Follows the agent's plan through the tool calls of the main conversation. Two shapes exist:
/// - `TodoWrite`, input `{"todos": [{"content", "status", "activeForm"}]}`: the whole list each time.
/// - `TaskCreate` (input `{"subject", "description", "activeForm"?}`, result `{"task": {"id", "subject"}}`)
///   and `TaskUpdate` (input `{"taskId", "status"?, "subject"?, "activeForm"?}`, result `{"success", "taskId"}`),
///   status `pending | in_progress | completed | deleted`. Seen live from Claude Code 2.1.277, where
///   the result arrives as `tool_use_result` on the `user` event that carries the tool result.
struct AgentPlan {
    private(set) var todos: [AgentTodo] = []
    /// Task calls waiting for their result, by tool use id.
    private var calls: [String: (name: String, input: [String: Any])] = [:]

    /// Returns true if the plan changed.
    mutating func toolUse(id: String?, name: String, input: [String: Any]) -> Bool {
        switch name {
        case "TodoWrite":
            // No list at all: a malformed call, which must not wipe the plan.
            guard let items = input["todos"] as? [[String: Any]] else { return false }
            let list = items.compactMap { item -> AgentTodo? in
                guard let content = item["content"] as? String, !content.isEmpty else { return nil }
                return AgentTodo(id: nil, content: content, status: (item["status"] as? String).flatMap(AgentTodo.Status.init) ?? .pending,
                                 activeForm: item["activeForm"] as? String ?? content)
            }
            defer { todos = list }
            return list != todos
        case "TaskCreate", "TaskUpdate":
            if let id { calls[id] = (name, input) }
            return false
        default:
            return false
        }
    }

    /// `result` is the `tool_use_result` of the `user` event answering tool use `id`.
    mutating func toolResult(id: String, result: [String: Any]) -> Bool {
        guard let call = calls.removeValue(forKey: id) else { return false }
        let before = todos
        if call.name == "TaskCreate" {
            guard let task = result["task"] as? [String: Any], let taskID = task["id"] as? String,
                  let subject = task["subject"] as? String ?? call.input["subject"] as? String else { return false }
            todos.removeAll { $0.id == taskID }
            todos.append(AgentTodo(id: taskID, content: subject, status: .pending, activeForm: call.input["activeForm"] as? String ?? subject))
        } else {
            guard result["success"] as? Bool == true, let taskID = result["taskId"] as? String ?? call.input["taskId"] as? String,
                  let index = todos.firstIndex(where: { $0.id == taskID }) else { return false }
            if let status = call.input["status"] as? String {
                if status == "deleted" {
                    todos.remove(at: index)
                    return true
                }
                if let known = AgentTodo.Status(rawValue: status) { todos[index].status = known }
            }
            if let subject = call.input["subject"] as? String, !subject.isEmpty { todos[index].content = subject }
            if let active = call.input["activeForm"] as? String, !active.isEmpty { todos[index].activeForm = active }
        }
        return todos != before
    }
}
