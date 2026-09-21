import AppKit
import Carbon.HIToolbox

/// Quick ways to start an agent: the plus orb and its panel, recent folders, a global shortcut,
/// and folders dropped on the plus orb, the menu bar icon or the free edge beyond a stack.
final class NewAgent: NSObject, Feature, NSMenuDelegate {
    static let recentsKey = "nook.recentFolders"
    static let coachKey = "nook.newAgent.coachShown"
    private static let menuCount = 8

    /// The plus orb and the menu reach the feature through here.
    private(set) static weak var shared: NewAgent?

    private weak var app: AppController?
    private var recents = RecentFolders()
    private var suggested: [FolderChoice] = []
    private var known = Set<ObjectIdentifier>()
    private var panel: NewAgentPanel?
    private var prompt: DuplicatePrompt?
    private var coach: CoachMark?
    private var edgeDrop: EdgeDrop?
    private var statusDrop: StatusDrop?
    /// Where the agent the open panel starts should go; nil means the default corner and current screen.
    private var target: (corner: Corner, display: UInt32)?

    func install(in app: AppController) {
        self.app = app
        Self.shared = self
        if let data = UserDefaults.standard.data(forKey: Self.recentsKey),
           let saved = try? JSONDecoder().decode(RecentFolders.self, from: data) { recents = saved }

        let centre = NotificationCenter.default
        centre.addObserver(forName: .nookAgentsChanged, object: nil, queue: .main) { [weak self] _ in self?.agentsChanged() }
        centre.addObserver(forName: .nookSessionChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, let session = (note.object as? AgentWindow)?.session,
                  let folder = session.cwd?.path, let id = session.sessionID else { return }
            if self.recents.note(sessionID: id, for: folder) { self.save() }
        }

        // First run (this feature installs last, so restored and command-line agents already exist):
        // nothing on screen but the plus orb, which gets one line of explanation, once.
        let firstRun = app.windows.isEmpty && !UserDefaults.standard.bool(forKey: Self.coachKey)
        agentsChanged()
        if firstRun, let orb = app.plusOrb {
            UserDefaults.standard.set(true, forKey: Self.coachKey)
            coach = CoachMark("Click + to start an agent in a project folder", beside: orb.frame)
        }

        app.recentMenu.delegate = self
        edgeDrop = EdgeDrop(app: app)
        if let button = app.statusButton {
            statusDrop = StatusDrop(button: button) { [weak self] in self?.dropped($0, corner: nil, display: nil, near: nil) }
        }
        registerHotkey()
    }

    /// ⌃⌥= is the plus key without Shift. If something else holds it, ⌃⌥O; a choice the user made stands.
    private func registerHotkey() {
        let id = "newAgent"
        let open: () -> Void = { [weak self] in self?.present() }
        let mods: NSEvent.ModifierFlags = [.control, .option]
        HotkeyCenter.shared.register(id: id, title: "New agent", defaultCombo: KeyCombo(kVK_ANSI_Equal, mods), onPress: open)
        let untouched = UserDefaults.standard.string(forKey: HotkeyCenter.keyPrefix + id) == nil
        if untouched, HotkeyCenter.shared.info(for: id)?.problem != nil {
            HotkeyCenter.shared.register(id: id, title: "New agent", defaultCombo: KeyCombo(kVK_ANSI_O, mods), onPress: open)
        }
    }

    // MARK: recents

    /// Folders of agents that appeared since the last look move to the front of the recents.
    private func agentsChanged() {
        guard let app else { return }
        let fresh = app.windows.filter { !known.contains(ObjectIdentifier($0)) }
        known = Set(app.windows.map { ObjectIdentifier($0) })
        guard !fresh.isEmpty else { return }
        coach?.orderOut(nil)
        coach = nil
        let before = recents
        for window in fresh { if let folder = window.session.cwd?.path { recents.touch(folder, sessionID: window.session.sessionID) } }
        if recents != before { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(data, forKey: Self.recentsKey) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let folders = recents.entries.prefix(Self.menuCount).filter { FileManager.default.fileExists(atPath: $0.path) }
        for entry in folders {
            let item = ClosureItem((entry.path as NSString).lastPathComponent) { [weak self] in
                self?.start(URL(fileURLWithPath: entry.path), options: NewAgentOptions(), corner: nil, display: nil, near: nil)
            }
            item.toolTip = entry.path
            menu.addItem(item)
        }
        if folders.isEmpty { menu.addItem(withTitle: "No Recent Folders", action: nil, keyEquivalent: "") }
    }

    // MARK: the panel

    /// From a plus orb, the agent joins that orb's stack; from the menu or the shortcut, the default corner.
    func present(from orb: PlusOrbWindow? = nil) {
        guard let app else { return }
        coach?.orderOut(nil)
        coach = nil
        target = orb.map { ($0.corner, $0.display) }
        let panel = NewAgentPanel(scenes: app.art.sceneChoices)
        self.panel?.dismiss()
        self.panel = panel
        let anchor = (orb ?? app.plusOrb)?.frame
        panel.onStart = { [weak self] choice, options in
            guard let self else { return }
            self.start(URL(fileURLWithPath: choice.path), options: options, resume: options.resume ? choice.sessionID : nil,
                       corner: self.target?.corner, display: self.target?.display, near: anchor)
        }
        panel.onChooseFolder = { [weak self] options in self?.chooseFolder(options, near: anchor) }
        panel.onRemove = { [weak self] path in
            self?.recents.remove(path)
            self?.save()
            self?.refreshPanel()
        }
        refreshPanel()
        panel.present(beside: anchor)

        // The scan only lists directory names; it still stays off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = ProjectScan.suggestions()
            DispatchQueue.main.async {
                guard let self, found != self.suggested else { return }
                self.suggested = found
                self.refreshPanel()
            }
        }
    }

    private func refreshPanel() {
        guard let app, let panel else { return }
        // A recent folder that has since been deleted or unmounted is not offered (and not forgotten).
        let choices = NewAgentRules.choices(recents: recents, suggested: suggested)
            .filter { $0.source == .suggested || FileManager.default.fileExists(atPath: $0.path) }
        panel.show(choices, open: Set(app.windows.compactMap { $0.session.cwd.map { NewAgentRules.canonical($0.path) } }))
    }

    private func chooseFolder(_ options: NewAgentOptions, near anchor: NSRect?) {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.prompt = "Start Agent"
        picker.message = "Choose the project folder this agent works in."
        guard picker.runModal() == .OK, let url = picker.url else { return }
        start(url, options: options, corner: target?.corner, display: target?.display, near: anchor)
    }

    // MARK: starting

    /// Folders dropped on a plus orb, an edge zone or the menu bar icon. nil corner and display mean the defaults.
    func dropped(_ folders: [URL], corner: Corner?, display: UInt32?, near anchor: NSRect?) {
        for folder in folders { start(folder, options: NewAgentOptions(), corner: corner, display: display, near: anchor) }
    }

    /// Every way of starting an agent ends here: ask about a duplicate, start, say a word about usage.
    func start(_ folder: URL, options: NewAgentOptions, resume: String? = nil, corner: Corner?, display: UInt32?, near anchor: NSRect?) {
        guard let app else { return }
        let begin = { [weak self, weak app] in
            guard let app else { return }
            let window = app.addAgent(folder: folder, resume: resume, corner: corner ?? DockPrefs.defaultCorner, scene: options.scene)
            if let display { app.move(window, toDisplay: display) }
            if !options.message.isEmpty { window.session.send(options.message) }
            if let note = NewAgentRules.usageNote(count: app.windows.count) { HUD.shared.show(note, near: window, duration: 3.5) }
            self?.prompt = nil
        }
        guard let index = NewAgentRules.existing(folder.path, among: app.windows.map { $0.session.cwd?.path }) else { return begin() }
        let existing = app.windows[index]
        prompt = DuplicatePrompt(folder: folder.lastPathComponent, near: anchor ?? existing.frame, goToExisting: { [weak self, weak app, weak existing] in
            self?.prompt = nil
            guard let app, let existing, app.windows.contains(where: { $0 === existing }) else { return }
            if existing.minimised { app.toggleMinimise(existing) }
            app.activate(existing)
        }, startAnother: begin)
    }
}
