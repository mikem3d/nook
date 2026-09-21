// TaskHub: one task board across every agent, with priorities, due dates and chains between agents.
//
// For other features (read-only; nothing here needs a permission or an Info.plist key):
//
//     TaskHub.shared.tasks                  every task, as `NookTask` values (Tasks/NookTask.swift)
//     TaskHub.shared.dueSoon                open tasks that are overdue or due within 24 hours, soonest first
//     TaskHub.shared.dueSoon(within:)       the same with another horizon, in seconds
//     TaskHub.shared.label(forAgent:)       a task's `agent` key (its folder path) as a name to show
//
//     .nookTaskChanged    userInfo["task"]: NookTask. Posted when a task is added, edited, sent, finished
//                         or removed (userInfo["removed"] == true, with the task as it last was), and once
//                         at the moment a task goes overdue (userInfo["overdue"] == true).
//     .nookTaskFinished   userInfo["task"]: NookTask, status `.done` or `.failed`, `result` holding the
//                         turn's summary. Posted once, when the turn that carried the task ends.
//
// Both are posted on the main thread with the TaskStore as object. `task.isOverdue(at:)`,
// `task.isDueToday(at:)` and `task.dueText()` say how a due date reads. Nothing polls: the overdue
// notice comes from one timer set to the next deadline.
//
// Sending is not done here. `Hotspots` is the only place that sends to an agent; this file owns the
// list, the hub panel, the menu item and the hotkey.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// An agent as the hub shows it: open in a window, or only remembered by the tasks assigned to it.
struct HubAgent: Identifiable, Equatable {
    var key: String
    var label: String
    /// nil when its window is not open.
    var state: TaskScheduler.AgentState?
    var auto = false
    var todos: [AgentTodo] = []

    var id: String { key }
}

final class TaskHub: NSObject, Feature {
    private static var current: TaskHub?
    /// The hub AppController registered. The first one made wins, so a test can make its own.
    static var shared: TaskHub { current ?? TaskHub() }

    let store: TaskStore
    /// Set by `Hotspots` when it installs.
    weak var driver: Hotspots?
    private weak var app: AppController?
    private var panel: TaskHubPanel?
    private weak var model: TaskHubModel?
    private var timer: Timer?
    /// Deadlines up to here have been announced.
    private var overdueChecked = Date()

    init(folder: URL? = nil) {
        store = TaskStore(folder: folder)
        super.init()
        if Self.current == nil { Self.current = self }
    }

    func install(in app: AppController) {
        self.app = app
        let item = NSMenuItem(title: "Task Board", action: #selector(toggle), keyEquivalent: "")
        item.target = self
        app.addMenuItem(item)
        HotkeyCenter.shared.register(id: "tasks.hub", title: "Show or hide the task board",
                                     defaultCombo: KeyCombo(kVK_ANSI_T, [.control, .option])) { [weak self] in self?.toggle() }
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(storeChanged), name: TaskStore.changed, object: store)
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            centre.addObserver(self, selector: #selector(clockChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clockChanged), name: NSWorkspace.didWakeNotification, object: nil)
        arm()
    }

    // MARK: reading

    var tasks: [NookTask] { store.tasks }

    var dueSoon: [NookTask] { dueSoon(within: 24 * 3600) }

    func dueSoon(within seconds: TimeInterval) -> [NookTask] {
        let now = Date()
        return store.tasks.dueSoon(now: now, horizon: now.addingTimeInterval(seconds))
    }

    func label(forAgent key: String) -> String {
        app?.windows.first { Hotspots.key(for: $0.session) == key }?.session.label ?? NookTask.label(forAgent: key)
    }

    /// Open agents in window order, then agents that are closed but still have tasks on the board.
    func agents() -> [HubAgent] {
        var result: [HubAgent] = []
        let states = driver?.agentStates() ?? []
        for window in app?.windows ?? [] {
            let key = Hotspots.key(for: window.session)
            guard !result.contains(where: { $0.key == key }) else { continue }
            let state = states.first { $0.key == key }
            result.append(HubAgent(key: key, label: window.session.label, state: state?.state ?? .idle, auto: state?.auto ?? false, todos: window.session.todos))
        }
        for key in store.tasks.compactMap(\.agent) where !result.contains(where: { $0.key == key }) {
            result.append(HubAgent(key: key, label: NookTask.label(forAgent: key)))
        }
        return result
    }

    // MARK: editing (the user's own actions, from the hub or a notice board)

    /// Changes the list, then lets the scheduler look: an edit can unblock something.
    func edit(_ change: (inout [NookTask]) -> Void) {
        if store.edit(change) { driver?.pump() }
    }

    /// Adds what a quick-add line describes. A line that names no agent goes to `defaultAgent`, or the inbox.
    @discardableResult
    func add(_ line: String, defaultAgent: String? = nil) -> NookTask? {
        let names = agents().map { QuickAdd.AgentName(key: $0.key, label: $0.label) }
        let parsed = QuickAdd.parse(line, agents: names, now: Date())
        guard !parsed.title.isEmpty else { return nil }
        let task = NookTask(title: parsed.title, priority: parsed.priority, due: parsed.due, dueHasTime: parsed.dueHasTime,
                            agent: parsed.agent ?? defaultAgent, tags: parsed.tags)
        edit { $0.append(task) }
        return task
    }

    func sendNow(_ id: UUID) -> String? { driver.map { $0.sendNow(id) } ?? "Sending is not available" }

    func setAuto(_ on: Bool, for agent: String) { driver?.setAuto(on, for: agent) }

    /// An agent opened, closed, became free or busy, switched auto, or changed its plan.
    func agentsChanged() { model?.reloadAgents() }

    // MARK: the panel

    @objc func toggle() {
        if let panel, panel.isVisible {
            panel.close()
            return
        }
        let model = TaskHubModel(hub: self)
        self.model = model
        let panel = self.panel ?? TaskHubPanel()
        self.panel = panel
        panel.present(model: model)
    }

    // MARK: due dates

    @objc private func storeChanged() {
        model?.reloadTasks()
        arm()
    }

    @objc private func clockChanged() {
        announceOverdue()
        model?.reloadTasks() // a new day: what is due today
    }

    /// Says once that a task went overdue, which also lights its notice board's news marker.
    private func announceOverdue() {
        let now = Date()
        let late = store.tasks.filter { task in
            guard task.isOverdue(at: now), let deadline = task.deadline() else { return false }
            return deadline > overdueChecked
        }
        overdueChecked = now
        for task in late {
            NotificationCenter.default.post(name: .nookTaskChanged, object: store, userInfo: ["task": task, "overdue": true])
        }
        if !late.isEmpty { NotificationCenter.default.post(name: TaskStore.changed, object: store) }
        arm()
    }

    /// One timer, set to the next deadline. Nothing runs when no open task has a due date ahead.
    private func arm() {
        timer?.invalidate()
        timer = nil
        let now = Date()
        guard let next = store.tasks.filter({ !$0.status.isFinished }).compactMap({ $0.deadline() }).filter({ $0 > now }).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.announceOverdue() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
