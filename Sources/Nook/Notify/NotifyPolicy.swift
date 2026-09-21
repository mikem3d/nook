import Foundation

/// Preference keys for notifications. The settings window writes them; `NotifySettings` reads them.
enum NotifyPrefs {
    static let enabled = "nook.notify.enabled"
    static let sound = "nook.notify.sound"
    static let audibleApprovals = "nook.notify.audibleApprovalsInQuiet"
    static let answerFromNotification = "nook.notify.answerFromNotification"
    /// Set once Nook has asked for the system permission by itself; after that only the settings window asks.
    static let asked = "nook.notify.asked"

    static func key(_ kind: NotifyEvent.Kind) -> String { "nook.notify.kind.\(kind.rawValue)" }

    static var defaults: [String: Any] {
        var values: [String: Any] = [enabled: true, sound: true, audibleApprovals: true, answerFromNotification: true]
        for kind in NotifyEvent.Kind.allCases { values[key(kind)] = true }
        return values
    }
}

struct NotifySettings: Equatable {
    var enabled = true
    var kinds = Set(NotifyEvent.Kind.allCases)
    var sound = true
    var audibleApprovalsInQuiet = true
    var answerFromNotification = true

    init() {}

    init(_ defaults: UserDefaults) {
        enabled = defaults.bool(forKey: NotifyPrefs.enabled)
        kinds = Set(NotifyEvent.Kind.allCases.filter { defaults.bool(forKey: NotifyPrefs.key($0)) })
        sound = defaults.bool(forKey: NotifyPrefs.sound)
        audibleApprovalsInQuiet = defaults.bool(forKey: NotifyPrefs.audibleApprovals)
        answerFromNotification = defaults.bool(forKey: NotifyPrefs.answerFromNotification)
    }
}

/// A notification ready to hand to the system, in plain values so it can be tested.
struct NotifyPlan: Equatable {
    /// Which buttons it carries. `approve`: Allow and Deny. `review`: Deny and Open, for requests
    /// that must be read in Nook first. `finished`: Reply and Open. `open`: Open only.
    enum Category: String, CaseIterable { case approve, review, finished, open }

    var identifier: String
    var thread: String
    var category: Category
    var title: String
    var subtitle = ""
    var body: String
    var sound: Bool
    /// Passive: straight to Notification Centre, no banner, no sound.
    var passive: Bool
    var agentID: String
    var requestID: String?
}

enum NotifyPolicy {
    /// A turn that ends this soon after it was sent found the user still there.
    static let shortTurn: TimeInterval = 3

    /// One identifier per agent and kind, so a newer notification replaces the older one.
    static func identifier(_ agentID: String, _ kind: NotifyEvent.Kind) -> String { "\(agentID).\(kind.rawValue)" }
    static func identifiers(forAgent agentID: String) -> [String] { NotifyEvent.Kind.allCases.map { identifier(agentID, $0) } }

    /// `watching`: the agent is the active one and its window can be seen.
    static func wants(_ event: NotifyEvent, watching: Bool, settings: NotifySettings) -> Bool {
        guard settings.enabled, settings.kinds.contains(event.kind), !watching else { return false }
        if event.kind == .finished, let seconds = event.turnSeconds, seconds < shortTurn { return false }
        return true
    }

    /// Finished and failed turns wait out the coalescing window; everything else goes at once.
    static func coalesces(_ kind: NotifyEvent.Kind) -> Bool { kind == .finished || kind == .failed }

    /// One event becomes its own notification; several (a burst of finished turns) become one.
    static func plan(for events: [NotifyEvent], quiet: Bool, settings: NotifySettings) -> NotifyPlan? {
        guard let first = events.first else { return nil }
        guard events.count > 1 else { return plan(for: first, quiet: quiet, settings: settings) }
        let failed = events.filter { $0.kind == .failed }
        let title = failed.isEmpty ? "\(events.count) agents finished"
            : failed.count == events.count ? "\(events.count) agents hit a problem"
            : "\(events.count - failed.count) finished, \(failed.count) hit a problem"
        let lines = events.map { "\($0.agentLabel): \($0.text.isEmpty ? ($0.kind == .failed ? "failed" : "done") : $0.text)" }
        return NotifyPlan(identifier: "nook.burst", thread: "nook.burst", category: .open, title: title,
                          body: lines.joined(separator: "\n"), sound: settings.sound && !quiet, passive: quiet,
                          agentID: (failed.first ?? first).agentID) // clicking opens the one that needs you most
    }

    private static func plan(for event: NotifyEvent, quiet: Bool, settings: NotifySettings) -> NotifyPlan {
        // Quiet mode files everything silently, except approvals if the user wants to keep hearing those.
        let hushed = quiet && !(event.kind == .permission && settings.audibleApprovalsInQuiet)
        var plan = NotifyPlan(identifier: identifier(event.agentID, event.kind), thread: event.agentID, category: .open,
                              title: "", body: event.text, sound: settings.sound && !hushed, passive: hushed,
                              agentID: event.agentID, requestID: event.requestID)
        switch event.kind {
        case .permission:
            plan.title = "\(event.agentLabel) needs approval"
            plan.subtitle = event.tool
            if let reason = event.reviewReason { plan.body += "\n" + NotifyText.reviewLine(reason) }
            plan.category = !settings.answerFromNotification ? .open : event.reviewReason == nil ? .approve : .review
        case .finished:
            plan.title = "\(event.agentLabel) finished"
            if plan.body.isEmpty { plan.body = "The turn is done." }
            plan.category = .finished
        case .failed:
            plan.title = "\(event.agentLabel) hit a problem"
            if plan.body.isEmpty { plan.body = "The turn ended with an error." }
        case .ended:
            plan.title = "\(event.agentLabel) stopped"
        case .autoRun:
            plan.title = "\(event.agentLabel) started by itself"
        case .taskDue:
            plan.title = event.overdue ? "Task overdue" : "Task due"
            plan.subtitle = event.agentLabel
            plan.thread = "nook.tasks"
            if let task = event.taskID { plan.identifier = "task.\(task)" } // one per task, not per agent
        }
        return plan
    }
}

/// Holds finished turns for a moment so that several agents finishing together make one notification.
struct NotifyCoalescer {
    static let window: TimeInterval = 2
    private(set) var held: [NotifyEvent] = []

    /// True when this event opens a new window, which the caller then closes with `drain` after `window` seconds.
    mutating func hold(_ event: NotifyEvent) -> Bool {
        let opens = held.isEmpty
        held.removeAll { $0.agentID == event.agentID }
        held.append(event)
        return opens
    }

    mutating func drain() -> [NotifyEvent] {
        defer { held = [] }
        return held
    }
}
