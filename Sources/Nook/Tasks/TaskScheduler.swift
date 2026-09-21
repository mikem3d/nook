import Foundation

/// Decides what Nook may send with nobody watching, as a pure function of the tasks, the agents
/// that are open and the settings. It sends nothing itself; `Hotspots` carries out the plan.
///
/// Automatic sends hand an agent work unattended, so every doubt resolves to not sending:
/// - an agent gets one task at a time, only while idle, never during a permission question;
/// - a task goes only if its agent's auto queue is on, or the user marked that very task to run
///   when unblocked (which only counts for a task that waits on others);
/// - nothing runs past a failed, cancelled or deleted prerequisite, or after the agent's own turn failed;
/// - the per-run limit counts every automatic send to an agent, chained ones included;
/// - priority only orders the queue. Urgent bypasses none of the above.
enum TaskScheduler {
    enum AgentState: Equatable {
        case idle
        /// Mid-turn, or something Nook sent has not come back yet.
        case busy
        case pendingPermission
        /// Idle, but its last turn ended badly.
        case lastTurnFailed
    }

    /// An agent whose window is open. A task assigned to anyone else is never sent.
    struct Agent: Equatable {
        var key: String
        var state: AgentState
        /// Runtime only, off at every launch.
        var auto = false
        var sentThisRun = 0
    }

    enum Source: Equatable {
        /// The agent's auto queue is on.
        case autoQueue
        /// The task was marked to run when unblocked, and what it waited on has finished.
        case chain
    }

    struct Send: Equatable {
        var task: UUID
        var agent: String
        var source: Source
    }

    /// Something ready was held back, and the user should be told why.
    struct Hold: Equatable {
        var task: UUID
        var agent: String
        var source: Source
        var why: String
    }

    struct Plan: Equatable {
        var sends: [Send] = []
        var holds: [Hold] = []
    }

    static let limitKey = "nook.tasks.autoLimit"
    static let defaultLimit = 5

    static var limit: Int {
        let stored = UserDefaults.standard.integer(forKey: limitKey)
        return stored > 0 ? stored : defaultLimit
    }

    static func plan(tasks: [NookTask], agents: [Agent], limit: Int) -> Plan {
        var plan = Plan()
        var planned = Set<String>()
        for agent in agents where planned.insert(agent.key).inserted { // two windows on one folder are one agent
            guard tasks.out(for: agent.key) == nil else { continue }
            let next = tasks.ready(for: agent.key).first { agent.auto || ($0.autoRun && !$0.after.isEmpty) }
            guard let next else { continue }
            let source: Source = agent.auto ? .autoQueue : .chain
            switch agent.state {
            case .busy, .pendingPermission:
                continue
            case .lastTurnFailed:
                plan.holds.append(Hold(task: next.id, agent: agent.key, source: source, why: "the last turn did not end well"))
            case .idle:
                if agent.sentThisRun >= limit {
                    plan.holds.append(Hold(task: next.id, agent: agent.key, source: source, why: "it reached its limit of \(limit) automatic tasks in a row"))
                } else {
                    plan.sends.append(Send(task: next.id, agent: agent.key, source: source))
                }
            }
        }
        return plan
    }

    /// Why the user cannot send this task now, or nil if they can.
    static func refusal(_ task: NookTask, in tasks: [NookTask], agent: Agent?) -> String? {
        guard task.status == .queued else { return "It is not waiting to be sent" }
        guard let key = task.agent else { return "Assign it to an agent first" }
        if let block = tasks.blocker(of: task) { return tasks.blockText(block) }
        guard let agent, agent.key == key else { return "\(NookTask.label(forAgent: key)) is not open" }
        if tasks.out(for: key) != nil { return "Another task is still with the agent" }
        switch agent.state {
        case .busy: return "The agent is busy"
        case .pendingPermission: return "The agent is waiting for a permission answer"
        case .idle, .lastTurnFailed: return nil // the user's own click may follow a failed turn
        }
    }
}

/// The words that go to the agent and into its transcript.
enum TaskPrompt {
    /// The task, then what its prerequisites reported and where they ran.
    static func compose(_ task: NookTask, in tasks: [NookTask]) -> String {
        var text = task.title
        if !task.notes.isEmpty { text += "\n\n" + task.notes }
        let finished = task.after.compactMap(tasks.task).filter { $0.status == .done }
        guard !finished.isEmpty else { return text }
        text += "\n\nContext: this task waited on the following, which finished successfully."
        for other in finished {
            text += "\n- “\(other.title)”"
            if let key = other.agent, !key.hasPrefix("demo:") { text += " (ran in \(key))" }
            text += ": " + (other.result.isEmpty ? "no summary was reported" : other.result)
        }
        return text
    }

    /// The system line written before a send. An automatic one names its source and what it waited on.
    /// Every one starts "Queued task", and an automatic one says "automatically": the notifications
    /// feature tells unattended sends from the user's own by those words.
    static func note(_ task: NookTask, in tasks: [NookTask], source: TaskScheduler.Source?, labels: (String) -> String) -> String {
        guard let source else { return "Queued task: " + task.title }
        let waited = task.after.compactMap(tasks.task).map { "“\($0.title)”" + ($0.agent.map { " (\(labels($0)))" } ?? "") }
        let chain = waited.isEmpty ? "" : ", after \(waited.joined(separator: ", ")) finished"
        switch source {
        case .autoQueue: return "Queued task (sent automatically by the auto queue\(chain)): " + task.title
        case .chain: return "Queued task (chained, sent automatically: marked to run when unblocked\(chain)): " + task.title
        }
    }
}
