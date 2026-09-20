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
    private let dropHighlight = DropHighlightView()

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
        // Inside the surface, so drags still find the surface as their destination.
        dropHighlight.frame = surface.bounds
        dropHighlight.autoresizingMask = [.width, .height]
        dropHighlight.isHidden = true
        surface.addSubview(dropHighlight)
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func refresh() {
        let quiet = controller?.isQuiet ?? false
        room.show(state: session.state, bubble: quiet ? "" : session.bubble, unread: session.unread)
    }

    /// Shown while a desktop drag or a handoff hovers over this window.
    func setDropHighlight(_ on: Bool) { dropHighlight.isHidden = !on }

    /// Dropped items go to the chat panel's attachment tray when there is one; nothing is sent behind the user's back.
    fileprivate func accept(_ payload: IntakePayload) {
        guard let controller else { return }
        Intake.deliver(payload, to: self, in: controller)
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
        menu.addItem(item(GrabMode.region.title, #selector(lookAtRegion)))
        let others = controller?.windows.filter { $0 !== self } ?? []
        if !others.isEmpty {
            let handOff = NSMenuItem(title: "Hand Off To", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for other in others {
                submenu.addItem(ClosureItem(other.session.label) { [weak self, weak other] in
                    guard let self, let other else { return }
                    Handoff.shared?.ask(from: self, to: other)
                })
            }
            handOff.submenu = submenu
            menu.addItem(handOff)
        }
        if session.cwd != nil { // demo agents have no folder
            menu.addItem(item("Reveal Folder in Finder", #selector(revealFolder)))
            menu.addItem(item("Open in Terminal", #selector(openTerminal)))
        }
        if lastReply != nil { menu.addItem(item("Copy Last Reply", #selector(copyLastReply))) }
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

    private var lastReply: String? { session.transcript.last { $0.kind == .assistant }?.text }

    @objc private func lookAtRegion() { Capture.shared?.grab(.region, for: self) }

    @objc private func revealFolder() {
        guard let cwd = session.cwd else { return }
        NSWorkspace.shared.open(cwd)
    }

    @objc private func openTerminal() {
        guard let cwd = session.cwd else { return }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", cwd.path]
        try? open.run()
    }

    @objc private func copyLastReply() {
        guard let lastReply else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastReply, forType: .string)
    }
}

/// The drop target look: an accent frame and a faint wash. Never takes the mouse.
private final class DropHighlightView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = 3
        layer?.cornerRadius = 4
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Sits over the scene: tells a click from a drag and moves the window with the mouse.
private final class InteractionView: NSView {
    weak var owner: AgentWindow?
    private var pressed: NSPoint?
    private var grab = NSPoint.zero
    private var dragging = false
    private var handingOff = false // Option held when the drag began: pass context instead of docking

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(DropClassifier.types + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
            handingOff = event.modifierFlags.contains(.option) && Handoff.shared != nil
            if handingOff {
                Handoff.shared?.dragBegan(from: owner)
            } else {
                owner.controller?.willDrag(owner)
            }
        }
        if handingOff {
            Handoff.shared?.dragMoved(from: owner)
            return
        }
        let mouse = NSEvent.mouseLocation
        owner.setFrameOrigin(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
        owner.controller?.dragged(owner)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; dragging = false; handingOff = false }
        guard let pressed, let owner else { return }
        if handingOff {
            Handoff.shared?.dragEnded(from: owner)
        } else if dragging {
            owner.controller?.dropped(owner)
        } else {
            owner.clicked(at: pressed, in: bounds.size)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let owner else { return }
        NSMenu.popUpContextMenu(owner.contextMenu(), with: event, for: self)
    }

    // MARK: drops from the desktop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let owner, sender.draggingPasteboard.availableType(from: registeredDraggedTypes) != nil else { return [] }
        owner.setDropHighlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { owner?.setDropHighlight(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { owner?.setDropHighlight(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let owner else { return false }
        let pasteboard = sender.draggingPasteboard
        let store = IntakeStore.standard
        let items = DropClassifier.classify(pasteboard.pasteboardItems ?? [])
        if !items.isEmpty {
            owner.accept(store.payload(from: items))
            return true
        }
        // Promised files (Photos, Mail, some browsers) arrive a moment later, into our temp folder.
        guard let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
              !promises.isEmpty, (try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)) != nil
        else { return false }
        var files: [URL] = []
        let group = DispatchGroup()
        for promise in promises {
            promise.fileTypes.forEach { _ in group.enter() }
            promise.receivePromisedFiles(atDestination: store.directory, options: [:], operationQueue: .main) { url, error in
                if error == nil { files.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak owner] in owner?.accept(IntakePayload(files: files)) }
        return true
    }
}
