import AppKit

/// Proof that a line of text was typed by the user into the chat input. Its initialiser is
/// private to this file — the input box's own submit path — so nothing else in the app can make
/// one: not the agent's replies, a queued task, a scheduled prompt, a voice transcript or a
/// notification reply. `ShellConsole.handle` takes only this, which is how "only what the user
/// typed can start a shell command" is enforced by the compiler rather than by convention.
struct TypedLine {
    let text: String
    fileprivate init(_ text: String) { self.text = text }
}

/// Floating input bar at the bottom of the screen with the active agent's log above it.
/// Non-activating but key-capable: typing works without taking focus from the user's editor.
final class ChatPanel: NSPanel {
    weak var controller: AppController?

    /// The panel's size at the `medium` text size; what is shown is this times the setting. (The
    /// older "nook.chat.size" held unscaled points for a smaller default and is no longer read.)
    static let sizeKey = "nook.chat.baseSize"
    /// The conversation takes over most of the screen; the input bar floats under the log.
    private static let screenShare: CGFloat = 0.9
    private static let inputWidthShare: CGFloat = 0.6
    private static let inputGap: CGFloat = 14

    private weak var session: AgentSession?
    private var drafts: [UUID: String] = [:]
    private var attachments: [URL] = []
    private var chipTitles: [String] = []
    private var elapsedTimer: Timer?
    private var transition = 0 // bumps on every show/hide so a stale fade-out cannot hide a fresh panel

    private let heading = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let contextBar = ContextBar()
    private let summary = NSTextField(labelWithString: "")
    private let log = LogView()
    private let activity = ActivityLine()
    private let queueRow = NSStackView()
    private let permissionRow = NSStackView()
    private let permissionTool = NSTextField(labelWithString: "")
    private let permissionDetail = NSTextField(labelWithString: "")
    private let chipRow = NSStackView()
    private let attachmentRow = NSStackView()
    private let input = InputBox()
    private let stop = NSButton(title: "Stop", target: nil, action: nil)
    private let deny = NSButton(title: "Deny", target: nil, action: nil)
    private let allow = NSButton(title: "Allow", target: nil, action: nil)
    private let column = NSStackView()
    private var top = NSStackView()
    private var barHeight: NSLayoutConstraint!
    private var rowWidths: [NSLayoutConstraint] = []

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: ChatMetrics.panelSize(saved: nil, textSize: .current)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NookLevel.chat
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none

        let glass = DropGlass()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.masksToBounds = true
        glass.onFiles = { [weak self] in self?.attach($0) }

        // The log is one large card; the input floats beneath it as its own bar. The panel itself
        // is clear, so a click in the gap between them falls through to the focus overlay.
        let inputGlass = DropGlass()
        inputGlass.material = .hudWindow
        inputGlass.blendingMode = .behindWindow
        inputGlass.state = .active
        inputGlass.wantsLayer = true
        inputGlass.layer?.cornerRadius = 18
        inputGlass.layer?.masksToBounds = true
        inputGlass.onFiles = { [weak self] in self?.attach($0) }
        let container = NSView()
        contentView = container

        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.lineBreakMode = .byTruncatingHead
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        top = NSStackView(views: [heading, detail])
        top.distribution = .fill

        barHeight = contextBar.heightAnchor.constraint(equalToConstant: 3)
        barHeight.isActive = true
        summary.textColor = .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        permissionDetail.textColor = .secondaryLabelColor
        permissionDetail.lineBreakMode = .byTruncatingMiddle
        permissionDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permissionDetail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        (deny.target, deny.action) = (self, #selector(denyTapped))
        deny.toolTip = "Deny (⌘⌫)"
        (allow.target, allow.action) = (self, #selector(allowTapped))
        for button in [deny, allow] { button.bezelStyle = .rounded }
        allow.toolTip = "Allow (⌘↩)"
        allow.bezelColor = .controlAccentColor
        permissionRow.setViews([permissionTool, permissionDetail, deny, allow], in: .leading)
        permissionRow.distribution = .fill
        permissionRow.isHidden = true

        for row in [chipRow, attachmentRow, queueRow] {
            row.distribution = .gravityAreas
            row.setClippingResistancePriority(.defaultLow, for: .horizontal)
            row.isHidden = true
        }

        input.onSubmit = { [weak self] in self?.submit() }
        input.onClose = { [weak self] in self?.controller?.deactivate() }
        input.onRecall = { [weak self] in
            guard let session = self?.session else { return nil }
            return ShellRecall.last(transcript: session.transcript,
                                    history: session.cwd.map { ShellHistory.commands(for: $0) } ?? [])
        }
        log.onShell = { [weak self] in self?.perform($0) }
        input.textView.onFiles = { [weak self] in self?.attach($0) }
        stop.target = self
        stop.action = #selector(stopTapped)
        stop.bezelStyle = .rounded
        stop.toolTip = "Stop (⌘.)"
        stop.isHidden = true
        stop.setContentHuggingPriority(.required, for: .horizontal)
        let inputRow = NSStackView(views: [input, stop])
        inputRow.alignment = .centerY
        inputRow.distribution = .fill

        let rows: [NSView] = [top, contextBar, summary, log, activity, queueRow, permissionRow, chipRow, attachmentRow]
        column.setViews(rows, in: .top)
        column.orientation = .vertical
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        log.setContentHuggingPriority(.init(1), for: .vertical)
        log.setContentCompressionResistancePriority(.init(1), for: .vertical)

        for view in [glass, inputGlass, inputRow] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false }
        container.addSubview(glass)
        container.addSubview(inputGlass)
        glass.addSubview(column)
        inputGlass.addSubview(inputRow)
        let inputWidth = inputGlass.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: Self.inputWidthShare)
        inputWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glass.topAnchor.constraint(equalTo: container.topAnchor),
            glass.bottomAnchor.constraint(equalTo: inputGlass.topAnchor, constant: -Self.inputGap),
            inputGlass.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            inputGlass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inputWidth,
            inputGlass.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
            inputGlass.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            inputRow.leadingAnchor.constraint(equalTo: inputGlass.leadingAnchor, constant: 14),
            inputRow.trailingAnchor.constraint(equalTo: inputGlass.trailingAnchor, constant: -14),
            inputRow.topAnchor.constraint(equalTo: inputGlass.topAnchor, constant: 10),
            inputRow.bottomAnchor.constraint(equalTo: inputGlass.bottomAnchor, constant: -10),
            column.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            column.topAnchor.constraint(equalTo: glass.topAnchor),
            column.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        rowWidths = rows.map { $0.widthAnchor.constraint(equalTo: column.widthAnchor) }
        NSLayoutConstraint.activate(rowWidths)
        applyTextSize()
        NotificationCenter.default.addObserver(self, selector: #selector(textSizeChanged), name: TextSize.changed, object: nil)
    }

    // MARK: text size

    /// Every font and the spacing that depends on it. Called once at launch and whenever the setting changes.
    private func applyTextSize() {
        let size = TextSize.current
        heading.font = TextSize.font(.title, weight: .semibold)
        detail.font = TextSize.digits(.secondary)
        summary.font = TextSize.font(.secondary)
        permissionTool.font = TextSize.font(.label, weight: .semibold)
        permissionDetail.font = TextSize.mono(.secondary)
        let control: NSControl.ControlSize = size.rawValue > 1 ? .large : .regular
        for button in [deny, allow, stop] {
            button.controlSize = control
            button.font = .systemFont(ofSize: max(size.points(.secondary), NSFont.systemFontSize(for: control)))
        }
        let side = size.metric(16)
        column.spacing = size.metric(10)
        column.setCustomSpacing(size.metric(6), after: top)
        column.edgeInsets = NSEdgeInsets(top: size.metric(14), left: side, bottom: size.metric(16), right: side)
        rowWidths.forEach { $0.constant = -side * 2 }
        barHeight.constant = size.metric(4)
        permissionRow.spacing = size.metric(8)
        chipRow.spacing = size.metric(7)
        attachmentRow.spacing = size.metric(7)
        queueRow.spacing = size.metric(7)
        column.setCustomSpacing(size.metric(4), after: log)
        activity.applyTextSize()
        input.applyTextSize()
    }

    /// Live: restyle, redraw the log and the chips at the new size, and resize the panel in place.
    @objc private func textSizeChanged() {
        applyTextSize()
        log.reset()
        chipTitles = []
        showAttachments()
        if let session { render(session) }
        guard isVisible, let screen = screen ?? NSScreen.main else { return }
        setFrame(placement(on: screen, height: savedSize.height), display: true)
        log.scrollToBottom()
    }

    override var canBecomeKey: Bool { true }

    /// Esc with focus outside the input (the log, say) closes the conversation.
    override func cancelOperation(_ sender: Any?) { controller?.deactivate() }

    /// Shortcuts the panel owns. The accessory app's Edit menu has no Undo, so that lives here too.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key) {
        case ([.command], "."):
            // Swallowed even when idle: a late ⌘. should not fall through to Esc and close the panel.
            stopTapped()
            return true
        case ([.command], "\r"), ([.command], "\u{3}"):
            guard session?.pending != nil else { break }
            allowTapped()
            return true
        case ([.command], "\u{7F}"), ([.command], "\u{8}"):
            guard session?.pending != nil else { break }
            denyTapped()
            return true
        case ([.command], "="), ([.command, .shift], "+"), ([.command, .shift], "="), ([.command], "+"):
            if !TextSize.step(1) { NSSound.beep() }
            return true
        case ([.command], "-"):
            if !TextSize.step(-1) { NSSound.beep() }
            return true
        case ([.command], "0"):
            TextSize.current = .medium
            return true
        case ([.command], "v"):
            // Here rather than via the Edit menu, which a non-activating panel can't rely on, and
            // always into the input: a screenshot pasted while the log has focus is still attached.
            if firstResponder !== input.textView { makeFirstResponder(input.textView) }
            input.textView.paste(nil)
            return true
        case ([.command], "z"):
            if let undo = (firstResponder as? NSTextView)?.undoManager, undo.canUndo { undo.undo() }
            return true
        case ([.command, .shift], "z"):
            if let undo = (firstResponder as? NSTextView)?.undoManager, undo.canRedo { undo.redo() }
            return true
        default:
            break
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: showing and hiding

    func present(_ session: AgentSession, on screen: NSScreen) {
        transition += 1
        if !UserDefaults.standard.bool(forKey: ShellPrefs.hintShown) {
            UserDefaults.standard.set(true, forKey: ShellPrefs.hintShown)
            session.remark("Start a line with ! to run a shell command here — Nook runs it, the agent never sees it.")
        }
        let target = placement(on: screen, height: savedSize.height)
        render(session)
        if isVisible, alphaValue == 1 {
            setFrame(target, display: true)
        } else {
            let rise: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 8
            if !isVisible { alphaValue = 0 }
            setFrame(target.offsetBy(dx: 0, dy: -rise), display: true)
            makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
                if rise > 0 { animator().setFrame(target, display: true) }
            }
        }
        makeKey()
        makeFirstResponder(input.textView)
        log.scrollToBottom()
        activity.show(session)
        syncTimer()
    }

    /// The controller hides the panel with `orderOut`; fade and sink first.
    override func orderOut(_ sender: Any?) {
        guard isVisible else { return super.orderOut(sender) }
        transition += 1
        let token = transition
        if let session { drafts[session.id] = input.text }
        activity.stop()
        syncTimer(hiding: true)
        let sink: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 8
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            if sink > 0 { animator().setFrame(frame.offsetBy(dx: 0, dy: -sink), display: true) }
        }, completionHandler: { [weak self] in
            guard let self, self.transition == token else { return }
            self.finishOrderOut()
        })
    }

    private func finishOrderOut() {
        super.orderOut(nil)
        alphaValue = 1
    }

    // MARK: size and placement

    private var savedSize: NSSize {
        ChatMetrics.panelSize(saved: UserDefaults.standard.string(forKey: Self.sizeKey).map(NSSizeFromString), textSize: .current)
    }

    /// Centred, covering most of the screen's visible area.
    private func placement(on screen: NSScreen, height: CGFloat = 0) -> NSRect {
        let area = screen.visibleFrame
        let size = NSSize(width: (area.width * Self.screenShare).rounded(), height: (area.height * Self.screenShare).rounded())
        return NSRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    // MARK: rendering

    func render(_ session: AgentSession) {
        if self.session !== session {
            if let old = self.session { drafts[old.id] = input.text }
            self.session = session
            input.text = drafts[session.id] ?? ""
            attachments = []
            showAttachments()
        }
        heading.stringValue = session.label
        renderDetail()
        contextBar.fraction = session.contextLimit > 0 ? CGFloat(session.contextTokens) / CGFloat(session.contextLimit) : 0
        contextBar.toolTip = "Context: \(Self.tokens(session.contextTokens)) of \(Self.tokens(session.contextLimit)) tokens"
        summary.stringValue = session.summary
        summary.toolTip = session.summary
        summary.isHidden = session.summary.isEmpty
        input.textView.placeholder = "Message \(session.label)…"

        if let request = session.pending {
            let full = Self.detail(of: request)
            permissionTool.stringValue = "Allow \(request.tool)?"
            permissionDetail.stringValue = full.replacingOccurrences(of: "\n", with: " ⏎ ")
            permissionDetail.toolTip = full
        }
        permissionRow.isHidden = session.pending == nil
        let console = ShellConsole.console(for: session)
        stop.isHidden = !session.state.busy && !console.isRunning
        stop.toolTip = console.isRunning ? "Stop the command (⌘.)" : "Stop (⌘.)"

        log.show(session)
        activity.show(isVisible ? session : nil)
        showQueue(session)
        showChips(session.needsLogin ? [ClaudeAuth.loginTitle]
                  : ReplyChips.titles(for: ReplyChips.situation(busy: session.state.busy, transcript: session.transcript)))
        syncTimer()
    }

    private func renderDetail() {
        guard let session else { return }
        var bits = [session.state.rawValue]
        if !session.model.isEmpty { bits.append(session.model) }
        if session.costUSD > 0 { bits.append(String(format: "$%.2f", session.costUSD)) }
        if let started = session.turnStarted {
            let seconds = max(Int(Date().timeIntervalSince(started)), 0)
            bits.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        detail.stringValue = bits.joined(separator: "  ·  ")
    }

    /// The elapsed-time clock ticks only while the panel is on screen and a turn is running.
    private func syncTimer(hiding: Bool = false) {
        let wanted = !hiding && isVisible && session?.turnStarted != nil
        if wanted, elapsedTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.renderDetail() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            elapsedTimer = timer
        } else if !wanted {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
        }
    }

    /// The whole command or path, not the engine's 80-character brief.
    private static func detail(of request: PermissionRequest) -> String {
        for key in ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt"] {
            if let value = request.input[key] as? String, !value.isEmpty { return value }
        }
        return request.summary
    }

    private static func tokens(_ count: Int) -> String {
        count >= 1000 ? "\(count / 1000)k" : "\(count)"
    }

    // MARK: chips and attachments

    private func showChips(_ titles: [String]) {
        guard titles != chipTitles else { return }
        chipTitles = titles
        let chips = titles.map { title in
            PillButton(title: title) { [weak self] in
                if title == ClaudeAuth.loginTitle { ClaudeAuth.shared?.login() } else { self?.controller?.send(title) }
            }
        }
        chipRow.setViews(chips, in: .leading)
        chipRow.isHidden = titles.isEmpty
    }

    /// Messages held behind a permission question, each with a ✕ that takes it back.
    private func showQueue(_ session: AgentSession) {
        let pills = session.queue.items.map { message -> PillButton in
            let pill = PillButton(title: "queued: " + Activity.shorten(message.text, limit: 38) + "  ✕") { [weak session, weak self] in
                session?.cancelQueued(message.id)
                if let session { self?.render(session) }
            }
            pill.toolTip = "\(message.text)\nWaiting until you answer the permission question. Click to cancel."
            return pill
        }
        queueRow.setViews(pills, in: .leading)
        queueRow.isHidden = pills.isEmpty
    }

    fileprivate func attach(_ urls: [URL]) {
        attachments += urls.filter { !attachments.contains($0) }
        showAttachments()
        makeKey()
        makeFirstResponder(input.textView)
    }

    private func showAttachments() {
        let chips = attachments.map { url -> PillButton in
            let chip = PillButton(title: url.lastPathComponent + "  ✕") { [weak self] in
                self?.attachments.removeAll { $0 == url }
                self?.showAttachments()
            }
            chip.toolTip = "\(url.path)\nClick to remove"
            return chip
        }
        attachmentRow.setViews(chips, in: .leading)
        attachmentRow.isHidden = attachments.isEmpty
    }

    // MARK: actions

    private func submit() {
        var text = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        if let session {
            switch ShellConsole.console(for: session).handle(TypedLine(text)) {
            case .ran, .nothing, .noFolder:
                // Attachments stay staged: they were meant for the agent, not for the shell.
                input.text = ""
                log.scrollToBottom()
                return
            case .busy:
                NSSound.beep() // the command stays in the input, ready to send again
                log.scrollToBottom()
                return
            case let .message(unescaped):
                text = unescaped
            }
        }
        if text.isEmpty { text = "Please look at " + attachments.map(\.lastPathComponent).joined(separator: ", ") + "." }
        let files = attachments
        input.text = ""
        attachments = []
        showAttachments()
        log.scrollToBottom()
        controller?.send(text, attachments: files)
    }

    /// ⌘. and the Stop button mean "stop what is running now": a shell command wins while one is
    /// running, because it is the newer, shorter-lived thing; with none, the agent's turn is interrupted.
    @objc private func stopTapped() {
        if let session, ShellConsole.console(for: session).stop() { return }
        if session?.state.busy == true { session?.interrupt() }
    }

    /// A button inside a shell result block.
    private func perform(_ action: ShellAction) {
        guard let session else { return }
        let console = ShellConsole.console(for: session)
        switch action.kind {
        case .stop: console.stop()
        case .share: console.share(action.run)
        case .expand: action.run.toggleExpanded()
        case .autoShare: console.toggleAutoShare()
        }
        action.run.bump()
        render(session)
    }

    @objc private func allowTapped() { controller?.answerActive(allow: true) }
    @objc private func denyTapped() { controller?.answerActive(allow: false) }
}

/// Files dropped on an agent window or grabbed from the screen wait here as chips until sent.
extension ChatPanel: AttachmentStaging {
    func stage(_ urls: [URL]) { attach(urls) }
}
