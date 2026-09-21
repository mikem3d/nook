import AppKit

extension Notification.Name {
    /// Quiet mode went on or off. Object: AppController.
    static let nookQuietChanged = Notification.Name("nookQuietChanged")
}

/// Everything that decides whether the screen is dimmed. Pure, so it is tested headless.
struct OverlayState: Equatable {
    var active = false
    var quiet = false
    /// A screen grab is under way: Capture blanks every Nook panel, this one included.
    var capturing = false
    var opacity = FocusOverlay.defaultOpacity
    var clickToDismiss = true

    var shown: Bool { active && !quiet && !capturing && dim > 0 }
    /// Stored values are clamped: nothing is darker than 0.9, so the screen never goes fully black.
    var dim: Double { min(max(opacity, 0), 0.9) }
    /// Clicks are taken only while the dim is really on screen; otherwise the panel is click-through.
    var takesClicks: Bool { shown && clickToDismiss }
}

/// Dims the whole screen behind the active agent and the chat panel: one click-swallowing black
/// panel per screen at `NookLevel.focusOverlay`. Entirely notification driven; while no agent is
/// active there are no windows and nothing runs.
final class FocusOverlay: Feature {
    static let opacityKey = "nook.overlay.opacity"
    static let clickKey = "nook.overlay.clickToDismiss"
    static let defaultOpacity = 0.45
    private static let fade = 0.15

    private weak var app: AppController?
    private var panels: [OverlayPanel] = []
    private var state = OverlayState()
    private var transition = 0 // bumps on every change so a stale fade-out cannot hide a fresh overlay

    func install(in app: AppController) {
        self.app = app
        UserDefaults.standard.register(defaults: [Self.opacityKey: Self.defaultOpacity, Self.clickKey: true])
        let center = NotificationCenter.default
        for name in [Notification.Name.nookActiveChanged, .nookQuietChanged] {
            center.addObserver(forName: name, object: app, queue: .main) { [weak self] _ in self?.refresh() }
        }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.state.shown else { return }
            self.cover(NSScreen.screens, dim: self.state.dim)
        }
        refresh()
    }

    private func refresh() {
        guard let app else { return }
        let defaults = UserDefaults.standard
        var next = state
        next.active = app.active != nil
        next.quiet = app.isQuiet
        next.opacity = defaults.double(forKey: Self.opacityKey)
        next.clickToDismiss = defaults.bool(forKey: Self.clickKey)
        apply(next)
    }

    private func apply(_ next: OverlayState) {
        guard next != state else { return }
        let old = state
        state = next
        panels.forEach { $0.ignoresMouseEvents = !next.takesClicks }
        if next.capturing != old.capturing {
            // A grab hides and restores the panels itself, through their alpha. Once it is over,
            // catch up with whatever changed in the meantime.
            if !next.capturing { next.shown ? cover(NSScreen.screens, dim: next.dim) : tearDown() }
            return
        }
        if next.shown {
            transition += 1
            cover(NSScreen.screens, dim: next.dim)
        } else if old.shown {
            fadeOut()
        }
    }

    /// One panel per screen, over all of it, faded to `dim`. Also called when screens come and go.
    private func cover(_ screens: [NSScreen], dim: Double) {
        while panels.count > screens.count { panels.removeLast().orderOut(nil) }
        while panels.count < screens.count {
            let panel = OverlayPanel()
            panel.onClick = { [weak self] in self?.app?.deactivate() }
            panel.onBlanked = { [weak self] blanked in
                guard let self else { return }
                var next = self.state
                next.capturing = blanked
                self.apply(next)
            }
            panels.append(panel)
        }
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: true)
            panel.ignoresMouseEvents = !state.takesClicks
            panel.orderFrontRegardless()
        }
        animate(to: CGFloat(dim), then: nil)
    }

    private func fadeOut() {
        transition += 1
        let token = transition
        animate(to: 0) { [weak self] in
            guard let self, self.transition == token else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }

    private func animate(to dim: CGFloat, then done: (() -> Void)?) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = still ? 0 : Self.fade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panels.forEach { $0.shade.animator().alphaValue = dim }
        }, completionHandler: done)
    }
}

/// The dim over one screen. The window itself stays at alpha 1 and the darkness lives in its
/// content view, so when Capture blanks Nook's panels for a screen grab (window alpha 0, restored
/// afterwards) this one disappears and comes back with the rest, whatever its fade was doing.
private final class OverlayPanel: NSPanel {
    let shade = ShadeView()
    var onClick: (() -> Void)?
    /// Someone set the window's alpha to zero (true) or back (false).
    var onBlanked: ((Bool) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NookLevel.focusOverlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        shade.alphaValue = 0
        shade.onClick = { [weak self] in self?.onClick?() }
        contentView = shade
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override var alphaValue: CGFloat {
        didSet { if (alphaValue == 0) != (oldValue == 0) { onBlanked?(alphaValue == 0) } }
    }
}

/// Black, and the end of the line for every click: nothing reaches the app underneath.
private final class ShadeView: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
    override func otherMouseDown(with event: NSEvent) { onClick?() }
    override func scrollWheel(with event: NSEvent) {}
}
