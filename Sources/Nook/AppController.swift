import AppKit

/// Owns every agent window, the corner stacks they dock into, and the single chat panel.
final class AppController: NSObject, NSApplicationDelegate {
    /// Stacks belong to a display, not an NSScreen object: AppKit replaces those when displays change.
    private struct StackKey: Hashable {
        let display: CGDirectDisplayID
        let corner: Corner
    }

    private typealias Axis = DockLayout.Axis

    /// One stack's direction, in a form Persistence can save.
    struct StackAxis: Codable, Equatable {
        let display: UInt32
        let corner: Int
        let axis: DockLayout.Axis
    }

    /// Read-only for the chrome and the settings window (scene choices); nil only before launch finishes.
    private(set) var art: Art!
    private(set) var windows: [AgentWindow] = [] // array order is stack order, from the corner inward
    private var homes: [ObjectIdentifier: CGDirectDisplayID] = [:]
    private(set) var active: AgentWindow?
    private var axes: [StackKey: Axis] = [:]
    private var dragging: AgentWindow?
    private let chat = ChatPanel()
    private var statusItem: NSStatusItem!
    private var ticker: Timer?
    private var demo: DemoDriver?
    private var menu: NSMenu!
    private var fixedScale = DockPrefs.fixedScale
    private var closeUndo = CloseUndo()
    private var closeExpiry: DispatchWorkItem?
    private var keyMonitor: Any?

    /// Docked windows stay out of this rectangle (global screen coordinates). It is set to the chat
    /// panel's frame while a conversation is open; the panel may update it if it moves or resizes.
    var reservedBottomRect: NSRect? {
        didSet { if reservedBottomRect != oldValue { layout(animated: true) } }
    }

    /// Every optional capability plugs in here; each lives in its own file under Features/.
    private let features: [Feature] = [
        Persistence(), Hotkeys(), QuietMode(), SettingsFeature(), Voice(), Capture(), Handoff(),
        FocusOverlay(), Hotspots(),
    ]

    /// Quiet mode: windows keep their state dot and badge but stop showing speech bubbles.
    var isQuiet = false {
        didSet {
            windows.forEach { $0.refresh() }
            if isQuiet != oldValue { NotificationCenter.default.post(name: .nookQuietChanged, object: self) }
        }
    }

    // MARK: launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            art = try Art()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        PixelFont.register(art.url("fonts/DepartureMono-Regular.otf"))
        chat.controller = self
        buildMenus()

        let args = Array(CommandLine.arguments.dropFirst())
        // --say=<text> sends an opening message to every real agent (engine smoke test).
        let opening = args.first { $0.hasPrefix("--say=") }.map { String($0.dropFirst(6)) }
        for path in args where !path.hasPrefix("--") {
            let window = addAgent(folder: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            if let opening { window.session.send(opening) }
        }
        if args.contains("--demo") { startDemo() }
        features.forEach { $0.install(in: self) }

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.session.tick(0.5) }
        }
        ticker?.tolerance = 0.25 // state decay is not time critical; let the system batch the wake-ups
        // ⌘W closes the active agent, but only while the chat panel has the keyboard. A menu key
        // equivalent would fight the settings window's own ⌘W, so this looks at key presses instead.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.chat.isKeyWindow, let active = self.active,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command],
                  event.charactersIgnoringModifiers?.lowercased() == "w" else { return event }
            self.requestClose(active)
            return nil
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        windows.forEach { $0.session.stop() }
    }

    private func buildMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack.person.crop", accessibilityDescription: "Nook")
        menu = NSMenu()
        menu.addItem(withTitle: "New Agent…", action: #selector(newAgent), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Add Demo Agents", action: #selector(startDemo), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Close All Agents…", action: #selector(closeAllAgents), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // An accessory app has no menu bar, but text fields need an Edit menu for ⌘C/⌘V.
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// A clickable object inside a scene (a notice board, a wall calendar) was clicked.
    /// Features listen for `.nookHotspot`; userInfo carries "id" (String) and "window" (AgentWindow).
    func hotspotClicked(_ id: String, in window: AgentWindow) {
        NotificationCenter.default.post(name: .nookHotspot, object: self, userInfo: ["id": id, "window": window])
    }

    /// Features add their commands to the menu bar menu, above Quit.
    func addMenuItem(_ item: NSMenuItem) {
        menu.insertItem(item, at: max(menu.numberOfItems - 2, 0))
    }

    // MARK: agents

    @objc private func newAgent() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Start Agent"
        panel.message = "Choose the project folder this agent works in."
        if panel.runModal() == .OK, let url = panel.url {
            addAgent(folder: url)
        }
    }

    /// `resume` continues an earlier Claude Code session; `corner`, `minimised` and `scene` restore a
    /// saved layout. Without a `scene` the new-agent preference picks one (rotating by default).
    @discardableResult
    func addAgent(folder: URL?, label: String? = nil, resume: String? = nil,
                  corner: Corner = DockPrefs.defaultCorner, minimised: Bool = false, scene: String? = nil) -> AgentWindow {
        let session = AgentSession(label: label ?? folder?.lastPathComponent ?? "agent", cwd: folder, resume: resume)
        let window = AgentWindow(session: session, art: art, roomIndex: windows.count)
        window.controller = self
        window.corner = corner
        window.minimised = minimised
        let choices = art.sceneChoices.map(\.id)
        let wanted = scene.flatMap { choices.contains($0) ? $0 : nil } // a saved scene the theme no longer has
            ?? ScenePrefs.scene(forNew: windows.count, choices: choices, preference: UserDefaults.standard.string(forKey: ScenePrefs.newAgentKey))
        if let wanted { window.setScene(wanted) }
        session.onChange = { [weak self, weak window] in
            guard let self, let window else { return }
            self.changed(window)
        }
        windows.append(window)
        // New agents appear on the screen you are working on, and then stay there.
        homes[ObjectIdentifier(window)] = (NSScreen.main ?? NSScreen.screens[0]).displayID
        if active != nil { window.room.setDimmed(true) }
        layout(animated: false, only: window)
        window.orderFrontRegardless()
        layout(animated: true)
        window.refresh()
        session.start()
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
        return window
    }

    /// Closes at once and offers undo. The user-facing paths go through `requestClose`, which asks first when it matters.
    func close(_ window: AgentWindow) { close([window]) }

    /// Closing an agent that is mid-turn or waiting for a permission asks first; an idle one just goes.
    func requestClose(_ window: AgentWindow) {
        let session = window.session
        guard CloseUndo.needsConfirmation(state: session.state, hasPending: session.pending != nil,
                                          turnInProgress: session.turnStarted != nil) else { return close(window) }
        let detail = session.pending != nil ? "It is waiting for a permission." : "It is in the middle of a turn."
        ClosePrompt.shared.ask("Close \(session.label)?", detail: detail, confirmTitle: "Close Agent", near: window.frame) { [weak self, weak window] in
            guard let self, let window, self.windows.contains(where: { $0 === window }) else { return }
            self.close(window)
        }
    }

    @objc private func closeAllAgents() {
        guard !windows.isEmpty else { return }
        let busy = windows.filter { $0.session.state.busy || $0.session.pending != nil }.count
        let detail = busy == 0 ? "" : busy == 1 ? "One is still working." : "\(busy) are still working."
        let title = windows.count == 1 ? "Close the agent?" : "Close all \(windows.count) agents?"
        ClosePrompt.shared.ask(title, detail: detail, confirmTitle: "Close All", near: nil) { [weak self] in
            guard let self else { return }
            self.close(self.windows)
        }
    }

    private func close(_ closing: [AgentWindow]) {
        guard !closing.isEmpty else { return }
        let records = closing.map { Persistence.saved($0, order: windows.firstIndex(of: $0) ?? windows.count, in: self) }
        if let active, closing.contains(active) { deactivate() }
        for window in closing {
            window.session.onChange = nil
            window.session.stop()
            homes[ObjectIdentifier(window)] = nil
            window.orderOut(nil)
        }
        windows.removeAll { closing.contains($0) }
        layout(animated: true)

        // The agents stay in the saved state until the undo offer runs out (see CloseUndo).
        closeUndo.closed(records, at: Date())
        closeExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.closeUndo.expire() else { return }
            NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
        }
        closeExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + CloseUndo.window, execute: expiry)
        let title = closing.count == 1 ? "Closed \(closing[0].session.label)" : "Closed \(closing.count) agents"
        ClosePrompt.shared.offer(title, button: "Undo", for: CloseUndo.window, near: closing.count == 1 ? closing[0].frame : nil) { [weak self] in
            self?.undoClose()
        }
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
    }

    /// Closed agents that can still come back; Persistence keeps saving them until they cannot.
    var recentlyClosed: [Persistence.SavedAgent] { closeUndo.held }

    /// Reopens what was just closed, where it was, resuming the same Claude sessions.
    private func undoClose() {
        closeExpiry?.cancel()
        closeExpiry = nil
        for agent in closeUndo.undo(at: Date()) {
            let window = addAgent(folder: agent.folder.isEmpty ? nil : URL(fileURLWithPath: agent.folder), label: agent.label,
                                  resume: agent.sessionID, corner: Corner(rawValue: agent.corner) ?? .bottomRight,
                                  minimised: agent.minimised, scene: agent.scene)
            if let display = agent.display, display != 0 { homes[ObjectIdentifier(window)] = display }
            windows.removeLast()
            windows.insert(window, at: min(agent.order, windows.count))
        }
        layout(animated: true)
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
    }

    func setScene(_ id: String, for window: AgentWindow) {
        window.setScene(id)
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self) // saved with the layout
    }

    private func changed(_ window: AgentWindow) {
        if active === window {
            window.session.unread = 0
            chat.render(window.session)
        }
        window.refresh()
        NotificationCenter.default.post(name: .nookSessionChanged, object: window)
    }

    // MARK: conversation

    func activate(_ window: AgentWindow) {
        active = window
        window.session.unread = 0
        for w in windows {
            w.room.setDimmed(w !== window)
            w.room.setActive(w === window)
        }
        window.refresh()
        chat.present(window.session, on: screen(of: window))
        reservedBottomRect = chat.frame
        NotificationCenter.default.post(name: .nookActiveChanged, object: self)
    }

    func deactivate() {
        active = nil
        for w in windows {
            w.room.setDimmed(false)
            w.room.setActive(false)
        }
        chat.orderOut(nil)
        reservedBottomRect = nil
        NotificationCenter.default.post(name: .nookActiveChanged, object: self)
    }

    func send(_ text: String, attachments: [URL] = []) { active?.session.send(text, attachments: attachments) }
    func answerActive(allow: Bool) { active?.session.answerPermission(allow: allow) }
    func answer(_ window: AgentWindow, allow: Bool) { window.session.answerPermission(allow: allow) }

    func toggleMinimise(_ window: AgentWindow) {
        window.minimised.toggle()
        layout(animated: true)
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self) // saved with the layout
    }

    // MARK: docking
    //
    // Every screen corner holds one stack. A stack runs either up/down the side (a column) or
    // along the top/bottom edge (a row). Dragging moves a window between corners, reorders it
    // within a stack, and flips the stack between column and row.

    func willDrag(_ window: AgentWindow) {
        dragging = window
        window.orderFrontRegardless()
        layout(animated: true) // nothing moves yet, but the chambers it leaves seal their connectors
    }

    /// Called continuously during a drag: the other windows make room where this one would land.
    func dragged(_ window: AgentWindow) {
        if place(window) { layout(animated: true) }
    }

    func dropped(_ window: AgentWindow) {
        place(window)
        dragging = nil
        layout(animated: true)
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
    }

    /// Works out where the dragged window belongs. Returns true if that changed the arrangement.
    @discardableResult
    private func place(_ window: AgentWindow) -> Bool {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? self.screen(of: window)
        let area = screen.visibleFrame
        let centre = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let right = centre.x > area.midX
        let bottom = centre.y < area.midY
        let corner: Corner = bottom ? (right ? .bottomRight : .bottomLeft) : (right ? .topRight : .topLeft)
        let key = StackKey(display: screen.displayID, corner: corner)
        let neighbours = windows.filter { $0 !== window && $0.corner == corner && homes[ObjectIdentifier($0)] == key.display }

        // Level with the corner window and off to its side: make a row. Above or below it: a column.
        var axis = axes[key] ?? .vertical
        if !neighbours.isEmpty {
            let size = NSSize(width: RoomScene.W * 2, height: RoomScene.H * 2)
            let margin = DockLayout().margin
            let cx = right ? area.maxX - margin - size.width / 2 : area.minX + margin + size.width / 2
            let cy = bottom ? area.minY + margin + size.height / 2 : area.maxY - margin - size.height / 2
            let dx = abs(centre.x - cx) / size.width
            let dy = abs(centre.y - cy) / size.height
            if dy < 0.6, dx > 0.5 { axis = .horizontal } else if dx < 0.6, dy > 0.5 { axis = .vertical }
        }

        // Lay the screen out as if the window had already landed at the end of that stack; the slot
        // nearest to it is where it goes. This stays right when the stack is wrapped into lines.
        var stacks = self.stacks(on: key.display, without: window)
        stacks[corner, default: []].append(window)
        var trial = axes
        trial[key] = axis
        let slots = solve(screen, stacks: stacks, axes: trial)[corner]?.frames ?? []
        let index = slots.indices.min { a, b in
            hypot(slots[a].midX - centre.x, slots[a].midY - centre.y) < hypot(slots[b].midX - centre.x, slots[b].midY - centre.y)
        } ?? neighbours.count

        let before = windows.map(ObjectIdentifier.init)
        let unchanged = window.corner == corner && axes[key] == axis && homes[ObjectIdentifier(window)] == key.display
        homes[ObjectIdentifier(window)] = key.display
        window.corner = corner
        axes[key] = axis
        windows.removeAll { $0 === window }
        if index < neighbours.count, let at = windows.firstIndex(where: { $0 === neighbours[index] }) {
            windows.insert(window, at: at)
        } else {
            windows.append(window)
        }
        return !(unchanged && before == windows.map(ObjectIdentifier.init))
    }

    private func screen(of window: AgentWindow) -> NSScreen {
        let home = homes[ObjectIdentifier(window)]
        return NSScreen.screens.first { $0.displayID == home } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screensChanged() { layout(animated: false) }

    @objc private func defaultsChanged() {
        // This fires for every preference in the app; only a new scale needs a fresh layout.
        guard DockPrefs.fixedScale != fixedScale else { return }
        fixedScale = DockPrefs.fixedScale
        layout(animated: true)
    }

    /// Windows whose display was unplugged move to the main screen. Array order is untouched, so
    /// they keep their order and join the end of whatever stack is already in that corner.
    private func adoptOrphans() {
        let present = Set(NSScreen.screens.map(\.displayID))
        let main = (NSScreen.main ?? NSScreen.screens[0]).displayID
        var moved = false
        for w in windows where !present.contains(homes[ObjectIdentifier(w)] ?? 0) {
            let old = StackKey(display: homes[ObjectIdentifier(w)] ?? 0, corner: w.corner)
            let new = StackKey(display: main, corner: w.corner)
            if axes[new] == nil { axes[new] = axes[old] }
            homes[ObjectIdentifier(w)] = main
            moved = true
        }
        if moved { NotificationCenter.default.post(name: .nookAgentsChanged, object: self) }
    }

    private func stacks(on display: CGDirectDisplayID, without skipped: AgentWindow? = nil) -> [Corner: [AgentWindow]] {
        var result: [Corner: [AgentWindow]] = [:]
        for w in windows where w !== skipped && homes[ObjectIdentifier(w)] == display {
            result[w.corner, default: []].append(w)
        }
        return result
    }

    /// The maths lives in DockLayout; this only feeds it one screen's numbers.
    private func solve(_ screen: NSScreen, stacks: [Corner: [AgentWindow]], axes: [StackKey: Axis]) -> [Corner: DockLayout.Placement] {
        var engine = DockLayout(canvas: CGSize(width: RoomScene.W, height: RoomScene.H))
        if let fixedScale {
            // The user's scale holds while wrapping can make it fit; smaller scales are a last resort.
            engine.scales = [fixedScale]
            engine.fallbackScales = [2, 1.5, 1].filter { $0 < fixedScale }
        } else {
            // Art pixels must be whole device pixels: 1.5x is only crisp on a Retina display.
            let backing = screen.backingScaleFactor
            engine.scales = [2, 1.5, 1].filter { ($0 * backing).truncatingRemainder(dividingBy: 1) == 0 }
        }
        engine.orb = RoomScene.orb
        let specs = stacks.map { corner, members in
            DockLayout.Stack(corner: corner, axis: axes[StackKey(display: screen.displayID, corner: corner)] ?? .vertical,
                             minimised: members.map(\.minimised))
        }
        let reserved = reservedBottomRect.flatMap { screen.frame.intersects($0) ? $0 : nil }
        return engine.solve(area: screen.visibleFrame, stacks: specs, reserved: reserved)
    }

    private func layout(animated: Bool, only: AgentWindow? = nil) {
        guard !NSScreen.screens.isEmpty else { return }
        adoptOrphans()
        var chambers: [(window: AgentWindow, frame: CGRect)] = []
        for screen in NSScreen.screens {
            let stacks = self.stacks(on: screen.displayID)
            let solved = solve(screen, stacks: stacks, axes: axes)
            for (corner, members) in stacks {
                guard let placement = solved[corner] else { continue }
                for (w, frame) in zip(members, placement.frames) {
                    // The dragged window follows the mouse and its slot stays open, so it joins nothing.
                    if !w.minimised, w !== dragging { chambers.append((w, frame)) }
                    guard only == nil || only === w, w !== dragging else { continue }
                    w.dock(to: frame, scale: placement.scale, animated: animated)
                }
            }
        }
        guard only == nil else { return }
        // Connectors follow where windows are going, not where the animation has got to, so they
        // open and close during a drag as the stacks make and lose room.
        let joined = Dictionary(uniqueKeysWithValues: zip(chambers.map { ObjectIdentifier($0.window) },
                                                          Connectors.edges(chambers.map(\.frame))))
        for w in windows { w.setNeighbours(joined[ObjectIdentifier(w)] ?? []) }
    }

    // MARK: saved layout (used by Persistence)

    var stackAxes: [StackAxis] {
        get {
            axes.map { StackAxis(display: $0.key.display, corner: $0.key.corner.rawValue, axis: $0.value) }
                .sorted { ($0.display, $0.corner) < ($1.display, $1.corner) }
        }
        set {
            for item in newValue {
                guard let corner = Corner(rawValue: item.corner) else { continue }
                axes[StackKey(display: item.display, corner: corner)] = item.axis
            }
            layout(animated: false)
        }
    }

    func display(of window: AgentWindow) -> UInt32 { homes[ObjectIdentifier(window)] ?? 0 }

    /// Puts a restored window back on its display. An unknown display falls back to the main screen.
    func move(_ window: AgentWindow, toDisplay display: UInt32) {
        homes[ObjectIdentifier(window)] = display
        layout(animated: false)
    }

    // MARK: demo

    @objc private func startDemo() {
        guard demo == nil else { return }
        let names = ["zipdemand", "sternfall", "asche-kron"]
        let sessions = names.map { addAgent(folder: nil, label: $0).session }
        demo = DemoDriver(sessions: sessions)
    }
}

/// Scripted fake agents, so the window experience can be tuned without spending usage.
final class DemoDriver {
    private let sessions: [AgentSession]
    private var timer: Timer?
    private var clock = 0.0
    private var cursor = 0

    private let script: [(Double, Int, AgentState, String, TranscriptEntry.Kind?, Bool)] = [
        (2, 0, .thinking, "", nil, false),
        (4, 0, .working, "Read: src/lookup.ts", .tool, false),
        (6, 1, .thinking, "", nil, false),
        (7, 0, .working, "Edit: src/lookup.ts", .tool, false),
        (9, 1, .working, "Bash: godot --headless --export", .tool, false),
        (11, 0, .talking, "Fixed the zip lookup. All 42 tests pass.", .assistant, true),
        (14, 2, .thinking, "", nil, false),
        (16, 1, .alert, "Allow Bash? rm -rf build/", .system, true),
        (18, 2, .talking, "The configurator pricing table is out of date. Want me to refresh it?", .assistant, true),
        (26, 1, .working, "Bash: godot --headless --export", .tool, false),
        (30, 1, .done, "Export finished.", .assistant, true),
        (34, 0, .done, "Done!", nil, false),
        (50, 0, .idle, "", nil, false),
    ]

    init(sessions: [AgentSession]) {
        self.sessions = sessions
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.step() }
    }

    private func step() {
        clock += 0.5
        while cursor < script.count, script[cursor].0 <= clock {
            let (_, who, state, text, kind, unread) = script[cursor]
            sessions[who].simulate(state, text: text, log: kind, countsAsUnread: unread)
            cursor += 1
        }
        if cursor >= script.count, clock > 60 {
            clock = 0
            cursor = 0
        }
    }
}

extension NSScreen {
    /// Stable for as long as the display stays connected, unlike the NSScreen object itself.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Docking preferences. The settings window writes them; this file only reads.
enum DockPrefs {
    /// "auto", "1x", "1.5x" or "2x" (a bare number works too).
    static let scaleKey = "nook.scale"
    /// "bottomRight", "bottomLeft", "topRight" or "topLeft" (or the Corner raw value).
    static let cornerKey = "nook.defaultCorner"

    /// nil means auto: as large as fits.
    static var fixedScale: CGFloat? {
        let raw = UserDefaults.standard.object(forKey: scaleKey)
        let number = (raw as? NSNumber)?.doubleValue
            ?? (raw as? String).flatMap { Double($0.lowercased().replacingOccurrences(of: "x", with: "")) }
        return number.flatMap { [1, 1.5, 2].contains($0) ? CGFloat($0) : nil }
    }

    static var defaultCorner: Corner {
        let raw = UserDefaults.standard.object(forKey: cornerKey)
        if let number = raw as? NSNumber, let corner = Corner(rawValue: number.intValue) { return corner }
        switch (raw as? String)?.lowercased().filter(\.isLetter) {
        case "bottomleft": return .bottomLeft
        case "topright": return .topRight
        case "topleft": return .topLeft
        default: return .bottomRight
        }
    }
}
