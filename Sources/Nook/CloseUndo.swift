import Foundation

/// Closing an agent: when to ask first, and how long a closed agent can still come back.
///
/// A close takes effect at once (the process stops, the window goes), but what was closed is held
/// here for `window` seconds. While it is held it still counts as saved, so a crash or a quit
/// inside those seconds brings the agent back rather than losing it. Only one close is held at a
/// time: a new close makes the one before it final.
struct CloseUndo {
    typealias Agent = Persistence.SavedAgent

    static let window: TimeInterval = 6

    /// Interrupting work or leaving a permission unanswered deserves a question; an idle agent does not.
    static func needsConfirmation(state: AgentState, hasPending: Bool, turnInProgress: Bool) -> Bool {
        state.busy || hasPending || turnInProgress
    }

    private(set) var held: [Agent] = []
    private var deadline = Date.distantPast

    mutating func closed(_ agents: [Agent], at now: Date) {
        held = agents
        deadline = now.addingTimeInterval(Self.window)
    }

    /// The agents to reopen, in stack order. Empty once the time is up.
    mutating func undo(at now: Date) -> [Agent] {
        defer { held = [] }
        return now <= deadline ? held.sorted { $0.order < $1.order } : []
    }

    /// The owner's one-shot timer ran out. True if something held became final, which is when it
    /// must leave the saved state.
    mutating func expire() -> Bool {
        defer { held = [] }
        return !held.isEmpty
    }
}
