import AppKit
import Carbon.HIToolbox

/// Global hotkeys: approve or deny the oldest waiting request, jump to the agent that needs you.
/// Every answer given by hotkey is confirmed in a HUD that says exactly what was answered.
final class Hotkeys: Feature {
    /// When on (the default), a second answer is refused until the previous confirmation has
    /// been visible for `guardInterval`, so a held or bounced key cannot clear a queue unseen.
    static let guardKey = "nook.hotkey.approvalGuard"
    static let guardInterval: TimeInterval = 0.3

    private weak var app: AppController?
    private var waiting: [ObjectIdentifier: (request: String, since: Date)] = [:]
    private var finished: [ObjectIdentifier: Date] = [:]
    private var states: [ObjectIdentifier: AgentState] = [:]
    private var lastConfirmation: Date?
    private var hidden = false

    func install(in app: AppController) {
        self.app = app
        UserDefaults.standard.register(defaults: [Self.guardKey: true])

        let centre = NotificationCenter.default
        centre.addObserver(forName: .nookSessionChanged, object: nil, queue: .main) { [weak self] note in
            if let window = note.object as? AgentWindow { self?.track(window) }
        }
        centre.addObserver(forName: .nookAgentsChanged, object: nil, queue: .main) { [weak self] _ in self?.agentsChanged() }
        centre.addObserver(forName: .nookActiveChanged, object: nil, queue: .main) { [weak self] _ in
            if let active = self?.app?.active { self?.finished[ObjectIdentifier(active)] = nil }
        }
        app.windows.forEach(track)

        let mods: NSEvent.ModifierFlags = [.control, .option]
        let keys = HotkeyCenter.shared
        keys.register(id: "approve", title: "Allow oldest request", defaultCombo: KeyCombo(kVK_ANSI_A, mods)) { [weak self] in self?.answer(allow: true) }
        keys.register(id: "deny", title: "Deny oldest request", defaultCombo: KeyCombo(kVK_ANSI_D, mods)) { [weak self] in self?.answer(allow: false) }
        keys.register(id: "jump", title: "Jump to agent needing attention", defaultCombo: KeyCombo(kVK_Space, mods)) { [weak self] in self?.jump() }
        keys.register(id: "cycle", title: "Next agent", defaultCombo: KeyCombo(kVK_ANSI_N, mods)) { [weak self] in self?.cycle() }
        keys.register(id: "quiet", title: "Toggle quiet mode", defaultCombo: KeyCombo(kVK_ANSI_Q, mods)) { QuietMode.current?.toggle() }
        keys.register(id: "hide", title: "Hide or show all agents", defaultCombo: KeyCombo(kVK_ANSI_H, mods)) { [weak self] in self?.toggleHidden() }
    }

    // MARK: tracking

    /// Stamps the moment a request appeared and the moment a turn finished.
    private func track(_ window: AgentWindow) {
        let key = ObjectIdentifier(window)
        if let request = window.session.pending {
            if waiting[key]?.request != request.requestID { waiting[key] = (request.requestID, Date()) }
        } else {
            waiting[key] = nil
        }
        let state = window.session.state
        if state == .done, states[key] != .done, app?.active !== window { finished[key] = Date() }
        states[key] = state
    }

    private func agentsChanged() {
        guard let app else { return }
        let live = Set(app.windows.map { ObjectIdentifier($0) })
        waiting = waiting.filter { live.contains($0.key) }
        finished = finished.filter { live.contains($0.key) }
        states = states.filter { live.contains($0.key) }
        if hidden { app.floatingWindows.forEach { $0.orderOut(nil) } } // a new agent orders itself front
    }

    private func candidates(_ windows: [AgentWindow]) -> [Attention.Candidate] {
        windows.map { window in
            let key = ObjectIdentifier(window)
            // Only a request that is still pending counts, whatever the bookkeeping says.
            let since = window.session.pending == nil ? nil : (waiting[key]?.since ?? Date())
            return Attention.Candidate(pendingSince: since, unread: window.session.unread, finishedAt: finished[key])
        }
    }

    // MARK: actions

    private func answer(allow: Bool) {
        guard let app else { return }
        let guarded = UserDefaults.standard.bool(forKey: Self.guardKey)
        if guarded, !Attention.acceptsAnswer(now: Date(), lastConfirmationShown: lastConfirmation, minimum: Self.guardInterval) { return }

        let windows = app.windows
        guard let index = Attention.oldestPending(candidates(windows)), let request = windows[index].session.pending else {
            HUD.shared.show("Nothing is waiting for approval")
            return
        }
        let window = windows[index]
        app.answer(window, allow: allow)
        lastConfirmation = Date()
        HUD.shared.show("\(allow ? "Allowed" : "Denied") \(request.tool) for \(window.session.label)",
                        detail: request.summary, near: window, important: true)
    }

    private func jump() {
        guard let app else { return }
        let windows = app.windows
        guard let index = Attention.mostNeedy(candidates(windows)) else {
            HUD.shared.show("No agent needs you")
            return
        }
        reveal()
        app.activate(windows[index])
    }

    private func cycle() {
        guard let app else { return }
        let windows = app.windows
        let current = windows.firstIndex { $0 === app.active }
        guard let index = Attention.next(after: current, count: windows.count) else { return }
        reveal()
        app.activate(windows[index])
    }

    private func toggleHidden() {
        guard let app else { return }
        if hidden {
            reveal()
        } else {
            hidden = true
            app.deactivate()
            app.floatingWindows.forEach { $0.orderOut(nil) }
        }
    }

    private func reveal() {
        guard hidden, let app else { return }
        hidden = false
        app.floatingWindows.forEach { $0.orderFrontRegardless() }
    }
}
