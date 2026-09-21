import Foundation

/// The user's queue of work for one agent: what waits, what is with the agent now, what came back.
struct TaskQueue: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String
    }

    struct Done: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String
        var finished: Date
        /// `session.summary` of the turn that handled it.
        var summary: String
        var failed: Bool
        /// Sent by auto mode rather than by the user's click.
        var automatic: Bool
    }

    static let doneLimit = 50

    var queued: [Item] = []
    /// Sent, and its turn has not finished.
    var sending: Item?
    var sentAutomatically = false
    /// Newest first.
    var done: [Done] = []
    /// Something came back since the board was last opened: the wax seal.
    var unseen = false

    var open: Int { queued.count + (sending == nil ? 0 : 1) }

    mutating func add(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { queued.append(Item(text: line)) }
    }

    /// Takes the top task off the queue to be sent; nil while another is still out, or when there is none.
    mutating func takeNext(automatic: Bool) -> Item? {
        guard sending == nil, !queued.isEmpty else { return nil }
        let item = queued.removeFirst()
        sending = item
        sentAutomatically = automatic
        return item
    }

    /// The turn that carried the sent task ended.
    mutating func finish(summary: String, failed: Bool, at date: Date) {
        guard let item = sending else { return }
        sending = nil
        done.insert(Done(id: item.id, text: item.text, finished: date, summary: summary, failed: failed, automatic: sentAutomatically), at: 0)
        if done.count > Self.doneLimit { done.removeLast(done.count - Self.doneLimit) }
        unseen = true
    }
}

/// The rule for auto mode, as a pure function. Auto mode means the agent is given work with nobody
/// watching, so every doubt resolves to not sending.
enum AutoRun {
    enum Decision: Equatable {
        case send
        /// Not now; look again at the next change.
        case wait
        /// Switch auto mode off and say why.
        case stop(String)
    }

    static let limitKey = "nook.tasks.autoLimit"
    static let defaultLimit = 5

    static var limit: Int {
        let stored = UserDefaults.standard.integer(forKey: limitKey)
        return stored > 0 ? stored : defaultLimit
    }

    /// `free`: the agent is between turns. `outstanding`: something Nook sent is still with the agent.
    static func decide(auto: Bool, queued: Int, free: Bool, waitingForPermission: Bool, outstanding: Bool,
                       lastTurnFailed: Bool, sentThisRun: Int, limit: Int) -> Decision {
        guard auto, queued > 0 else { return .wait }
        guard free, !waitingForPermission, !outstanding else { return .wait }
        if lastTurnFailed { return .stop("the last turn did not end well") }
        if sentThisRun >= limit { return .stop("it reached its limit of \(limit) tasks in a row") }
        return .send
    }
}
