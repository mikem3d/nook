import AppKit

enum FolderDrop {
    /// The folders among the dragged files. Files are ignored: only a folder can be an agent's home.
    static func folders(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}

/// Folders dropped on the menu bar icon. The status item's window passes drags to its delegate.
final class StatusDrop: NSObject, NSWindowDelegate, NSDraggingDestination {
    private let onDrop: ([URL]) -> Void

    init(button: NSStatusBarButton, onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init()
        button.window?.registerForDraggedTypes([.fileURL])
        button.window?.delegate = self
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        FolderDrop.folders(on: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let folders = FolderDrop.folders(on: sender.draggingPasteboard)
        guard !folders.isEmpty else { return false }
        onDrop(folders)
        return true
    }
}

/// While files are being dragged anywhere on screen, the free edge beyond each stack becomes a
/// drop target: a faint wash that lights up under the pointer. The panels exist only during such
/// a drag, so at all other times the screen edge belongs to the apps underneath.
///
/// Noticing the drag takes a global mouse monitor (mouse events need no permission). Its handler
/// does nothing but compare two numbers, and looks at the drag pasteboard's types (never its
/// contents) at most five times a second while the button is down.
final class EdgeDrop {
    private weak var app: AppController?
    private var monitor: Any?
    private var panels: [EdgeZonePanel] = []
    private var lastChange = NSPasteboard(name: .drag).changeCount
    private var lastLook: TimeInterval = 0

    init(app: AppController) {
        self.app = app
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.saw(event)
        }
    }

    deinit { monitor.map(NSEvent.removeMonitor) }

    private func saw(_ event: NSEvent) {
        if event.type == .leftMouseUp {
            // The drop itself reaches the panel a moment after the button goes up.
            if !panels.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.hide() } }
            return
        }
        guard panels.isEmpty, event.timestamp - lastLook > 0.2 else { return }
        lastLook = event.timestamp
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        if board.types?.contains(.fileURL) == true { show() }
    }

    private func show() {
        guard let app else { return }
        panels = app.edgeZones().map { zone in
            EdgeZonePanel(frame: zone.rect) { [weak self] folders in
                self?.hide()
                NewAgent.shared?.dropped(folders, corner: zone.corner, display: zone.display, near: nil)
            }
        }
        panels.forEach { $0.orderFrontRegardless() }
    }

    private func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

private final class EdgeZonePanel: NSPanel {
    init(frame: NSRect, onDrop: @escaping ([URL]) -> Void) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NookLevel.agent
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = EdgeZoneView(onDrop: onDrop)
    }

    override var canBecomeKey: Bool { false }
}

private final class EdgeZoneView: NSView {
    private let onDrop: ([URL]) -> Void
    private var lit = false { didSet { refresh() } }

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        registerForDraggedTypes([.fileURL])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Never fully clear: the window server only offers drags to pixels that are really there.
    private func refresh() {
        layer?.borderWidth = lit ? 3 : 1
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(lit ? 0.22 : 0.08).cgColor
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        lit = !FolderDrop.folders(on: sender.draggingPasteboard).isEmpty
        return lit ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { lit = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let folders = FolderDrop.folders(on: sender.draggingPasteboard)
        guard !folders.isEmpty else { return false }
        onDrop(folders)
        return true
    }
}
