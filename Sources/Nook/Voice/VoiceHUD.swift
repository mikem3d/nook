import AppKit

/// The small panel shown while the talk key is held: level meter, who will receive the message,
/// and the words so far. Never takes focus, and ignores the mouse unless it is offering a link.
final class VoiceHUD: NSPanel {
    private static let baseSize = NSSize(width: 540, height: 88)
    private static let meterSize = NSSize(width: 56, height: 34)

    private let meter = LevelMeter(frame: NSRect(origin: .zero, size: VoiceHUD.meterSize))
    private let target = NSTextField(labelWithString: "")
    private let words = NSTextField(labelWithString: "")
    private var link: URL?
    private var hideTimer: Timer?
    private let text = NSStackView()
    private let row = NSStackView()
    private var meterWidth: NSLayoutConstraint!
    private var meterHeight: NSLayoutConstraint!

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.baseSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = NookLevel.hud // above the chat panel, which it may overlap
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = true

        let glass = ClickThroughGlass()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        glass.onClick = { [weak self] in self?.openLink() }
        contentView = glass

        target.textColor = .secondaryLabelColor
        target.lineBreakMode = .byTruncatingTail
        words.maximumNumberOfLines = 2
        words.cell?.truncatesLastVisibleLine = true
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        text.setViews([target, words], in: .top)
        text.orientation = .vertical
        text.alignment = .leading
        row.setViews([meter, text], in: .leading)
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(row)
        meterWidth = meter.widthAnchor.constraint(equalToConstant: Self.meterSize.width)
        meterHeight = meter.heightAnchor.constraint(equalToConstant: Self.meterSize.height)
        NSLayoutConstraint.activate([
            meterWidth, meterHeight,
            row.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            row.topAnchor.constraint(equalTo: glass.topAnchor),
            row.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Live state while the key is held.
    func listen(to destination: String, transcript: String) {
        hideTimer?.invalidate()
        link = nil
        ignoresMouseEvents = true
        meter.isHidden = false
        target.isHidden = false
        words.isHidden = false
        target.stringValue = destination.uppercased()
        words.stringValue = transcript.isEmpty ? "Listening…" : transcript
        words.textColor = transcript.isEmpty ? .tertiaryLabelColor : .labelColor
        words.lineBreakMode = .byTruncatingHead // the newest words matter most
        present()
    }

    func level(_ value: Float) { meter.push(value) }

    /// A result or an explanation; goes away by itself. With `link`, a click opens it.
    func notice(_ title: String, detail: String = "", link: URL? = nil) {
        self.link = link
        ignoresMouseEvents = link == nil
        meter.isHidden = true
        meter.reset()
        target.stringValue = title.uppercased()
        words.stringValue = detail
        words.textColor = .labelColor
        words.lineBreakMode = .byTruncatingTail
        target.isHidden = title.isEmpty
        words.isHidden = detail.isEmpty
        present()
        hideTimer?.invalidate()
        let seconds = link != nil ? 8.0 : (detail.count > 40 ? 4.0 : 1.6)
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        meter.reset()
        orderOut(nil)
    }

    private func openLink() {
        guard let link else { return }
        NSWorkspace.shared.open(link)
        dismiss()
    }

    /// Read each time the panel shows, so it follows the setting without observing it.
    private func applyTextSize() {
        let size = TextSize.current
        target.font = TextSize.mono(.caption, weight: .semibold)
        words.font = TextSize.font(.title, weight: .medium)
        text.spacing = size.metric(3)
        row.spacing = size.metric(14)
        row.edgeInsets = NSEdgeInsets(top: size.metric(12), left: size.metric(16), bottom: size.metric(12), right: size.metric(16))
        meterWidth.constant = size.metric(Self.meterSize.width)
        meterHeight.constant = size.metric(Self.meterSize.height)
        setContentSize(NSSize(width: size.metric(Self.baseSize.width), height: size.metric(Self.baseSize.height)))
    }

    /// Bottom centre of the screen the pointer is on, above the chat panel if that is showing.
    private func present() {
        applyTextSize()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var y = area.minY + 24
        if let chat = NSApp.windows.first(where: { $0 is ChatPanel && $0.isVisible && $0.screen === screen }) {
            y = min(chat.frame.maxY + 8, area.maxY - frame.height - 24)
        }
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: y))
        orderFrontRegardless()
    }
}

private final class ClickThroughGlass: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }
}

/// A scrolling strip of chunky bars, in keeping with the pixel windows. Draws only when a new
/// level arrives, which only happens while the microphone is open.
private final class LevelMeter: NSView {
    private static let bars = 8
    private var history = [Float](repeating: 0, count: LevelMeter.bars)

    func push(_ level: Float) {
        history.removeFirst()
        history.append(level)
        needsDisplay = true
    }

    func reset() {
        history = [Float](repeating: 0, count: Self.bars)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let step = bounds.width / CGFloat(Self.bars)
        let cell: CGFloat = 4 // bar heights snap to whole "pixels"
        for (i, level) in history.enumerated() {
            let cells = max(1, (CGFloat(level) * bounds.height / cell).rounded())
            let height = min(cells * cell, bounds.height)
            let rect = NSRect(x: CGFloat(i) * step, y: ((bounds.height - height) / 2).rounded(),
                              width: step - 2, height: height)
            NSColor.controlAccentColor.withAlphaComponent(level > 0.02 ? 1 : 0.35).setFill()
            rect.fill()
        }
    }
}
