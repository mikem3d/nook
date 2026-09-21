// HUD: a transient confirmation that never takes focus or mouse clicks.
//
//     HUD.shared.show("Allowed Bash for zipdemand", detail: "rm -rf build/", near: window, important: true)
//
// - `near`: the HUD sits just above (or below) that window; nil puts it top-centre of the main screen.
// - `important: false` (the default) is dropped while quiet mode is on. Only pass true for
//   things the user must see, such as what a hotkey just approved.
// - One HUD at a time: a new message replaces the old one. It fades after `duration` and
//   nothing runs once it is gone.

import AppKit

final class HUD {
    static let shared = HUD()

    /// Quiet mode plugs in here; while it returns true only important messages show.
    var isSuppressed: () -> Bool = { false }

    private var panel: NSPanel?
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var widthLimit: NSLayoutConstraint!
    private var hide: DispatchWorkItem?

    func show(_ text: String, detail extra: String = "", near window: NSWindow? = nil,
              important: Bool = false, duration: TimeInterval = 1.8) {
        guard important || !isSuppressed() else { return }
        let panel = self.panel ?? build()
        self.panel = panel
        applyTextSize()
        title.stringValue = text
        detail.stringValue = extra
        detail.isHidden = extra.isEmpty

        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        panel.setFrame(Self.frame(size: size, near: window), display: true)

        hide?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        let current = hide
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A newer message may have arrived during the fade; leave that one up.
            if self?.hide === current { panel.orderOut(nil) }
        })
    }

    /// Read each time a message shows, so the HUD follows the setting without observing it.
    private func applyTextSize() {
        let size = TextSize.current
        title.font = TextSize.font(.title, weight: .semibold)
        detail.font = TextSize.mono(.secondary)
        stack.spacing = size.metric(4)
        stack.edgeInsets = NSEdgeInsets(top: size.metric(12), left: size.metric(20), bottom: size.metric(12), right: size.metric(20))
        widthLimit.constant = size.metric(480)
    }

    private static func frame(size: NSSize, near window: NSWindow?) -> NSRect {
        let gap: CGFloat = 8
        guard let window, let area = (window.screen ?? NSScreen.main)?.visibleFrame else {
            let area = NSScreen.main?.visibleFrame ?? .zero
            return NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 40, width: size.width, height: size.height)
        }
        var x = window.frame.midX - size.width / 2
        var y = window.frame.maxY + gap
        if y + size.height > area.maxY { y = window.frame.minY - gap - size.height }
        x = min(max(x, area.minX + gap), area.maxX - size.width - gap)
        y = min(max(y, area.minY + gap), area.maxY - size.height - gap)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func build() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NookLevel.hud
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 10
        glass.layer?.masksToBounds = true

        title.lineBreakMode = .byTruncatingTail
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle

        stack.setViews([title, detail], in: .top)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(stack)
        widthLimit = glass.widthAnchor.constraint(lessThanOrEqualToConstant: 480)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            widthLimit,
        ])
        panel.contentView = glass
        return panel
    }
}
