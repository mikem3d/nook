import AppKit

/// Thin bar showing how full the agent's context window is.
final class ContextBar: NSView {
    var fraction: CGFloat = 0 { didSet { if fraction != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard fraction > 0 else { return }
        (fraction > 0.8 ? NSColor.systemOrange : NSColor.controlAccentColor).setFill()
        let filled = NSRect(x: 0, y: 0, width: max(bounds.width * min(fraction, 1), bounds.height), height: bounds.height)
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}

/// Invisible strip along the panel's top edge; dragging it resizes the panel's height.
final class ResizeGrip: NSView {
    /// Called with the pointer's screen y while dragging, then with nil when the drag ends.
    var onDrag: ((CGFloat?) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation.y) }
    override func mouseUp(with event: NSEvent) { onDrag?(nil) }
}

/// The panel's glass background, tinted the mine's dusk purple; also the drop target for files
/// and images. The tint is dark, so the glass keeps a dark appearance for legible text.
final class DropGlass: NSVisualEffectView {
    static let tint = NSColor(red: 0.08, green: 0.075, blue: 0.11, alpha: 0.94)

    var onFiles: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        let wash = NSView(frame: bounds)
        wash.autoresizingMask = [.width, .height]
        wash.wantsLayer = true
        wash.layer?.backgroundColor = Self.tint.cgColor
        addSubview(wash)
        registerForDraggedTypes(Attachments.dragTypes)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = Attachments.urls(from: sender.draggingPasteboard)
        onFiles?(files)
        return !files.isEmpty
    }
}
