import AppKit

extension Notification.Name {
    /// The synced events, or the state of a sync, changed. Object: CalendarSync.
    static let nookCalendarChanged = Notification.Name("nookCalendarChanged")
}

/// Brings the user's real calendar into Nook through the calendar MCP tools their Claude Code already has.
///
/// Every sync is a paid `claude` job, so there are only three ways one starts: the calendar panel
/// opens with a cache older than 15 minutes, the user presses Refresh, or, if they switched
/// `nook.calendar.backgroundSync` on, one timer set an hour after the last attempt. The very first
/// sync is always the user's click. Nothing is ever written to the calendar except one event the
/// user confirmed, and only with `nook.calendar.allowWrites` on.
final class CalendarSync: NSObject, Feature {
    static let backgroundKey = "nook.calendar.backgroundSync"
    static let writesKey = "nook.calendar.allowWrites"

    enum Status: Equatable {
        case idle, discovering, syncing
        /// The CLI offers no tool that lists calendar events.
        case notConnected
        case failed(String)

        var busy: Bool { self == .discovering || self == .syncing }
    }

    /// The panel and quiet mode reach the feature through here.
    private(set) static weak var current: CalendarSync?

    private weak var app: AppController?
    private let bridge = CalendarBridge()
    private let file: URL
    private var timer: Timer?
    private var lastAttempt: Date?
    private var background = false

    private(set) var cache: CalendarCache?
    private(set) var status = Status.idle { didSet { if status != oldValue { changed() } } }

    var events: [CalendarEvent] { cache?.events ?? [] }
    var allowsWrites: Bool { UserDefaults.standard.bool(forKey: Self.writesKey) && CalendarTools.stored?.create != nil }

    init(file: URL = CalendarCache.defaultFile) {
        self.file = file
        super.init()
    }

    func install(in app: AppController) {
        self.app = app
        Self.current = self
        UserDefaults.standard.register(defaults: [Self.backgroundKey: false, Self.writesKey: false])
        cache = CalendarCache.load(from: file)
        background = UserDefaults.standard.bool(forKey: Self.backgroundKey)
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(agentsChanged), name: .nookAgentsChanged, object: nil)
        centre.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(arm), name: NSWorkspace.didWakeNotification, object: nil)
        changed()
        arm()
    }

    // MARK: when a sync runs

    func panelOpened() { syncIfDue(.panelOpened) }

    /// The Refresh, Connect and Retry buttons. After a failure the tools are looked up afresh.
    func refresh() {
        if !status.busy, status != .idle { CalendarTools.stored = nil }
        syncIfDue(.refreshButton)
    }

    func cancel() { bridge.cancel() }

    private func syncIfDue(_ reason: SyncPolicy.Reason) {
        guard !bridge.isRunning, SyncPolicy.shouldSync(reason, lastSync: cache?.syncedAt, lastAttempt: lastAttempt, now: Date(),
                                                       backgroundEnabled: background) else { return }
        lastAttempt = Date()
        if let tools = CalendarTools.stored, tools.canRead { list(with: tools) } else { discover() }
    }

    private func discover() {
        status = .discovering
        bridge.run(.discover, timeout: 60) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                let tools = CalendarTools.discover(in: output.tools ?? [])
                CalendarTools.stored = tools
                if tools.canRead { self.list(with: tools) } else { self.finish(.notConnected) }
            case .failure(let failure):
                self.finish(.failed(failure.message))
            }
        }
    }

    private func list(with tools: CalendarTools) {
        status = .syncing
        let window = CalendarCache.window(around: Date())
        bridge.run(.list(window, tools)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                guard let events = EventDecoding.events(from: output.structured) else {
                    // A refused connector usually makes the job answer in prose instead of the schema.
                    let said = output.saidText ?? ""
                    return self.finish(.failed(SyncProblem.isAuthorisation(said) ? SyncProblem.notAuthorised
                                                                                 : "The calendar job returned nothing readable."))
                }
                let answer = output.structured as? [String: Any]
                // Tools that failed look like an empty calendar; keeping the old cache beats believing that.
                if let problem = SyncProblem.message(problem: answer?["problem"] as? String, eventCount: events.count) { return self.finish(.failed(problem)) }
                let truncated = answer?["truncated"] as? Bool ?? false
                let cache = CalendarCache(syncedAt: Date(), window: window, costUSD: output.costUSD, truncated: truncated, events: events)
                cache.save(to: self.file)
                self.cache = cache
                self.reanchor()
                self.finish(.idle)
            case .failure(.cancelled):
                self.finish(.idle)
            case .failure(let failure):
                self.finish(.failed(failure.message))
            }
        }
    }

    private func finish(_ status: Status) {
        let same = self.status == status
        self.status = status
        if same { changed() } // the events changed even though the status did not
        arm()
    }

    private func changed() { NotificationCenter.default.post(name: .nookCalendarChanged, object: self) }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = UserDefaults.standard.bool(forKey: Self.backgroundKey)
            guard now != self.background else { return }
            self.background = now
            self.arm()
        }
    }

    /// The one background timer; not set at all unless the user switched background sync on.
    @objc private func arm() {
        timer?.invalidate()
        timer = nil
        guard let next = SyncPolicy.nextBackgroundSync(lastSync: cache?.syncedAt, lastAttempt: lastAttempt, enabled: background) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.syncIfDue(.background) }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: prompts tied to events

    @objc private func agentsChanged() { reanchor() }

    /// Open agents only: `Hotspots` edits a calendar through its window. An agent opened later is
    /// brought up to date by the agents-changed notification.
    private func reanchor() {
        guard let cache, let hotspots = Hotspots.current, let app else { return }
        let now = Date()
        for window in app.windows where hotspots.calendar(for: window).items.contains(where: { $0.anchor != nil }) {
            hotspots.editCalendar(window) { EventAnchoring.reanchor(&$0.items, events: cache.events, window: cache.window, complete: !cache.truncated, now: now) }
        }
    }

    // MARK: write-back

    /// Creates the one event the user has just been shown and confirmed. Never called by anything but that button.
    func create(_ draft: CalendarBridge.EventDraft, completion: @escaping (String?) -> Void) {
        guard allowsWrites, let tools = CalendarTools.stored else { return completion("Adding to the calendar is switched off.") }
        bridge.run(.create(draft, tools), timeout: 120) { result in
            switch result {
            case .success(let output):
                let answer = output.structured as? [String: Any]
                completion(answer?["created"] as? Bool == true ? nil : "The calendar did not confirm the event.")
            case .failure(let failure):
                completion(failure.message)
            }
        }
    }
}
