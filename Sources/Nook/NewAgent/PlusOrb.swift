import AppKit

/// The new-agent button: a quiet orb at the far end of a stack. Click opens the new-agent panel,
/// a dropped folder starts an agent in this stack, and dragging it picks the default corner.
///
/// It is drawn with AppKit from the theme's own orb back and ring, with a plus where an agent's
/// head would be. A themed "plus" sprite should replace the drawn plus later.
final class PlusOrbWindow: NSPanel {
    private weak var controller: AppController?
    var corner: Corner = .bottomRight
    var display: CGDirectDisplayID = 0
    private let face: PlusOrbView

    init(art: Art, controller: AppController) {
        self.controller = controller
        face = PlusOrbView(art: art)
        super.init(contentRect: NSRect(x: 0, y: 0, width: RoomScene.orb * 2, height: RoomScene.orb * 2),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NookLevel.agent
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // a square shadow around a disc is worse than none, as with agent orbs
        isReleasedWhenClosed = false
        animationBehavior = .none
        face.owner = self
        face.autoresizingMask = [.width, .height]
        contentView = face
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setDimmed(_ on: Bool) { face.dimmed = on }

    func dock(to frame: NSRect, animated: Bool) {
        guard !face.isDragging else { return }
        let animated = animated && isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !isVisible {
            setFrame(frame, display: true)
            orderFrontRegardless()
        } else if self.frame != frame {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    animator().setFrame(frame, display: true)
                }
            } else {
                setFrame(frame, display: true)
            }
        }
    }

    fileprivate func clicked() { NewAgent.shared?.present(from: self) }
    fileprivate func dragEnded() { controller?.plusDropped(self) }

    fileprivate func received(_ folders: [URL]) {
        NewAgent.shared?.dropped(folders, corner: corner, display: display, near: frame)
    }
}

private final class PlusOrbView: NSView {
    weak var owner: PlusOrbWindow?
    private let back: NSImage?
    private let ring: NSImage?
    private var pressed: NSPoint?
    private var grab = NSPoint.zero
    private(set) var isDragging = false
    private var hovering = false { didSet { refreshAlpha() } }
    private var dropping = false { didSet { refreshAlpha(); needsDisplay = true } }
    var dimmed = false { didSet { refreshAlpha() } }

    init(art: Art) {
        let spec = art.theme.orb
        back = spec?.back.flatMap { NSImage(contentsOf: art.root.appendingPathComponent($0)) }
        ring = spec?.ring.flatMap { NSImage(contentsOf: art.root.appendingPathComponent($0)) }
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        // The panel is never key, so only `.activeAlways` sees the pointer. Nothing runs otherwise.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        toolTip = "New agent: click, or drop a project folder here"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("New agent")
        refreshAlpha()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Quieter than an agent orb until the pointer or a folder is over it.
    private func refreshAlpha() {
        alphaValue = dropping ? 1 : dimmed ? 0.3 : hovering ? 1 : 0.6
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.imageInterpolation = .none // art pixels stay square
        context.shouldAntialias = false
        let s = bounds.width / RoomScene.orb
        if let back, let ring {
            back.draw(in: bounds)
            ring.draw(in: bounds)
        } else {
            // No orb art: the same plain dark disc with a grey rim the agent orbs fall back to.
            let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: s, dy: s))
            NSColor(red: 0.17, green: 0.16, blue: 0.23, alpha: 1).setFill()
            disc.fill()
            NSColor(white: 0.55, alpha: 1).setStroke()
            disc.lineWidth = 2 * s
            disc.stroke()
        }
        // The plus: two bars of art pixels, centred, with a one pixel shadow under them.
        let bars = [NSRect(x: 9, y: 13, width: 10, height: 2), NSRect(x: 13, y: 9, width: 2, height: 10)]
        func fill(_ color: NSColor, dy: CGFloat) {
            color.setFill()
            for bar in bars { NSRect(x: bar.minX * s, y: (bar.minY + dy) * s, width: bar.width * s, height: bar.height * s).fill() }
        }
        fill(NSColor(white: 0, alpha: 0.5), dy: -1)
        fill(NSColor(red: 0.93, green: 0.86, blue: 0.68, alpha: 1), dy: 0)
        if dropping {
            let halo = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            NSColor.controlAccentColor.setStroke()
            halo.lineWidth = 3
            halo.stroke()
        }
    }

    // MARK: mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The square's corners are not part of the orb.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        return WindowChrome.inOrb(convert(point, from: superview), size: bounds.size) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        pressed = event.locationInWindow
        let mouse = NSEvent.mouseLocation
        grab = NSPoint(x: mouse.x - owner.frame.minX, y: mouse.y - owner.frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressed, let owner else { return }
        if !isDragging {
            let p = event.locationInWindow
            guard hypot(p.x - pressed.x, p.y - pressed.y) > 3 else { return }
            isDragging = true
        }
        let mouse = NSEvent.mouseLocation
        owner.setFrameOrigin(NSPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed != nil, let owner else { return }
        let wasDragging = isDragging
        pressed = nil
        isDragging = false
        if wasDragging { owner.dragEnded() } else { owner.clicked() }
    }

    // MARK: folders from Finder

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropping = !FolderDrop.folders(on: sender.draggingPasteboard).isEmpty
        return dropping ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { dropping = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropping = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let folders = FolderDrop.folders(on: sender.draggingPasteboard)
        guard !folders.isEmpty else { return false }
        owner?.received(folders)
        return true
    }
}
