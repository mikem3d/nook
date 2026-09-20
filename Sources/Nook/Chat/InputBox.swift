import AppKit

/// The editor inside the input box: a plain-text NSTextView (so paste, undo and IME are the
/// system's own) with a placeholder, and file/image pastes and drops routed to attachments.
final class InputTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var onFiles: (([URL]) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? .systemFont(ofSize: 15), .foregroundColor: NSColor.placeholderTextColor])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func paste(_ sender: Any?) {
        let files = Attachments.urls(from: .general)
        if files.isEmpty { pasteAsPlainText(sender) } else { onFiles?(files) }
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + Attachments.dragTypes }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = Attachments.urls(from: sender.draggingPasteboard)
        guard !files.isEmpty else { return super.performDragOperation(sender) }
        onFiles?(files)
        return true
    }
}

/// Multi-line input that grows from one line to `maxLines`, then scrolls.
final class InputBox: NSView, NSTextViewDelegate {
    static let maxLines: CGFloat = 6

    let textView = InputTextView(usingTextLayoutManager: false)
    var onSubmit: (() -> Void)?
    /// Esc with nothing left to clear.
    var onClose: (() -> Void)?
    /// Up-arrow in an empty input: the text to bring back, if any.
    var onRecall: (() -> String?)?

    private let scroll = NSScrollView()
    private var height: NSLayoutConstraint!
    private let inset = NSSize(width: 6, height: 6)

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            textView.undoManager?.removeAllActions()
            textView.needsDisplay = true
            updateHeight()
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9

        textView.font = .systemFont(ofSize: 15)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = inset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        height = heightAnchor.constraint(equalToConstant: 32)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            height,
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func layout() {
        super.layout()
        updateHeight() // the wrap width is only known once laid out
    }

    private func updateHeight() {
        guard let manager = textView.layoutManager, let container = textView.textContainer, let font = textView.font else { return }
        manager.ensureLayout(for: container)
        let line = manager.defaultLineHeight(for: font)
        let used = manager.usedRect(for: container).height
        let wanted = min(max(used, line), line * Self.maxLines).rounded(.up) + inset.height * 2
        if abs(height.constant - wanted) > 0.5 { height.constant = wanted }
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) { updateHeight() }

    /// Commands arrive here only after the input method has had its say, so Return that
    /// confirms an IME composition never sends.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if textView.string.isEmpty { onClose?() } else { replaceAll(with: "") }
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard textView.string.isEmpty, let last = onRecall?(), !last.isEmpty else { return false }
            replaceAll(with: last)
            return true
        default:
            return false
        }
    }

    /// Goes through the text system so the change can be undone.
    private func replaceAll(with string: String) {
        textView.insertText(string, replacementRange: NSRange(location: 0, length: (textView.string as NSString).length))
    }
}
