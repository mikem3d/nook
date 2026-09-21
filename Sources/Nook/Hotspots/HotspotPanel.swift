import AppKit
import SwiftUI

/// Every text size the hotspot panels use, in one table, all following the app-wide `nook.textSize` setting.
enum HotspotText {
    static var title: Font { .system(size: TextSize.current.points(18), weight: .semibold) }
    static var heading: Font { .system(size: TextSize.points(.secondary), weight: .semibold) }
    static var body: Font { .system(size: TextSize.points(.body)) }
    static var caption: Font { .system(size: TextSize.points(.secondary)) }
    static var day: Font { .system(size: TextSize.points(.label)).monospacedDigit() }
}

/// Where a panel goes: beside the agent window on the side with more room, else above or below it.
enum PanelPlacement {
    static func frame(size: CGSize, beside anchor: CGRect, in area: CGRect, gap: CGFloat = 8) -> CGRect {
        let (left, right) = (anchor.minX - area.minX, area.maxX - anchor.maxX)
        var origin: CGPoint
        if max(left, right) >= size.width + gap {
            // Tops level, so the panel reads as hanging off the window.
            origin = CGPoint(x: right >= left ? anchor.maxX + gap : anchor.minX - gap - size.width, y: anchor.maxY - size.height)
        } else {
            let above = area.maxY - anchor.maxY >= anchor.minY - area.minY
            origin = CGPoint(x: anchor.midX - size.width / 2, y: above ? anchor.maxY + gap : anchor.minY - gap - size.height)
        }
        origin.x = min(max(origin.x, area.minX), max(area.maxX - size.width, area.minX))
        origin.y = min(max(origin.y, area.minY), max(area.maxY - size.height, area.minY))
        return CGRect(origin: origin, size: size)
    }
}

/// The one panel a hotspot opens. Non-activating, so the user's editor keeps the focus it has, but
/// key-capable, because both panels have text fields. Esc, or a click anywhere else, closes it.
final class HotspotPanel: NSPanel {
    private(set) weak var anchor: AgentWindow?
    private(set) var hotspot = ""
    var onClose: (() -> Void)?
    private var clickMonitor: Any?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NookLevel.prompt // above the focus overlay, level with the agent window it hangs off
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    func present<Content: View>(_ view: Content, size: CGSize, hotspot: String, beside window: AgentWindow) {
        dismiss()
        anchor = window
        self.hotspot = hotspot
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        glass.frame = host.frame
        glass.addSubview(host)
        contentView = glass
        setContentSize(size)
        follow()
        makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(self, selector: #selector(follow), name: NSWindow.didMoveNotification, object: window)
        // A click on an agent window does not take the keyboard from this panel, so `resignKey` alone would miss it.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window !== self, event.window?.parent !== self { self.dismiss() }
            return event
        }
    }

    @objc private func follow() {
        guard let anchor else { return }
        let area = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? anchor.frame
        setFrame(PanelPlacement.frame(size: frame.size, beside: anchor.frame, in: area), display: true)
    }

    func dismiss() {
        guard anchor != nil else { return }
        anchor = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        orderOut(nil)
        contentView = nil
        onClose?()
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }
}
