import AppKit

/// Pass one agent's result to another, or broadcast one prompt to several.
final class Handoff: Feature {
    /// Agent windows reach the feature through here: Option-drag and the context menu.
    private(set) static weak var shared: Handoff?

    static let broadcastHotkeyPreference = "nook.hotkey.broadcast"

    private weak var app: AppController?
    private var chip: GhostChip?
    private weak var hovered: AgentWindow?
    private var prompt: LinePrompt?
    private var broadcast: BroadcastPanel?

    func install(in app: AppController) {
        self.app = app
        Self.shared = self
        let key = HotkeySpec.preference(Self.broadcastHotkeyPreference, default: "ctrl+opt+b")
        let item = ClosureItem("Broadcast…") { [weak self] in self?.showBroadcast() }
        key.decorate(item)
        app.addMenuItem(item)
        GlobalHotkeys.shared.register("broadcast", key) { [weak self] in self?.showBroadcast() }
    }

    // MARK: option-drag

    func dragBegan(from source: AgentWindow) {
        chip = GhostChip(text: "Hand off \(source.session.label)")
        chip?.follow(NSEvent.mouseLocation)
        chip?.orderFrontRegardless()
    }

    func dragMoved(from source: AgentWindow) {
        let mouse = NSEvent.mouseLocation
        chip?.follow(mouse)
        let target = app?.windows.first { $0 !== source && $0.frame.contains(mouse) }
        guard target !== hovered else { return }
        hovered?.setDropHighlight(false)
        hovered = target
        target?.setDropHighlight(true)
        chip?.show(target.map { "\(source.session.label) → \($0.session.label)" } ?? "Hand off \(source.session.label)")
    }

    func dragEnded(from source: AgentWindow) {
        chip?.orderOut(nil)
        chip = nil
        let target = hovered
        hovered = nil
        guard let target else { return }
        ask(from: source, to: target)
    }

    // MARK: prompt and send

    /// Asks for one line beside the target, then sends. The target stays highlighted while asked.
    func ask(from source: AgentWindow, to target: AgentWindow) {
        prompt?.onCancel?()
        target.setDropHighlight(true)
        prompt = LinePrompt(title: "\(source.session.label) → \(target.session.label)",
                            placeholder: "What should it do with this? (Return to send)",
                            beside: target) { [weak self, weak source, weak target] line in
            self?.prompt = nil
            target?.setDropHighlight(false)
            guard let line, let source, let target, self?.app?.windows.contains(where: { $0 === target }) == true else { return }
            target.session.send(Self.message(from: source.session, instruction: line).text)
        }
    }

    static func message(from session: AgentSession, instruction: String) -> HandoffMessage {
        HandoffMessage(sourceLabel: session.label, sourceFolder: session.cwd?.path, summary: session.summary,
                       lastReply: session.transcript.last { $0.kind == .assistant }?.text, instruction: instruction)
    }

    // MARK: broadcast

    private func showBroadcast() {
        guard let app, !app.windows.isEmpty else { return NSSound.beep() }
        broadcast?.orderOut(nil)
        let panel = BroadcastPanel(agents: app.windows) { [weak self] text, chosen in
            self?.broadcast = nil
            // Straight to each session: nobody is activated, the windows just start thinking.
            for window in chosen where self?.app?.windows.contains(where: { $0 === window }) == true {
                window.session.send(text)
            }
        }
        panel.onCancel = { [weak self, weak panel] in
            panel?.orderOut(nil)
            self?.broadcast = nil
        }
        broadcast = panel
    }
}

/// A prompt plus a tick box per agent, all ticked.
private final class BroadcastPanel: MiniPanel {
    private let field = NSTextField()
    private var boxes: [(NSButton, AgentWindow)] = []
    private let send: (String, [AgentWindow]) -> Void

    init(agents: [AgentWindow], send: @escaping (String, [AgentWindow]) -> Void) {
        self.send = send
        let size = TextSize.current
        let rows = CGFloat(agents.count)
        super.init(size: NSSize(width: size.metric(520), height: size.metric(136 + rows * 27)))

        let title = NSTextField(labelWithString: "Broadcast to agents")
        title.font = TextSize.font(.title, weight: .semibold)
        field.placeholderString = "Same message to every ticked agent…"
        field.font = TextSize.font(.body)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.target = self
        field.action = #selector(submit)

        let ticks = NSStackView()
        ticks.orientation = .vertical
        ticks.alignment = .leading
        ticks.spacing = size.metric(5)
        for agent in agents {
            let box = NSButton(checkboxWithTitle: agent.session.label, target: nil, action: nil)
            box.font = TextSize.font(.label)
            box.state = .on
            boxes.append((box, agent))
            ticks.addArrangedSubview(box)
        }

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        let go = NSButton(title: "Send", target: self, action: #selector(submit))
        go.bezelColor = .controlAccentColor
        let buttons = NSStackView(views: [NSView(), cancel, go])

        let column = NSStackView(views: [title, field, ticks, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = size.metric(10)
        let side = size.metric(16)
        column.edgeInsets = NSEdgeInsets(top: size.metric(14), left: side, bottom: size.metric(14), right: side)
        column.frame = glass.bounds
        column.autoresizingMask = [.width, .height]
        glass.addSubview(column)
        for view in [field, buttons] as [NSView] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -side * 2).isActive = true
        }

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    @objc private func cancelTapped() { onCancel?() }

    @objc private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = boxes.filter { $0.0.state == .on }.map(\.1)
        guard !text.isEmpty, !chosen.isEmpty else { return NSSound.beep() }
        orderOut(nil)
        send(text, chosen)
    }
}
