import AppKit

/// The two small panels around closing an agent: the question before a busy agent is closed, and
/// the offer to undo afterwards. Both sit beside the agent's window, never activate Nook, and run
/// nothing once they are gone.
final class ClosePrompt: NSPanel {
    static let shared = ClosePrompt()

    private let heading = NSTextField(labelWithString: "")
    private let note = NSTextField(labelWithString: "")
    private let confirm = NSButton(title: "", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private var onConfirm: (() -> Void)?
    private var takesKeys = false
    private let text = NSStackView()
    private let row = NSStackView()
    private var widthLimit: NSLayoutConstraint!
    private var hide: DispatchWorkItem?
    /// The chat panel, when ⌘W asked the question: it gets the keyboard back afterwards.
    private weak var previousKey: NSWindow?

    private init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NookLevel.hud
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 10
        glass.layer?.masksToBounds = true

        heading.lineBreakMode = .byTruncatingMiddle
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byTruncatingTail
        for button in [confirm, cancel] {
            button.bezelStyle = .rounded
            button.target = self
        }
        confirm.action = #selector(confirmed)
        cancel.action = #selector(dismiss)
        cancel.keyEquivalent = "\u{1b}"

        text.setViews([heading, note], in: .top)
        text.orientation = .vertical
        text.alignment = .leading
        row.setViews([text, cancel, confirm], in: .leading)
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(row)
        widthLimit = glass.widthAnchor.constraint(lessThanOrEqualToConstant: 580)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            row.topAnchor.constraint(equalTo: glass.topAnchor),
            row.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            widthLimit,
        ])
        contentView = glass
    }

    /// Key only while it asks a question, so Return and Esc reach it; the undo offer never takes the keyboard.
    override var canBecomeKey: Bool { takesKeys }

    /// Asks before closing. Return confirms, Esc or clicking elsewhere cancels.
    func ask(_ title: String, detail: String, confirmTitle: String, near anchor: NSRect?, then action: @escaping () -> Void) {
        if !isKeyWindow { previousKey = NSApp.keyWindow }
        present(title, detail: detail, button: confirmTitle, question: true, near: anchor, action: action)
        makeKeyAndOrderFront(nil)
    }

    /// Offers `action` for `duration` seconds, then fades away.
    func offer(_ title: String, button: String, for duration: TimeInterval, near anchor: NSRect?, then action: @escaping () -> Void) {
        present(title, detail: "", button: button, question: false, near: anchor, action: action)
        orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func present(_ title: String, detail: String, button: String, question: Bool, near anchor: NSRect?, action: @escaping () -> Void) {
        hide?.cancel()
        hide = nil
        applyTextSize()
        heading.stringValue = title
        note.stringValue = detail
        note.isHidden = detail.isEmpty
        confirm.title = button
        confirm.keyEquivalent = question ? "\r" : ""
        cancel.isHidden = !question
        takesKeys = question
        onConfirm = action
        guard let content = contentView else { return }
        content.layoutSubtreeIfNeeded()
        setFrame(Self.frame(size: content.fittingSize, near: anchor), display: true)
        alphaValue = 1
    }

    /// Read each time a prompt shows, so it follows the setting without observing it.
    private func applyTextSize() {
        let size = TextSize.current
        heading.font = TextSize.font(.title, weight: .semibold)
        note.font = TextSize.font(.secondary)
        let control: NSControl.ControlSize = size.rawValue > 1 ? .large : .regular
        for button in [confirm, cancel] {
            button.controlSize = control
            button.font = .systemFont(ofSize: max(size.points(.secondary), NSFont.systemFontSize(for: control)))
        }
        text.spacing = size.metric(3)
        row.spacing = size.metric(12)
        row.edgeInsets = NSEdgeInsets(top: size.metric(12), left: size.metric(16), bottom: size.metric(12), right: size.metric(14))
        widthLimit.constant = size.metric(580)
    }

    /// A question left behind (the user clicked elsewhere) counts as Cancel.
    override func resignKey() {
        super.resignKey()
        if takesKeys { dismiss() }
    }

    @objc private func confirmed() {
        let action = onConfirm
        dismiss()
        action?()
    }

    @objc func dismiss() {
        hide?.cancel()
        hide = nil
        onConfirm = nil
        takesKeys = false
        orderOut(nil)
        if let previousKey, previousKey.isVisible { previousKey.makeKey() }
        previousKey = nil
    }

    private func fadeOut() {
        let current = hide
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A newer prompt may have arrived during the fade; leave that one up.
            if let self, self.hide === current { self.dismiss() }
        })
    }

    /// Just above the anchor (below it when there is no room), or top centre of the main screen without one.
    private static func frame(size: NSSize, near anchor: NSRect?) -> NSRect {
        let gap: CGFloat = 8
        let screens = NSScreen.screens
        guard let anchor, let area = (screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame else {
            let area = NSScreen.main?.visibleFrame ?? .zero
            return NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 40, width: size.width, height: size.height)
        }
        var x = anchor.midX - size.width / 2
        var y = anchor.maxY + gap
        if y + size.height > area.maxY { y = anchor.minY - gap - size.height }
        x = min(max(x, area.minX + gap), area.maxX - size.width - gap)
        y = min(max(y, area.minY + gap), area.maxY - size.height - gap)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
