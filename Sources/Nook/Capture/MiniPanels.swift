import AppKit

/// A small glass panel that can take typing without activating Nook, in the chat panel's style.
class MiniPanel: NSPanel {
    var onCancel: (() -> Void)?
    let glass = NSVisualEffectView()

    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true

        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 10
        glass.layer?.masksToBounds = true
        contentView = glass
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Beside `anchor` on whichever side has room, kept on its screen.
    static func origin(for size: NSSize, beside anchor: NSRect, in area: NSRect, gap: CGFloat = 8) -> NSPoint {
        var x = anchor.midX > area.midX ? anchor.minX - gap - size.width : anchor.maxX + gap
        var y = anchor.midY - size.height / 2
        x = min(max(x, area.minX + gap), area.maxX - size.width - gap)
        y = min(max(y, area.minY + gap), area.maxY - size.height - gap)
        return NSPoint(x: x, y: y)
    }
}

/// One line of text anchored to an agent window. Return sends (empty is fine), Esc cancels.
final class LinePrompt: MiniPanel {
    private let field = NSTextField()
    private var finish: ((String?) -> Void)?

    init(title: String, placeholder: String, beside anchor: NSWindow, done: @escaping (String?) -> Void) {
        super.init(size: NSSize(width: 340, height: 64))
        finish = done
        onCancel = { [weak self] in self?.end(nil) }

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.target = self
        field.action = #selector(submit)

        let column = NSStackView(views: [label, field])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        column.frame = glass.bounds
        column.autoresizingMask = [.width, .height]
        glass.addSubview(column)
        field.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -24).isActive = true

        let area = (anchor.screen ?? NSScreen.main)?.visibleFrame ?? anchor.frame
        setFrameOrigin(Self.origin(for: frame.size, beside: anchor.frame, in: area))
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    @objc private func submit() { end(field.stringValue) }

    private func end(_ value: String?) {
        guard let finish else { return }
        self.finish = nil
        orderOut(nil)
        finish(value)
    }
}

/// Follows the pointer during a handoff drag. Never takes clicks.
final class GhostChip: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        pill.layer?.cornerRadius = 11
        pill.addSubview(label)
        contentView = pill
        show(text)
    }

    override var canBecomeKey: Bool { false }

    func show(_ text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 20, height: 22)
        label.setFrameOrigin(NSPoint(x: 10, y: (size.height - label.frame.height) / 2))
        setContentSize(size)
    }

    func follow(_ mouse: NSPoint) {
        setFrameOrigin(NSPoint(x: mouse.x + 12, y: mouse.y - frame.height - 10))
    }
}
