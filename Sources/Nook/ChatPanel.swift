import AppKit

/// Floating input bar at the bottom of the screen with the active agent's log above it.
/// Non-activating but key-capable: typing works without taking focus from the user's editor.
final class ChatPanel: NSPanel {
    weak var controller: AppController?

    static let sizeKey = "nook.chat.size"
    private static let defaultSize = NSSize(width: 680, height: 440)
    private static let minHeight: CGFloat = 220
    private static let bottomMargin: CGFloat = 24

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
    private let permissionRow = NSStackView()
    private let permissionTool = NSTextField(labelWithString: "")
    private let permissionDetail = NSTextField(labelWithString: "")
    private let chipRow = NSStackView()
    private let attachmentRow = NSStackView()
    private let input = InputBox()
    private let stop = NSButton(title: "Stop", target: nil, action: nil)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
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
        contentView = glass

        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.lineBreakMode = .byTruncatingHead
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [heading, detail])
        top.distribution = .fill

        contextBar.heightAnchor.constraint(equalToConstant: 3).isActive = true
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        permissionTool.font = .systemFont(ofSize: 12, weight: .semibold)
        permissionDetail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        permissionDetail.textColor = .secondaryLabelColor
        permissionDetail.lineBreakMode = .byTruncatingMiddle
        permissionDetail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permissionDetail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let deny = NSButton(title: "Deny", target: self, action: #selector(denyTapped))
        deny.toolTip = "Deny (⌘⌫)"
        let allow = NSButton(title: "Allow", target: self, action: #selector(allowTapped))
        allow.toolTip = "Allow (⌘↩)"
        allow.bezelColor = .controlAccentColor
        permissionRow.setViews([permissionTool, permissionDetail, deny, allow], in: .leading)
        permissionRow.distribution = .fill
        permissionRow.isHidden = true

        for row in [chipRow, attachmentRow] {
            row.spacing = 6
            row.distribution = .gravityAreas
            row.setClippingResistancePriority(.defaultLow, for: .horizontal)
            row.isHidden = true
        }

        input.onSubmit = { [weak self] in self?.submit() }
        input.onClose = { [weak self] in self?.controller?.deactivate() }
        input.onRecall = { [weak self] in self?.session?.transcript.last { $0.kind == .user }?.text }
        input.textView.onFiles = { [weak self] in self?.attach($0) }
        stop.target = self
        stop.action = #selector(stopTapped)
        stop.controlSize = .small
        stop.bezelStyle = .rounded
        stop.toolTip = "Stop (⌘.)"
        stop.isHidden = true
        stop.setContentHuggingPriority(.required, for: .horizontal)
        let inputRow = NSStackView(views: [input, stop])
        inputRow.alignment = .centerY
        inputRow.distribution = .fill

        let rows: [NSView] = [top, contextBar, summary, log, permissionRow, chipRow, attachmentRow, inputRow]
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.setCustomSpacing(5, after: top)
        column.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        column.translatesAutoresizingMaskIntoConstraints = false
        log.setContentHuggingPriority(.init(1), for: .vertical)
        log.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let grip = ResizeGrip()
        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.onDrag = { [weak self] in self?.resize(toTop: $0) }
        glass.addSubview(column)
        glass.addSubview(grip)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            column.topAnchor.constraint(equalTo: glass.topAnchor),
            column.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            grip.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            grip.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            grip.topAnchor.constraint(equalTo: glass.topAnchor),
            grip.heightAnchor.constraint(equalToConstant: 7),
        ])
        for view in rows {
            view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -28).isActive = true
        }
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
        syncTimer()
    }

    /// The controller hides the panel with `orderOut`; fade and sink first.
    override func orderOut(_ sender: Any?) {
        guard isVisible else { return super.orderOut(sender) }
        transition += 1
        let token = transition
        if let session { drafts[session.id] = input.text }
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
        guard let stored = UserDefaults.standard.string(forKey: Self.sizeKey) else { return Self.defaultSize }
        let size = NSSizeFromString(stored)
        return size.width >= 320 && size.height >= Self.minHeight ? size : Self.defaultSize
    }

    /// Bottom-centred on the screen's visible area, clamped to fit it.
    private func placement(on screen: NSScreen, height: CGFloat) -> NSRect {
        let area = screen.visibleFrame
        let width = min(savedSize.width, area.width - 32)
        let clamped = min(max(height, Self.minHeight), area.height - Self.bottomMargin * 2)
        return NSRect(x: (area.midX - width / 2).rounded(), y: area.minY + Self.bottomMargin, width: width, height: clamped.rounded())
    }

    private func resize(toTop y: CGFloat?) {
        guard let screen = screen ?? NSScreen.main else { return }
        guard let y else {
            UserDefaults.standard.set(NSStringFromSize(NSSize(width: savedSize.width, height: frame.height)), forKey: Self.sizeKey)
            return
        }
        setFrame(placement(on: screen, height: y - (screen.visibleFrame.minY + Self.bottomMargin)), display: true)
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
        stop.isHidden = !session.state.busy

        log.show(session)
        showChips(ReplyChips.titles(for: ReplyChips.situation(busy: session.state.busy, transcript: session.transcript)))
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
        let chips = titles.map { title in PillButton(title: title) { [weak self] in self?.controller?.send(title) } }
        chipRow.setViews(chips, in: .leading)
        chipRow.isHidden = titles.isEmpty
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
        if text.isEmpty { text = "Please look at " + attachments.map(\.lastPathComponent).joined(separator: ", ") + "." }
        let files = attachments
        input.text = ""
        attachments = []
        showAttachments()
        log.scrollToBottom()
        controller?.send(text, attachments: files)
    }

    @objc private func stopTapped() {
        if session?.state.busy == true { session?.interrupt() }
    }

    @objc private func allowTapped() { controller?.answerActive(allow: true) }
    @objc private func denyTapped() { controller?.answerActive(allow: false) }
}

/// Files dropped on an agent window or grabbed from the screen wait here as chips until sent.
extension ChatPanel: AttachmentStaging {
    func stage(_ urls: [URL]) { attach(urls) }
}
