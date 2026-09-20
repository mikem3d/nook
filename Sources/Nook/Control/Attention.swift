import Foundation

/// The pure decisions behind the one-key hotkeys, kept free of AppKit so they can be unit tested.
enum Attention {
    /// One agent, as the hotkeys see it. Array order is window (stack) order and breaks ties.
    struct Candidate {
        var pendingSince: Date?
        var unread = 0
        var finishedAt: Date?
    }

    /// Index of the agent whose permission request has waited longest.
    static func oldestPending(_ agents: [Candidate]) -> Int? {
        var best: (index: Int, since: Date)?
        for (index, agent) in agents.enumerated() {
            guard let since = agent.pendingSince else { continue }
            if best == nil || since < best!.since { best = (index, since) }
        }
        return best?.index
    }

    /// Who most needs the user: a waiting permission request (oldest first), then the most
    /// unread messages, then whoever finished most recently. nil when nobody needs anything.
    static func mostNeedy(_ agents: [Candidate]) -> Int? {
        if let waiting = oldestPending(agents) { return waiting }
        var unread: (index: Int, count: Int)?
        for (index, agent) in agents.enumerated() where agent.unread > 0 {
            if unread == nil || agent.unread > unread!.count { unread = (index, agent.unread) }
        }
        if let unread { return unread.index }
        var finished: (index: Int, at: Date)?
        for (index, agent) in agents.enumerated() {
            guard let at = agent.finishedAt else { continue }
            if finished == nil || at > finished!.at { finished = (index, at) }
        }
        return finished?.index
    }

    /// The next agent after `active`, wrapping; the first one when none is active.
    static func next(after active: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let active else { return 0 }
        return (active + 1) % count
    }

    /// Key-repeat guard: a hotkey answer only counts once the confirmation of the previous one
    /// has been on screen for `minimum` seconds, so a queue can never be approved unseen.
    static func acceptsAnswer(now: Date, lastConfirmationShown: Date?, minimum: TimeInterval) -> Bool {
        guard let last = lastConfirmationShown else { return true }
        return now.timeIntervalSince(last) >= minimum
    }
}
