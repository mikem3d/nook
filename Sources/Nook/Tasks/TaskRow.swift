import SwiftUI

/// One task as a row, the same in the hub and on an agent's notice board.
struct TaskRow: View {
    let task: NookTask
    /// Why it cannot be sent yet, in words.
    var block: String?
    var now: Date
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Self.icon(task.status)).foregroundStyle(Self.tint(task.status)).frame(width: 16)
                if task.priority != .none {
                    Text(Self.mark(task.priority)).font(HotspotText.heading).foregroundStyle(Self.tint(task.priority)).help(task.priority.title + " priority")
                }
                Text(task.title).font(HotspotText.body).lineLimit(2)
                    .strikethrough(task.status == .cancelled)
                    .foregroundStyle(task.status.isFinished ? .secondary : .primary)
                Spacer(minLength: 0)
                if task.autoRun, !task.status.isFinished {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow).help("Runs automatically when unblocked")
                }
            }
            if let due = task.dueText(), !task.status.isFinished {
                let overdue = task.isOverdue(at: now)
                let today = task.isDueToday(at: now)
                Label((overdue ? "Overdue: " : today ? "Due today: " : "Due ") + due, systemImage: overdue ? "exclamationmark.circle.fill" : "clock")
                    .font(HotspotText.caption.weight(overdue || today ? .semibold : .regular))
                    .foregroundStyle(overdue ? Color.red : today ? Color.orange : Color.secondary)
            }
            if let block {
                Label(block, systemImage: "link").font(HotspotText.caption)
                    .foregroundStyle(block.hasPrefix("Blocked") ? Color.red : Color.secondary).lineLimit(2)
            }
            if !task.tags.isEmpty {
                Text(task.tags.map { "#" + $0 }.joined(separator: " ")).font(HotspotText.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            if task.status.isFinished, let finished = task.finished {
                Text((task.automatic ? "Auto · " : "") + finished.formatted(date: .abbreviated, time: .shortened)
                     + (task.result.isEmpty ? "" : " · " + task.result))
                    .font(HotspotText.caption).foregroundStyle(task.status == .failed ? Color.red : Color.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
    }

    static func mark(_ priority: NookTask.Priority) -> String {
        switch priority {
        case .none: return ""
        case .low: return "↓"
        case .medium: return "!"
        case .high: return "!!"
        case .urgent: return "!!!"
        }
    }

    static func tint(_ priority: NookTask.Priority) -> Color {
        switch priority {
        case .none, .low: return .secondary
        case .medium: return .yellow
        case .high: return .orange
        case .urgent: return .red
        }
    }

    static func icon(_ status: NookTask.Status) -> String {
        switch status {
        case .queued: return "circle"
        case .sent: return "paperplane.fill"
        case .running: return "arrow.right.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    static func tint(_ status: NookTask.Status) -> Color {
        switch status {
        case .queued, .cancelled: return .secondary
        case .sent, .running: return .yellow
        case .done: return .green
        case .failed: return .red
        }
    }
}

/// The agent's own plan, read-only, as the hub and the notice board both show it.
struct AgentPlanList: View {
    let todos: [AgentTodo]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
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
}
