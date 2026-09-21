import Foundation

/// Something that may deserve a system notification. Built by Features/Notifications.swift from
/// session changes; everything that decides what happens to it is pure (NotifyPolicy).
struct NotifyEvent: Equatable {
    enum Kind: String, CaseIterable {
        case permission, finished, failed, ended, autoRun, taskDue
    }

    var kind: Kind
    /// Stable for one agent for this run: the notification's thread, and half of its identifier.
    var agentID: String
    var agentLabel: String
    /// The summary, the exact command or path, the transcript note, or the task's title.
    var text = ""
    /// How long the turn took, when known. A turn that ends at once is not worth a notification.
    var turnSeconds: TimeInterval?

    // Permission requests only.
    var tool = ""
    var requestID: String?
    /// Why this request cannot be allowed from the notification (see `Risk`, `NotifyText`).
    var reviewReason: String?

    // Due tasks only.
    var taskID: String?
    var overdue = false
}

/// The few session fields that say whether something notify-worthy just happened. Comparing two
/// of these is all the work done for the many session changes (streaming text) that do not matter.
struct AgentSnapshot: Equatable {
    var pendingID: String?
    var turnsCompleted = 0
    var state = AgentState.idle
    var failed = false
    var interrupted = false
    var entries = 0
    var turnStarted: Date?
}

enum AgentTransition: Equatable {
    case asked
    /// The request went away: answered here, by hotkey, or withdrawn by the CLI.
    case answered
    case turnEnded(failed: Bool, seconds: TimeInterval?)
    case processEnded(midTurn: Bool)
    case autoRun(String)

    /// `notes` are the system lines added to the transcript between the two snapshots.
    static func between(_ old: AgentSnapshot, _ new: AgentSnapshot, notes: [String], now: Date) -> [AgentTransition] {
        var found: [AgentTransition] = []
        if new.pendingID != old.pendingID {
            if old.pendingID != nil { found.append(.answered) }
            if new.pendingID != nil { found.append(.asked) }
        }
        for note in notes {
            if note.hasPrefix("Session ended (exit") {
                found.append(.processEnded(midTurn: old.state.busy))
            } else if isAutomaticRun(note) {
                found.append(.autoRun(note))
            }
        }
        // Real agents count their turns; the scripted demo agents only change state.
        let ended = new.turnsCompleted > old.turnsCompleted || (new.state == .done && old.state != .done)
        if ended, !new.interrupted { // the user interrupted it themselves; that is not news
            found.append(.turnEnded(failed: new.failed, seconds: old.turnStarted.map { now.timeIntervalSince($0) }))
        }
        return found
    }

    /// The task board and calendar name every send the user did not type ("Scheduled (daily 09:00): …",
    /// "Queued task (sent automatically): …"). A queued task the user sent by hand is not automatic.
    static func isAutomaticRun(_ note: String) -> Bool {
        note.hasPrefix("Scheduled") || (note.hasPrefix("Queued task") && note.contains("automatically"))
    }
}
