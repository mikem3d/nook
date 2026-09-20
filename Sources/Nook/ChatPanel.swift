import AppKit

/// Floating input bar at the bottom of the screen with the active agent's log above it.
final class ChatPanel: NSPanel, NSTextFieldDelegate {
    weak var controller: AppController?

    private let heading = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let log = NSTextView()
    private let scroll = NSScrollView()
    private let permissionRow = NSStackView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let input = NSTextField()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.masksToBounds = true
        contentView = glass

        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        let top = NSStackView(views: [heading, detail])
        top.distribution = .fill

        log.isEditable = false
        log.isSelectable = true
        log.drawsBackground = false
        log.textContainerInset = NSSize(width: 4, height: 6)
        log.isVerticallyResizable = true
        log.autoresizingMask = [.width]
        log.textContainer?.widthTracksTextView = true
        scroll.documentView = log
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        permissionLabel.lineBreakMode = .byTruncatingMiddle
        permissionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let deny = NSButton(title: "Deny", target: self, action: #selector(denyTapped))
        let allow = NSButton(title: "Allow", target: self, action: #selector(allowTapped))
        allow.keyEquivalent = "\r"
        allow.keyEquivalentModifierMask = [.command]
        allow.bezelColor = .controlAccentColor
        permissionRow.setViews([permissionLabel, deny, allow], in: .leading)
        permissionRow.isHidden = true

        input.font = .systemFont(ofSize: 15)
        input.isBezeled = true
        input.bezelStyle = .roundedBezel
        input.focusRingType = .none
        input.delegate = self
        input.target = self
        input.action = #selector(submit)

        let column = NSStackView(views: [top, scroll, permissionRow, input])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        column.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            column.topAnchor.constraint(equalTo: glass.topAnchor),
            column.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        for view in [top, scroll, permissionRow, input] as [NSView] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -28).isActive = true
        }
        input.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes the conversation.
    override func cancelOperation(_ sender: Any?) { controller?.deactivate() }

    func present(_ session: AgentSession, on screen: NSScreen) {
        let area = screen.visibleFrame
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.minY + 24))
        render(session)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(input)
    }

    func render(_ session: AgentSession) {
        heading.stringValue = session.label
        var bits = [session.state.rawValue]
        if !session.model.isEmpty { bits.append(session.model) }
        if session.costUSD > 0 { bits.append(String(format: "$%.2f", session.costUSD)) }
        detail.stringValue = bits.joined(separator: "  ·  ")
        input.placeholderString = "Message \(session.label)…   (Esc to close)"

        if let req = session.pending {
            permissionLabel.stringValue = "Allow \(req.tool)?  \(req.summary)"
            permissionRow.isHidden = false
        } else {
            permissionRow.isHidden = true
        }

        let text = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        for entry in session.transcript {
            let attributes: [NSAttributedString.Key: Any]
            let prefix: String
            switch entry.kind {
            case .user:
                prefix = "You  "
                attributes = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.controlAccentColor]
            case .assistant:
                prefix = ""
                attributes = [.font: body, .foregroundColor: NSColor.labelColor]
            case .tool:
                prefix = "⚙ "
                attributes = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
            case .system:
                prefix = "— "
                attributes = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]
            }
            text.append(NSAttributedString(string: prefix + entry.text + "\n\n", attributes: attributes))
        }
        log.textStorage?.setAttributedString(text)
        log.scrollToEndOfDocument(nil)
    }

    @objc private func submit() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input.stringValue = ""
        controller?.send(text)
    }

    @objc private func allowTapped() { controller?.answerActive(allow: true) }
    @objc private func denyTapped() { controller?.answerActive(allow: false) }
}
