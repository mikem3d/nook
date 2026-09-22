import AppKit

/// The line at the foot of the log while a turn runs: a spinner, what the agent is doing in plain
/// words, the seconds ticking, and how to stop. It is its own view, so its 10 fps heartbeat never
/// touches the log's text storage.
final class ActivityLine: NSView {
    private let label = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var phase = ActivityPhase.idle
    private var started: Date?
    private var hint = "⌘. to stop"

    init() {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Called on every render. Starts the heartbeat when a turn is running and stops it the
    /// instant the turn ends.
    func show(_ session: AgentSession?) {
        let running = session?.turnStarted != nil || session?.pending != nil
        guard let session, running else { return stop() }
        phase = session.phase
        hint = session.pending != nil ? "⌘↩ allows, ⌘⌫ denies" : "⌘. or Stop interrupts"
        started = session.turnStarted ?? Date()
        isHidden = false
        if timer == nil {
            let beat = Timer(timeInterval: Activity.interval, repeats: true) { [weak self] _ in self?.tick() }
            beat.tolerance = Activity.interval / 4
            RunLoop.main.add(beat, forMode: .common)
            timer = beat
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isHidden = true
        started = nil
    }

    func applyTextSize() { tick() }

    /// One small attributed string rebuilt per frame; nothing else in the panel is touched.
    private func tick() {
        guard let started else { return }
        let seconds = Date().timeIntervalSince(started)
        label.attributedStringValue = Self.render(phase: phase, seconds: seconds,
                                                  at: ProcessInfo.processInfo.systemUptime, hint: hint)
    }

    private static func render(phase: ActivityPhase, seconds: Double, at time: Double, hint: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: Activity.frame(at: time) + "  ", attributes: [
            .font: TextSize.mono(.secondary), .foregroundColor: NSColor.secondaryLabelColor]))
        out.append(NSAttributedString(string: phase.words, attributes: [
            .font: TextSize.font(.secondary, weight: .medium), .foregroundColor: NSColor.labelColor]))
        out.append(NSAttributedString(string: "  " + Activity.elapsed(seconds), attributes: [
            .font: TextSize.digits(.secondary), .foregroundColor: NSColor.secondaryLabelColor]))
        out.append(NSAttributedString(string: "   " + hint, attributes: [
            .font: TextSize.font(.caption), .foregroundColor: NSColor.tertiaryLabelColor]))
        return out
    }
}
