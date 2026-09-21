import AppKit

/// System notifications when an agent needs you or finishes while you are not looking, plus a
/// line at the top of the menu bar menu that says who is waiting.
///
/// This file only watches sessions and carries out decisions. What to notify, the wording, the
/// coalescing and the risk check are pure and live in Notify/; NotifyCenter is the only code that
/// talks to the system. Everything is driven by the app's notifications: a session change costs
/// one small struct comparison, and the only timers are the 2 s coalescing window and one shot
/// for the next due task.
final class Notifications: NSObject, Feature {
    private weak var app: AppController?
    private var snapshots: [ObjectIdentifier: AgentSnapshot] = [:]
    private var askedAt: [ObjectIdentifier: Date] = [:]
    /// Kept so a closed agent's notifications can be withdrawn after its window is gone.
    private var agentIDs: [ObjectIdentifier: String] = [:]
    /// Agents whose turn ended while nobody was watching, until they are next activated.
    private var unseen: Set<ObjectIdentifier> = []
    private var coalescer = NotifyCoalescer()
    private var tasks = DueTasks()
    private var taskTimer: DispatchWorkItem?
    private var asking = false
    private let indicator = NSMenuItem(title: "", action: #selector(jumpToNeediest), keyEquivalent: "")
    private let indicatorRule = NSMenuItem.separator()

    func install(in app: AppController) {
        self.app = app
        UserDefaults.standard.register(defaults: NotifyPrefs.defaults)
        app.windows.forEach { snapshots[ObjectIdentifier($0)] = Self.snapshot($0.session) } // restored agents are not news

        let centre = NotificationCenter.default
        centre.addObserver(forName: .nookSessionChanged, object: nil, queue: .main) { [weak self] note in
            if let window = note.object as? AgentWindow { self?.changed(window) }
        }
        centre.addObserver(forName: .nookAgentsChanged, object: nil, queue: .main) { [weak self] _ in self?.agentsChanged() }
        centre.addObserver(forName: .nookActiveChanged, object: nil, queue: .main) { [weak self] _ in self?.activeChanged() }
        // The task board's notifications, by name: that code is written in parallel (see DueTasks).
        centre.addObserver(forName: Notification.Name("nookTaskChanged"), object: nil, queue: .main) { [weak self] note in
            guard let self, let task = DueTasks.parse(note.userInfo) else { return }
            let agent = (note.userInfo?["window"] as? AgentWindow)?.session.label ?? task.agent
            self.track(task: task.id, title: task.title, agent: agent, due: task.due, done: task.done)
        }
        centre.addObserver(forName: Notification.Name("nookTaskFinished"), object: nil, queue: .main) { [weak self] note in
            guard let self, let task = DueTasks.parse(note.userInfo) else { return }
            self.track(task: task.id, title: task.title, agent: task.agent, due: nil, done: true)
        }

        NotifyCenter.shared.onAction = { [weak self] action, agent, request in self?.act(action, agent: agent, request: request) }
        NotifyCenter.shared.start()

        // addMenuItem puts commands above Quit; this line belongs at the very top.
        indicator.target = self
        app.addMenuItem(indicator)
        if let menu = indicator.menu {
            menu.removeItem(indicator)
            menu.insertItem(indicator, at: 0)
            menu.insertItem(indicatorRule, at: 1)
        }
        refreshIndicator()
    }

    /// For a task board that announces changes without userInfo: feed it `TaskHub.shared.dueSoon` here.
    func track(task id: String, title: String, agent: String?, due: Date?, done: Bool) {
        tasks.track(id: id, title: title, agent: agent, due: due, done: done)
        if due == nil || done { NotifyCenter.shared.remove(["task.\(id)"]) }
        armTasks()
    }

    // MARK: sessions

    private func changed(_ window: AgentWindow) {
        let key = ObjectIdentifier(window)
        let session = window.session
        let new = Self.snapshot(session)
        let old = snapshots[key] ?? AgentSnapshot()
        guard new != old else { return }
        snapshots[key] = new
        agentIDs[key] = session.id.uuidString

        let notes = session.transcript.count > old.entries
            ? session.transcript[old.entries...].filter { $0.kind == .system }.map(\.text) : []
        for transition in AgentTransition.between(old, new, notes: notes, now: Date()) {
            switch transition {
            case .asked:
                askedAt[key] = Date()
                if let request = session.pending { consider(Self.event(for: request, in: session), from: window) }
            case .answered:
                askedAt[key] = nil
                NotifyCenter.shared.remove([NotifyPolicy.identifier(session.id.uuidString, .permission)])
            case .turnEnded(let failed, let seconds):
                if !isWatching(window) { unseen.insert(key) }
                consider(NotifyEvent(kind: failed ? .failed : .finished, agentID: session.id.uuidString, agentLabel: session.label,
                                     text: session.summary, turnSeconds: seconds), from: window)
            case .processEnded(let midTurn):
                let text = midTurn ? "It stopped in the middle of a turn. Send a message to pick it back up."
                                   : "Its claude process exited. Send a message to start it again."
                consider(NotifyEvent(kind: .ended, agentID: session.id.uuidString, agentLabel: session.label, text: text), from: window)
            case .autoRun(let note):
                consider(NotifyEvent(kind: .autoRun, agentID: session.id.uuidString, agentLabel: session.label,
                                     text: NotifyText.middleTruncated(note, limit: NotifyText.bodyLimit)), from: window)
            }
        }
        refreshIndicator()
    }

    private func agentsChanged() {
        guard let app else { return }
        let live = Set(app.windows.map { ObjectIdentifier($0) })
        for (key, id) in agentIDs where !live.contains(key) {
            NotifyCenter.shared.remove(NotifyPolicy.identifiers(forAgent: id))
            agentIDs[key] = nil
        }
        snapshots = snapshots.filter { live.contains($0.key) }
        askedAt = askedAt.filter { live.contains($0.key) }
        unseen = unseen.filter { live.contains($0) }
        refreshIndicator()
    }

    /// Opening an agent is seeing what it had to say: its finished and failed notifications go.
    private func activeChanged() {
        guard let active = app?.active else { return }
        unseen.remove(ObjectIdentifier(active))
        let id = active.session.id.uuidString
        NotifyCenter.shared.remove([.finished, .failed, .ended, .autoRun].map { NotifyPolicy.identifier(id, $0) })
        refreshIndicator()
    }

    private static func snapshot(_ session: AgentSession) -> AgentSnapshot {
        AgentSnapshot(pendingID: session.pending?.requestID, turnsCompleted: session.turnsCompleted, state: session.state,
                      failed: session.lastTurnFailed, interrupted: session.lastTurnFailed && session.summary == "Interrupted",
                      entries: session.transcript.count, turnStarted: session.turnStarted)
    }

    private static func event(for request: PermissionRequest, in session: AgentSession) -> NotifyEvent {
        let body = NotifyText.permissionBody(input: request.input, fallback: request.summary)
        let reason = Risk.reason(input: request.input, projectFolder: session.cwd?.path)
            ?? (body.complete ? nil : "too long to show in full")
        return NotifyEvent(kind: .permission, agentID: session.id.uuidString, agentLabel: session.label, text: body.text,
                           tool: request.tool, requestID: request.requestID, reviewReason: reason)
    }

    private func isWatching(_ window: AgentWindow?) -> Bool {
        guard let window, app?.active === window else { return false }
        return window.occlusionState.contains(.visible)
    }

    private func window(agentID: String) -> AgentWindow? {
        app?.windows.first { $0.session.id.uuidString == agentID }
    }

    // MARK: deciding and delivering

    private func consider(_ event: NotifyEvent, from window: AgentWindow?) {
        let settings = NotifySettings(.standard)
        guard NotifyPolicy.wants(event, watching: isWatching(window), settings: settings) else { return }
        guard NotifyPolicy.coalesces(event.kind) else { return deliver([event], settings: settings) }
        guard coalescer.hold(event) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + NotifyCoalescer.window) { [weak self] in self?.flush() }
    }

    /// The window has closed. Anyone the user opened in the meantime has been seen already.
    private func flush() {
        let settings = NotifySettings(.standard)
        let events = coalescer.drain().filter { event in
            guard let window = window(agentID: event.agentID) else { return false }
            return NotifyPolicy.wants(event, watching: isWatching(window), settings: settings)
        }
        deliver(events, settings: settings)
    }

    private func deliver(_ events: [NotifyEvent], settings: NotifySettings) {
        guard NotifyCenter.isAvailable,
              let plan = NotifyPolicy.plan(for: events, quiet: app?.isQuiet ?? false, settings: settings) else { return }
        switch NotifyCenter.shared.status {
        case .allowed: post(plan)
        case .undetermined: ask(then: plan)
        case .denied: NotifyCenter.shared.refresh() // the user may have switched it on in System Settings since
        case .unavailable: break
        }
    }

    /// A request answered in the meantime (the permission prompt took a while) is no longer worth showing.
    private func post(_ plan: NotifyPlan) {
        if let request = plan.requestID, window(agentID: plan.agentID)?.session.pending?.requestID != request { return }
        NotifyCenter.shared.post(plan)
    }

    /// Nook asks for the system permission by itself once ever: the first time there is something to
    /// say, with a line of explanation first, and never during quiet mode (a meeting, a shared
    /// screen). After that the Notifications settings pane is the only place that asks.
    private func ask(then plan: NotifyPlan) {
        let defaults = UserDefaults.standard
        guard !asking, !defaults.bool(forKey: NotifyPrefs.asked), app?.isQuiet != true else { return }
        asking = true
        defaults.set(true, forKey: NotifyPrefs.asked)
        HUD.shared.show("Nook can notify you when an agent needs you", detail: "macOS is about to ask. You can change this in Settings.", duration: 4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NotifyCenter.shared.requestAuthorisation { [weak self] granted in
                self?.asking = false
                if granted { self?.post(plan) }
            }
        }
    }

    // MARK: answers from a notification

    private func act(_ action: NotifyCenter.Action, agent: String, request: String?) {
        guard let app, let window = window(agentID: agent) else { return }
        let session = window.session
        switch action {
        case .open:
            window.orderFrontRegardless() // it may have been hidden by the hotkey
            app.activate(window)
        case .allow, .deny:
            // Only ever answer the request the notification showed, never whatever is pending now.
            guard let pending = session.pending, pending.requestID == request else {
                HUD.shared.show("That request was already answered", near: window)
                return
            }
            let allow = action == .allow
            guard !allow || NotifySettings(.standard).answerFromNotification else { return }
            app.answer(window, allow: allow)
            HUD.shared.show("\(allow ? "Allowed" : "Denied") \(pending.tool) for \(session.label)",
                            detail: pending.summary, near: window, important: true)
        case .reply(let text):
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            session.send(message)
            HUD.shared.show("Sent to \(session.label)", near: window)
        }
    }

    // MARK: due tasks

    private func armTasks() {
        taskTimer?.cancel()
        taskTimer = nil
        announceDueTasks()
        guard let next = tasks.nextDue else { return }
        let timer = DispatchWorkItem { [weak self] in self?.armTasks() }
        taskTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + max(next.timeIntervalSinceNow, 0.1), execute: timer)
    }

    private func announceDueTasks() {
        for (item, overdue) in tasks.takeDue(now: Date()) {
            let window = app?.windows.first { $0.session.label == item.agent }
            consider(NotifyEvent(kind: .taskDue, agentID: window?.session.id.uuidString ?? "", agentLabel: item.agent ?? "",
                                 text: item.title, taskID: item.id, overdue: overdue), from: nil)
        }
    }

    // MARK: menu bar

    private func refreshIndicator() {
        let windows = app?.windows ?? []
        let pending = windows.filter { $0.session.pending != nil }
        let finished = windows.filter { unseen.contains(ObjectIdentifier($0)) && $0.session.pending == nil }
        let title = NotifyText.needsYou(pending: pending.map(\.session.label), finished: finished.map(\.session.label))
        // The menu bar icon carries the count of agents waiting on an approval.
        app?.statusButton?.title = pending.isEmpty ? "" : " \(pending.count)"
        app?.statusButton?.imagePosition = pending.isEmpty ? .imageOnly : .imageLeft
        guard title != (indicator.isHidden ? nil : indicator.title) else { return }
        indicator.title = title ?? ""
        indicator.isHidden = title == nil
        indicatorRule.isHidden = title == nil
    }

    @objc private func jumpToNeediest() {
        guard let app else { return }
        let windows = app.windows
        let candidates = windows.map { window -> Attention.Candidate in
            let key = ObjectIdentifier(window)
            return Attention.Candidate(pendingSince: window.session.pending == nil ? nil : (askedAt[key] ?? Date()),
                                       finishedAt: unseen.contains(key) ? Date() : nil)
        }
        guard let index = Attention.mostNeedy(candidates) else { return }
        windows[index].orderFrontRegardless()
        app.activate(windows[index])
    }
}
