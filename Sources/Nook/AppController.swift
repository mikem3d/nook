import AppKit

/// Owns every agent window, the corner stacks they dock into, and the single chat panel.
final class AppController: NSObject, NSApplicationDelegate {
    private struct StackKey: Hashable {
        let screen: ObjectIdentifier
        let corner: Corner
    }

    private enum Axis { case vertical, horizontal }

    private static let margin: CGFloat = 12
    private static let gap: CGFloat = 8
    private static let scales: [CGFloat] = [2, 1.5, 1]

    private var art: Art!
    private(set) var windows: [AgentWindow] = [] // array order is stack order, from the corner inward
    private var homes: [ObjectIdentifier: NSScreen] = [:]
    private(set) var active: AgentWindow?
    private var axes: [StackKey: Axis] = [:]
    private var dragging: AgentWindow?
    private let chat = ChatPanel()
    private var statusItem: NSStatusItem!
    private var ticker: Timer?
    private var demo: DemoDriver?
    private var menu: NSMenu!

    /// Every optional capability plugs in here; each lives in its own file under Features/.
    private let features: [Feature] = [
        Persistence(), Hotkeys(), QuietMode(), SettingsFeature(), Voice(), Capture(), Handoff(),
    ]

    /// Quiet mode: windows keep their state dot and badge but stop showing speech bubbles.
    var isQuiet = false {
        didSet { windows.forEach { $0.refresh() } }
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
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
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

    /// `resume` continues an earlier Claude Code session; `corner` and `minimised` restore a saved layout.
    @discardableResult
    func addAgent(folder: URL?, label: String? = nil, resume: String? = nil,
                  corner: Corner = .bottomRight, minimised: Bool = false) -> AgentWindow {
        let session = AgentSession(label: label ?? folder?.lastPathComponent ?? "agent", cwd: folder, resume: resume)
        let window = AgentWindow(session: session, art: art, roomIndex: windows.count)
        window.controller = self
        window.corner = corner
        window.minimised = minimised
        session.onChange = { [weak self, weak window] in
            guard let self, let window else { return }
            self.changed(window)
        }
        windows.append(window)
        if active != nil { window.room.setDimmed(true) }
        layout(animated: false, only: window)
        window.orderFrontRegardless()
        layout(animated: true)
        window.refresh()
        session.start()
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
        return window
    }

    func close(_ window: AgentWindow) {
        if active === window { deactivate() }
        window.session.onChange = nil
        window.session.stop()
        windows.removeAll { $0 === window }
        homes[ObjectIdentifier(window)] = nil
        window.orderOut(nil)
        layout(animated: true)
        NotificationCenter.default.post(name: .nookAgentsChanged, object: self)
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
        NotificationCenter.default.post(name: .nookActiveChanged, object: self)
    }

    func deactivate() {
        active = nil
        for w in windows {
            w.room.setDimmed(false)
            w.room.setActive(false)
        }
        chat.orderOut(nil)
        NotificationCenter.default.post(name: .nookActiveChanged, object: self)
    }

    func send(_ text: String, attachments: [URL] = []) { active?.session.send(text, attachments: attachments) }
    func answerActive(allow: Bool) { active?.session.answerPermission(allow: allow) }
    func answer(_ window: AgentWindow, allow: Bool) { window.session.answerPermission(allow: allow) }

    func toggleMinimise(_ window: AgentWindow) {
        window.minimised.toggle()
        layout(animated: true)
    }

    // MARK: docking
    //
    // Every screen corner holds one stack. A stack runs either up/down the side (a column) or
    // along the top/bottom edge (a row). Dragging moves a window between corners, reorders it
    // within a stack, and flips the stack between column and row.

    func willDrag(_ window: AgentWindow) {
        dragging = window
        window.orderFrontRegardless()
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
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let centre = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let right = centre.x > area.midX
        let bottom = centre.y < area.midY
        let corner: Corner = bottom ? (right ? .bottomRight : .bottomLeft) : (right ? .topRight : .topLeft)
        let key = StackKey(screen: ObjectIdentifier(screen), corner: corner)
        let neighbours = windows.filter { $0 !== window && $0.corner == corner && self.screen(of: $0) === screen }

        // Level with the corner window and off to its side: make a row. Above or below it: a column.
        var axis = axes[key] ?? .vertical
        if !neighbours.isEmpty {
            let size = NSSize(width: RoomScene.W * 2, height: RoomScene.H * 2)
            let cx = right ? area.maxX - Self.margin - size.width / 2 : area.minX + Self.margin + size.width / 2
            let cy = bottom ? area.minY + Self.margin + size.height / 2 : area.maxY - Self.margin - size.height / 2
            let dx = abs(centre.x - cx) / size.width
            let dy = abs(centre.y - cy) / size.height
            if dy < 0.6, dx > 0.5 { axis = .horizontal } else if dx < 0.6, dy > 0.5 { axis = .vertical }
        }

        let slots = frames(for: neighbours, corner: corner, axis: axis, area: area, shared: false).frames
        let index = slots.filter { slot in
            switch axis {
            case .vertical: return bottom ? slot.midY < centre.y : slot.midY > centre.y
            case .horizontal: return right ? slot.midX > centre.x : slot.midX < centre.x
            }
        }.count

        let before = windows.map(ObjectIdentifier.init)
        let unchanged = window.corner == corner && axes[key] == axis && self.screen(of: window) === screen
        homes[ObjectIdentifier(window)] = screen
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
        if let home = homes[ObjectIdentifier(window)], NSScreen.screens.contains(home) { return home }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screensChanged() { layout(animated: false) }

    /// Slot rectangles for a stack, growing from its corner, at the largest scale that fits.
    private func frames(for stack: [AgentWindow], corner: Corner, axis: Axis, area: NSRect, shared: Bool) -> (scale: CGFloat, frames: [NSRect]) {
        func size(_ w: AgentWindow, _ s: CGFloat) -> NSSize {
            NSSize(width: RoomScene.W * s, height: (w.minimised ? RoomScene.bar : RoomScene.H) * s)
        }
        func extent(_ w: AgentWindow, _ s: CGFloat) -> CGFloat { axis == .vertical ? size(w, s).height : size(w, s).width }

        let room = (axis == .vertical ? area.height : area.width) - Self.margin * 2
        let budget = room * (shared ? 0.5 : 1)
        let scale = Self.scales.first { s in
            stack.reduce(0) { $0 + extent($1, s) } + Self.gap * CGFloat(max(stack.count - 1, 0)) <= budget
        } ?? Self.scales.last!

        var offset = Self.margin
        var result: [NSRect] = []
        for w in stack {
            let sz = size(w, scale)
            let along = offset
            offset += extent(w, scale) + Self.gap
            let x: CGFloat
            let y: CGFloat
            switch axis {
            case .vertical:
                x = corner.isRight ? area.maxX - Self.margin - sz.width : area.minX + Self.margin
                y = corner.isBottom ? area.minY + along : area.maxY - along - sz.height
            case .horizontal:
                x = corner.isRight ? area.maxX - along - sz.width : area.minX + along
                y = corner.isBottom ? area.minY + Self.margin : area.maxY - Self.margin - sz.height
            }
            result.append(NSRect(origin: NSPoint(x: x, y: y), size: sz))
        }
        return (scale, result)
    }

    private func layout(animated: Bool, only: AgentWindow? = nil) {
        var stacks: [StackKey: [AgentWindow]] = [:]
        for w in windows {
            stacks[StackKey(screen: ObjectIdentifier(screen(of: w)), corner: w.corner), default: []].append(w)
        }
        for (key, stack) in stacks {
            guard let first = stack.first else { continue }
            let axis = axes[key] ?? .vertical
            // Two stacks running toward each other along the same edge split the space.
            let facing: Corner
            switch (axis, key.corner) {
            case (.vertical, .bottomRight): facing = .topRight
            case (.vertical, .topRight): facing = .bottomRight
            case (.vertical, .bottomLeft): facing = .topLeft
            case (.vertical, .topLeft): facing = .bottomLeft
            case (.horizontal, .bottomRight): facing = .bottomLeft
            case (.horizontal, .bottomLeft): facing = .bottomRight
            case (.horizontal, .topRight): facing = .topLeft
            case (.horizontal, .topLeft): facing = .topRight
            }
            let facingKey = StackKey(screen: key.screen, corner: facing)
            let shared = stacks[facingKey] != nil && (axes[facingKey] ?? .vertical) == axis

            let (scale, slots) = frames(for: stack, corner: key.corner, axis: axis, area: screen(of: first).visibleFrame, shared: shared)
            for (w, frame) in zip(stack, slots) {
                guard only == nil || only === w else { continue }
                guard w !== dragging else { continue } // it follows the mouse; its slot stays open
                w.room.configure(scale: scale, minimised: w.minimised)
                if animated {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.18
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        w.animator().setFrame(frame, display: true)
                    }
                } else {
                    w.setFrame(frame, display: true)
                }
            }
        }
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
