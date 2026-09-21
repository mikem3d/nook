import AppKit

/// Clickable objects in a scene: the task board and the calendar. This file is the driver: it
/// opens the panels, keeps the props in the scene telling the truth, and is the only place that
/// sends anything to an agent without the user pressing a key.
///
/// Both automatic paths (the queue's auto mode, scheduled prompts) are off until the user switches
/// them on, light a marker in the window while they are armed, and write a system line naming
/// their source into the transcript before they send, which quiet mode does not hide.
/// Nothing here polls: session notifications, one timer set to the next due time, and the system's
/// day-change, wake and clock-change notifications.
final class Hotspots: NSObject, Feature {
    enum ID {
        static let tasks = "tasks"
        static let calendar = "calendar"
    }

    /// What Nook sent that the agent has not finished yet.
    private enum Outstanding {
        case task
        case scheduled(UUID)
    }

    /// Calendar sync re-anchors event-tied prompts through here.
    private(set) static weak var current: Hotspots?
    private weak var app: AppController?
    private let tasks: HotspotStore<TaskQueue>
    private let calendars: HotspotStore<AgentCalendar>
    private let panel = HotspotPanel()
    private var timer: Timer?

    /// Runtime only, by agent key. Auto mode is deliberately not saved: a relaunch starts with it off.
    private var auto = Set<String>()
    private var sentThisRun: [String: Int] = [:]
    private var outstanding: [String: Outstanding] = [:]
    /// Scheduled prompts that came due mid-turn, waiting for the agent to be free.
    private var waiting: [String: [UUID]] = [:]
    /// By session, not by folder: a reopened agent starts counting again.
    private var turnsSeen: [UUID: Int] = [:]
    private var plans: [UUID: [AgentTodo]] = [:]
    private var planNews = Set<String>()

    private weak var boardModel: TaskBoardModel?
    private weak var calendarModel: CalendarModel?
    /// The mouse-down that closed a panel is followed by the click that would reopen it.
    private var closed: (hotspot: String, window: ObjectIdentifier, at: TimeInterval)?

    init(folder: URL? = nil) {
        tasks = HotspotStore(name: "tasks.json", folder: folder) { TaskQueue() }
        calendars = HotspotStore(name: "schedule.json", folder: folder) { AgentCalendar() }
        super.init()
    }

    func install(in app: AppController) {
        self.app = app
        Self.current = self
        // A task that was out when Nook last quit never reported back.
        for key in tasks.keys where tasks[key].sending != nil {
            tasks.update(key) { $0.finish(summary: "Nook closed before it finished", failed: true, at: Date()) }
        }
        let centre = NotificationCenter.default
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
            tasks.update(key) { $0.unseen = false }
            planNews.remove(key)
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
    }

    // MARK: the scene tells the truth

    private func refresh(_ window: AgentWindow) {
        let key = Self.key(for: window.session)
        let queue = tasks[key]
        let calendar = calendars[key]
        let plan = window.session.todos.filter { $0.status != .completed }.count
        window.room.showHotspot(ID.tasks, HotspotState(level: queue.open + plan, news: queue.unseen || planNews.contains(key)))
        let today = Date()
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
            refresh(window)
        }
        if session.turnsCompleted != turnsSeen[session.id] ?? 0 {
            turnsSeen[session.id] = session.turnsCompleted
            turnFinished(window, key: key)
        }
        if boardModel?.window === window { boardModel?.reloadStatus() }
        guard Self.isFree(session) else { return }
        if let next = waiting[key]?.first {
            waiting[key]?.removeFirst()
            run(next, on: window)
        } else {
            pump(window)
        }
    }

    private func turnFinished(_ window: AgentWindow, key: String) {
        let session = window.session
        let (summary, failed, now) = (session.summary, session.lastTurnFailed, Date())
        var source = ""
        switch outstanding.removeValue(forKey: key) {
        case .task:
            source = "Queued task"
            tasks.update(key) { $0.finish(summary: summary, failed: failed, at: now) }
            if panel.anchor === window, panel.hotspot == ID.tasks { tasks.update(key) { $0.unseen = false } }
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
        reloadModels()
        refresh(window)
    }

    private func reloadModels() {
        boardModel?.reload()
        calendarModel?.reload()
    }

    // MARK: the task queue

    func queue(for window: AgentWindow) -> TaskQueue { tasks[Self.key(for: window.session)] }
    func isAuto(_ window: AgentWindow) -> Bool { auto.contains(Self.key(for: window.session)) }

    func editQueue(_ window: AgentWindow, _ change: (inout TaskQueue) -> Void) {
        tasks.update(Self.key(for: window.session), change)
        reloadModels()
        refresh(window)
        pump(window)
    }

    /// The user's own click: sends the top task now, and starts a fresh auto run count.
    func sendNext(_ window: AgentWindow) {
        let key = Self.key(for: window.session)
        guard Self.isFree(window.session), outstanding[key] == nil else { return }
        sentThisRun[key] = 0
        send(window, key: key, automatic: false)
    }

    func setAuto(_ on: Bool, for window: AgentWindow) {
        let key = Self.key(for: window.session)
        guard on != auto.contains(key) else { return }
        if on { auto.insert(key) } else { auto.remove(key) }
        sentThisRun[key] = 0
        window.session.remark(on ? "Auto queue on: queued tasks are sent as each turn finishes, at most \(AutoRun.limit) in a row."
                                 : "Auto queue off.")
        reloadModels()
        refresh(window)
        pump(window)
    }

    /// Auto mode's one decision point. Called whenever the agent might have become free.
    private func pump(_ window: AgentWindow) {
        let session = window.session
        let key = Self.key(for: session)
        let decision = AutoRun.decide(auto: auto.contains(key), queued: tasks[key].queued.count, free: Self.isFree(session),
                                      waitingForPermission: session.pending != nil, outstanding: outstanding[key] != nil,
                                      lastTurnFailed: session.lastTurnFailed, sentThisRun: sentThisRun[key] ?? 0, limit: AutoRun.limit)
        switch decision {
        case .wait:
            break
        case .send:
            send(window, key: key, automatic: true)
        case .stop(let why):
            auto.remove(key)
            session.remark("Auto queue stopped: \(why). \(tasks[key].queued.count) queued tasks are waiting.")
            reloadModels()
            refresh(window)
        }
    }

    private func send(_ window: AgentWindow, key: String, automatic: Bool) {
        var item: TaskQueue.Item?
        tasks.update(key) { item = $0.takeNext(automatic: automatic) }
        guard let item else { return }
        // Marked before anything is logged: the log line itself comes back here as a session change.
        outstanding[key] = .task
        if automatic { sentThisRun[key, default: 0] += 1 }
        window.session.remark((automatic ? "Queued task (sent automatically): " : "Queued task: ") + item.text)
        window.session.send(item.text)
        reloadModels()
        refresh(window)
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
