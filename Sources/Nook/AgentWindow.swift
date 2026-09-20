import AppKit
import SpriteKit

enum Corner: Int {
    case bottomRight, bottomLeft, topRight, topLeft

    var isRight: Bool { self == .bottomRight || self == .topRight }
    var isBottom: Bool { self == .bottomRight || self == .bottomLeft }
}

/// One agent's scene. Never takes keyboard focus, floats above everything, follows you across Spaces.
final class AgentWindow: NSPanel {
    let session: AgentSession
    let room: RoomScene
    weak var controller: AppController?

    var corner: Corner = .bottomRight
    var minimised = false

    private let skView = SKView()

    init(session: AgentSession, art: Art, roomIndex: Int) {
        self.session = session
        room = RoomScene(art: art, roomIndex: roomIndex, title: session.label)
        super.init(contentRect: NSRect(x: 0, y: 0, width: RoomScene.W * 2, height: RoomScene.H * 2),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 15 // pixel animation tops out at 8 fps
        skView.presentScene(room)

        let surface = InteractionView()
        surface.owner = self
        skView.autoresizingMask = [.width, .height]
        surface.autoresizingMask = [.width, .height]
        let content = NSView(frame: contentLayoutRect)
        skView.frame = content.bounds
        surface.frame = content.bounds
        content.addSubview(skView)
        content.addSubview(surface)
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func refresh() {
        let quiet = controller?.isQuiet ?? false
        room.show(state: session.state, bubble: quiet ? "" : session.bubble, unread: session.unread)
    }

    fileprivate func clicked(at point: NSPoint, in size: NSSize) {
        let s = size.width / RoomScene.W
        let onMinimise = point.y > size.height - RoomScene.bar * s && point.x > size.width - 14 * s
        if minimised || onMinimise {
            controller?.toggleMinimise(self)
        } else {
            controller?.activate(self)
        }
    }

    fileprivate func contextMenu() -> NSMenu {
        let menu = NSMenu()
        if session.pending != nil {
            menu.addItem(item("Allow", #selector(allow)))
            menu.addItem(item("Deny", #selector(deny)))
            menu.addItem(.separator())
        }
        menu.addItem(item(minimised ? "Restore" : "Minimise", #selector(toggleMinimise)))
        menu.addItem(item("Interrupt", #selector(interrupt)))
        menu.addItem(.separator())
        menu.addItem(item("Close Agent", #selector(closeAgent)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func allow() { controller?.answer(self, allow: true) }
    @objc private func deny() { controller?.answer(self, allow: false) }
    @objc private func toggleMinimise() { controller?.toggleMinimise(self) }
    @objc private func interrupt() { session.interrupt() }
    @objc private func closeAgent() { controller?.close(self) }
}

/// Sits over the scene: tells a click from a drag and moves the window with the mouse.
private final class InteractionView: NSView {
    weak var owner: AgentWindow?
    private var pressed: NSPoint?
    private var grab = NSPoint.zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        pressed = event.locationInWindow
        let mouse = NSEvent.mouseLocation
        grab = NSPoint(x: mouse.x - owner.frame.minX, y: mouse.y - owner.frame.minY)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressed, let owner else { return }
        if !dragging {
            let p = event.locationInWindow
            guard hypot(p.x - pressed.x, p.y - pressed.y) > 3 else { return }
            dragging = true
            owner.controller?.willDrag(owner)
        }
        let mouse = NSEvent.mouseLocation
        owner.setFrameOrigin(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
        owner.controller?.dragged(owner)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; dragging = false }
        guard let pressed, let owner else { return }
        if dragging {
            owner.controller?.dropped(owner)
        } else {
            owner.clicked(at: pressed, in: bounds.size)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let owner else { return }
        NSMenu.popUpContextMenu(owner.contextMenu(), with: event, for: self)
    }
}
