import AppKit

/// Clickable objects in a scene: the task board and the calendar. This file is the driver: it
/// opens the panels, keeps the props in the scene telling the truth, and is the only place that
/// sends anything to an agent without the user pressing a key.
///
/// Every automatic path (an agent's auto queue, a task marked to run when unblocked, scheduled
/// prompts) is off until the user switches it on, lights a marker in the window while it is armed,
/// and writes a system line naming its source into the transcript before it sends, which quiet
/// mode does not hide. What may be sent is decided by `TaskScheduler`; the tasks themselves live in
/// `TaskHub.shared.store`, and the notice board is a view of that list filtered to one agent.
/// Nothing here polls: session notifications, one timer set to the next due time, and the system's
/// day-change, wake and clock-change notifications.
final class Hotspots: NSObject, Feature {
    enum ID {
        static let tasks = "tasks"
        static let calendar = "calendar"
    }

    /// What Nook sent that the agent has not finished yet.
    private enum Outstanding {
        case task(UUID)
        case scheduled(UUID)
    }

    private weak var app: AppController?
    private var store: TaskStore { TaskHub.shared.store }
    private let calendars: HotspotStore<AgentCalendar>
    private let panel = HotspotPanel()
    private var timer: Timer?

    /// Runtime only, by agent key. Auto mode is deliberately not saved: a relaunch starts with it off.
    private var auto = Set<String>()
    private var sentThisRun: [String: Int] = [:]
    private var outstanding: [String: Outstanding] = [:]
    /// Ready tasks the scheduler held back, so the transcript says why once rather than at every change.
    private var held = Set<UUID>()
    /// Scheduled prompts that came due mid-turn, waiting for the agent to be free.
    private var waiting: [String: [UUID]] = [:]
    /// By session, not by folder: a reopened agent starts counting again.
    private var turnsSeen: [UUID: Int] = [:]
    /// Session changes arrive many times a second while an agent streams; views only hear of a real change.
    private var wasFree: [UUID: Bool] = [:]
    private var plans: [UUID: [AgentTodo]] = [:]
    private var planNews = Set<String>()

    private weak var boardModel: TaskBoardModel?
    private weak var calendarModel: CalendarModel?
    /// The mouse-down that closed a panel is followed by the click that would reopen it.
    private var closed: (hotspot: String, window: ObjectIdentifier, at: TimeInterval)?

    init(folder: URL? = nil) {
        calendars = HotspotStore(name: "schedule.json", folder: folder) { AgentCalendar() }
        super.init()
    }

    func install(in app: AppController) {
        self.app = app
        // A task that was out when Nook last quit never reported back.
        store.edit { tasks in
            for task in tasks where task.status.isOut { tasks.finish(task.id, summary: "Nook closed before it finished", failed: true, at: Date()) }
        }
        TaskHub.shared.driver = self
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(tasksChanged), name: TaskStore.changed, object: nil)
        centre.addObserver(self, selector: #selector(clicked(_:)), name: .nookHotspot, object: nil)
        centre.addObserver(self, selector: #selector(sessionChanged(_:)), name: .nookSessionChanged, object: nil)
        centre.addObserver(self, selector: #selector(agentsChanged), name: .nookAgentsChanged, object: nil)
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            centre.addObserver(self, selector: #selector(clockChanged), name: name, object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clockChanged), name: NSWorkspace.didWakeNotification, object: nil)
        panel.onClose = { [weak self] in self?.panelClosed() }
        tick(launching: true)
        agentsChanged()
    }

    static func key(for session: AgentSession) -> String { session.cwd?.path ?? "demo:" + session.label }

    private func window(for key: String) -> AgentWindow? { app?.windows.first { Self.key(for: $0.session) == key } }

    static func isFree(_ session: AgentSession) -> Bool {
        !session.state.busy && session.pending == nil && session.turnStarted == nil
    }

    // MARK: panels

    @objc private func clicked(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? String, let window = note.userInfo?["window"] as? AgentWindow else { return }
        if let closed, closed.hotspot == id, closed.window == ObjectIdentifier(window),
           ProcessInfo.processInfo.systemUptime - closed.at < 0.6 { return } // clicking the open panel's own prop closes it
        let key = Self.key(for: window.session)
        switch id {
        case ID.tasks:
            let model = TaskBoardModel(feature: self, window: window)
            boardModel = model
            planNews.remove(key)
            store.markSeen(key, at: Date())
            panel.present(TaskBoardView(model: model), size: CGSize(width: TextSize.metric(400), height: TextSize.metric(560)), hotspot: id, beside: window)
        case ID.calendar:
            let model = CalendarModel(feature: self, window: window)
            calendarModel = model
            panel.present(CalendarView(model: model), size: CGSize(width: TextSize.metric(400), height: TextSize.metric(600)), hotspot: id, beside: window)
        default:
            return
        }
        refresh(window)
    }

    private func panelClosed() {
        closed = nil
        if let event = NSApp.currentEvent, event.type == .leftMouseDown, let window = event.window as? AgentWindow {
            closed = (panel.hotspot, ObjectIdentifier(window), ProcessInfo.processInfo.systemUptime)
        }
    }

    @objc private func agentsChanged() {
        guard let app else { return }
        // A panel does not outlive its window, or hang off an orb.
        if let anchor = panel.anchor, anchor.minimised || !app.windows.contains(anchor) { panel.dismiss() }
        app.windows.forEach(refresh)
        TaskHub.shared.agentsChanged()
    }

    // MARK: the scene tells the truth

    private func refresh(_ window: AgentWindow) {
        let key = Self.key(for: window.session)
        let calendar = calendars[key]
        let plan = window.session.todos.filter { $0.status != .completed }.count
        let today = Date()
        let open = store.tasks.filter { $0.agent == key && !$0.status.isFinished }.count
        let news = planNews.contains(key) || store.tasks.hasNews(for: key, since: store.seen(key), now: today)
        window.room.showHotspot(ID.tasks, HotspotState(level: open + plan, news: news))
        let marked = calendar.hasRun(on: today) || calendar.items.contains { $0.missed != nil }
        window.room.showHotspot(ID.calendar, HotspotState(news: marked, number: Calendar.current.component(.day, from: today)))
        window.automation = auto.contains(key) || calendar.items.contains(where: \.enabled)
    }

    // MARK: turns

    @objc private func sessionChanged(_ note: Notification) {
        guard let window = note.object as? AgentWindow else { return }
        let session = window.session
        let key = Self.key(for: session)

        if session.todos != plans[session.id] ?? [] {
            plans[session.id] = session.todos
            if !(panel.anchor === window && panel.hotspot == ID.tasks) { planNews.insert(key) }
            boardModel?.reload()
            TaskHub.shared.agentsChanged()
            refresh(window)
        }
        if case .task(let id) = outstanding[key], session.turnStarted != nil, store.tasks.task(id)?.status == .sent {
            store.edit { tasks in
                if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].status = .running }
            }
        }
        if session.turnsCompleted != turnsSeen[session.id] ?? 0 {
            turnsSeen[session.id] = session.turnsCompleted
            turnFinished(window, key: key)
        }
        let free = Self.isFree(session)
        if free != wasFree[session.id] ?? true {
            wasFree[session.id] = free
            boardModel?.reload()
            TaskHub.shared.agentsChanged()
        }
        guard free else { return }
        if let next = waiting[key]?.first {
            waiting[key]?.removeFirst()
            run(next, on: window)
        } else {
            pump()
        }
    }

    private func turnFinished(_ window: AgentWindow, key: String) {
        let session = window.session
        let (summary, failed, now) = (session.summary, session.lastTurnFailed, Date())
        var source = ""
        switch outstanding.removeValue(forKey: key) {
        case .task(let id):
            source = "Queued task"
            store.edit { $0.finish(id, summary: summary, failed: failed, at: now) }
        case .scheduled(let id):
            source = "Scheduled"
            calendars.update(key) { calendar in
                guard let index = calendar.items.firstIndex(where: { $0.id == id }) else { return }
                calendar.items[index].lastRun = now
                calendar.items[index].lastSummary = summary
                calendar.items[index].lastFailed = failed
            }
        case nil:
            break
        }
        calendars.update(key) { $0.record(.init(date: now, summary: summary, failed: failed, source: source)) }
        calendarModel?.reload()
        refresh(window)
    }

    /// The list changed, from the hub, a notice board or a finished turn.
    @objc private func tasksChanged() {
        if let anchor = panel.anchor, panel.hotspot == ID.tasks {
            // The open board is being looked at: what arrives is seen. Marking clears the news, so this does not loop.
            let key = Self.key(for: anchor.session)
            if store.tasks.hasNews(for: key, since: store.seen(key), now: Date()) { store.markSeen(key, at: Date()) }
        }
        boardModel?.reload()
        app?.windows.forEach(refresh)
    }

    // MARK: sending tasks

    func isAuto(_ key: String) -> Bool { auto.contains(key) }

    /// How the scheduler sees each open agent. Two windows on one folder count once, as the first.
    func agentStates() -> [TaskScheduler.Agent] {
        (app?.windows ?? []).map { window in
            let session = window.session
            let key = Self.key(for: session)
            let state: TaskScheduler.AgentState = session.pending != nil ? .pendingPermission
                : !Self.isFree(session) || outstanding[key] != nil ? .busy
                : session.lastTurnFailed ? .lastTurnFailed : .idle
            return TaskScheduler.Agent(key: key, state: state, auto: auto.contains(key), sentThisRun: sentThisRun[key] ?? 0)
        }
    }

    /// The user's own click or key: sends this task now, and starts a fresh automatic run count.
    /// Returns why not, if it cannot go.
    @discardableResult
    func sendNow(_ id: UUID) -> String? {
        guard let task = store.tasks.task(id) else { return "That task is gone" }
        let agent = agentStates().first { $0.key == task.agent }
        if let refusal = TaskScheduler.refusal(task, in: store.tasks, agent: agent) { return refusal }
        guard let key = task.agent, let window = window(for: key) else { return "Its agent is not open" }
        sentThisRun[key] = 0
        send(task, to: window, key: key, source: nil)
        return nil
    }

    func setAuto(_ on: Bool, for key: String) {
        guard on != auto.contains(key), let window = window(for: key) else { return }
        if on { auto.insert(key) } else { auto.remove(key) }
        sentThisRun[key] = 0
        window.session.remark(on ? "Auto queue on: queued tasks are sent as each turn finishes, at most \(TaskScheduler.limit) in a row."
                                 : "Auto queue off.")
        autoChanged(window)
        pump()
    }

    private func autoChanged(_ window: AgentWindow) {
        boardModel?.reload()
        TaskHub.shared.agentsChanged()
        refresh(window)
    }

    /// The one decision point for automatic sends. Called whenever an agent might have become free
    /// or the list changed; it looks at every agent, because a task may wait on another agent's.
    func pump() {
        let tasks = store.tasks
        guard tasks.contains(where: { $0.status == .queued && $0.agent != nil }) else { return }
        let plan = TaskScheduler.plan(tasks: tasks, agents: agentStates(), limit: TaskScheduler.limit)
        for hold in plan.holds {
            guard let window = window(for: hold.agent) else { continue }
            switch hold.source {
            case .autoQueue:
                auto.remove(hold.agent)
                let count = tasks.filter { $0.agent == hold.agent && $0.status == .queued }.count
                window.session.remark("Auto queue stopped: \(hold.why). \(count) queued tasks are waiting.")
                autoChanged(window)
            case .chain:
                guard held.insert(hold.task).inserted, let task = tasks.task(hold.task) else { continue }
                window.session.remark("Chained task held (“\(task.title)”): \(hold.why). Send it yourself from the task board when ready.")
            }
        }
        for item in plan.sends {
            guard let task = tasks.task(item.task), let window = window(for: item.agent) else { continue }
            send(task, to: window, key: item.agent, source: item.source)
        }
    }

    private func send(_ task: NookTask, to window: AgentWindow, key: String, source: TaskScheduler.Source?) {
        // Marked before anything is logged: the log line itself comes back here as a session change.
        outstanding[key] = .task(task.id)
        held.remove(task.id)
        if source != nil { sentThisRun[key, default: 0] += 1 }
        let tasks = store.tasks
        let labels = TaskHub.shared.label(forAgent:)
        store.edit { list in
            guard let index = list.firstIndex(where: { $0.id == task.id }) else { return }
            (list[index].status, list[index].sent, list[index].automatic) = (.sent, Date(), source != nil)
        }
        window.session.remark(TaskPrompt.note(task, in: tasks, source: source, labels: labels))
        window.session.send(TaskPrompt.compose(task, in: tasks))
    }

    // MARK: the calendar

    func calendar(for window: AgentWindow) -> AgentCalendar { calendars[Self.key(for: window.session)] }

    func editCalendar(_ window: AgentWindow, _ change: (inout AgentCalendar) -> Void) {
        calendars.update(Self.key(for: window.session), change)
        calendarModel?.reload()
        refresh(window)
        arm()
    }

    /// "Run now" on a missed item, or on any item: the user asked, so it goes even though its time has passed.
    func runNow(_ id: UUID, on window: AgentWindow) {
        calendars.update(Self.key(for: window.session)) { calendar in
            if let index = calendar.items.firstIndex(where: { $0.id == id }) { calendar.items[index].missed = nil }
        }
        run(id, on: window)
    }

    /// Sends a scheduled prompt, or holds it until the turn in progress (or the permission question) is over.
    private func run(_ id: UUID, on window: AgentWindow) {
        let key = Self.key(for: window.session)
        guard let item = calendars[key].items.first(where: { $0.id == id }) else { return }
        guard Self.isFree(window.session), outstanding[key] == nil else {
            if waiting[key]?.contains(id) != true { waiting[key, default: []].append(id) }
            return
        }
        outstanding[key] = .scheduled(id)
        window.session.remark("Scheduled (\(item.schedule.summary())): \(item.prompt)")
        window.session.send(item.prompt)
        calendarModel?.reload()
        refresh(window)
    }

    @objc private func clockChanged() {
        tick(launching: false)
        app?.windows.forEach(refresh) // a new day: the calendar's number
    }

    /// Deals with everything due up to now, then sets the one timer to the next due time.
    private func tick(launching: Bool) {
        let now = Date()
        for key in calendars.keys {
            var due: [UUID] = []
            calendars.update(key) { due = ScheduleClock.reconcile(&$0.items, now: now, launching: launching) }
            guard !due.isEmpty else { continue }
            if let window = window(for: key) {
                due.forEach { run($0, on: window) }
            } else {
                // Its agent is not open: nothing is started behind the user's back.
                calendars.update(key) { calendar in
                    for index in calendar.items.indices where due.contains(calendar.items[index].id) { calendar.items[index].missed = now }
                }
            }
        }
        calendarModel?.reload()
        arm()
    }

    private func arm() {
        timer?.invalidate()
        timer = nil
        guard let next = calendars.keys.compactMap({ ScheduleClock.nextWake(calendars[$0].items) }).min() else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.tick(launching: false)
            self?.app?.windows.forEach { self?.refresh($0) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
