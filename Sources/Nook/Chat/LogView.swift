import AppKit

/// Draws the subtle rounded box behind fenced code blocks.
private final class CodeLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let whole = NSRange(location: 0, length: storage.length)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        storage.enumerateAttribute(.nookCode, in: visible) { value, range, _ in
            guard value != nil else { return }
            var block = NSRange()
            _ = storage.attribute(.nookCode, at: range.location, longestEffectiveRange: &block, in: whole)
            let glyphs = glyphRange(forCharacterRange: block, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let top = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let bottom = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            let inset = container.lineFragmentPadding
            let box = NSRect(x: origin.x + inset, y: origin.y + top.minY,
                             width: container.size.width - inset * 2, height: bottom.maxY - top.minY)
            let radius = TextSize.metric(8)
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
        }
    }
}

/// The scrolling log. It mirrors a session's transcript incrementally: new entries are appended,
/// only the trailing item is ever re-rendered, and the streamed message is a replaceable tail.
final class LogView: NSScrollView, NSTextViewDelegate {
    private let storage = NSTextStorage()
    private let text: NSTextView

    private var sessionID: UUID?
    private var consumed = 0            // transcript entries already folded into `items`
    private var items: [LogItem] = []
    private var lengths: [Int] = []     // characters each item occupies in `storage`
    private var expanded = Set<Int>()
    private var streaming = ""
    private var streamLength = 0

    init() {
        let manager = CodeLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        text = NSTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)

        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 6)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        text.delegate = self
        documentView = text
        hasVerticalScroller = true
        drawsBackground = false
        borderType = .noBorder
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ session: AgentSession) {
        let transcript = session.transcript
        if session.id != sessionID || transcript.count < consumed {
            reset()
            sessionID = session.id
        }
        var firstChanged = items.count
        if transcript.count > consumed {
            firstChanged = LogModel.append(transcript[consumed...], at: consumed, to: &items)
            consumed = transcript.count
        }
        let stream = Self.tail(session.streamingText, after: items.last)
        guard firstChanged < items.count || stream != streaming else { return }

        let pinned = isAtBottom
        storage.beginEditing()
        let keep = lengths.prefix(firstChanged).reduce(0, +)
        if firstChanged < items.count {
            storage.deleteCharacters(in: NSRange(location: keep, length: storage.length - keep))
            lengths.removeSubrange(firstChanged...)
            for item in items[firstChanged...] {
                let rendered = render(item)
                storage.append(rendered)
                lengths.append(rendered.length)
            }
        } else {
            storage.deleteCharacters(in: NSRange(location: storage.length - streamLength, length: streamLength))
        }
        let live = stream.isEmpty ? NSAttributedString() : LogRenderer.renderStreaming(stream)
        storage.append(live)
        (streaming, streamLength) = (stream, live.length)
        storage.endEditing()
        if pinned { scrollToBottom() }
    }

    /// Forgets everything rendered, so the next `show` draws the log afresh (a new session, or a new text size).
    func reset() {
        (sessionID, consumed, items, lengths, expanded, streaming, streamLength) = (nil, 0, [], [], [], "", 0)
        storage.setAttributedString(NSAttributedString())
    }

    /// The engine may append the finished entry a beat before it clears `streamingText`;
    /// never show the same message twice.
    private static func tail(_ streamingText: String, after last: LogItem?) -> String {
        let stream = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .message(.assistant, text)? = last, !stream.isEmpty, text.hasPrefix(stream) { return "" }
        return stream
    }

    private func render(_ item: LogItem) -> NSAttributedString {
        if case let .tools(start, _) = item { return LogRenderer.render(item, expanded: expanded.contains(start)) }
        return LogRenderer.render(item, expanded: false)
    }

    // MARK: scrolling

    private var isAtBottom: Bool { contentView.bounds.maxY >= text.frame.height - 16 }

    func scrollToBottom() {
        if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
        text.scrollToEndOfDocument(nil)
    }

    /// Stay pinned to the newest line when the panel or the input box changes height.
    override func setFrameSize(_ newSize: NSSize) {
        let pinned = isAtBottom
        super.setFrameSize(newSize)
        if pinned { scrollToBottom() }
    }

    // MARK: in-log actions

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard charIndex < storage.length else { return false }
        let attributes = storage.attributes(at: charIndex, effectiveRange: nil)
        if let start = attributes[.nookToggle] as? Int {
            toggle(start)
            return true
        }
        if let code = attributes[.nookCopy] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            var range = NSRange()
            _ = storage.attribute(.nookCopy, at: charIndex, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
            if range.length == 4 { // "Copy" becomes "Copied"; the next re-render resets it
                storage.replaceCharacters(in: range, with: "Copied")
                grow(itemContaining: charIndex, by: 2)
            }
            return true
        }
        return false // a real link: AppKit opens it
    }

    private func toggle(_ start: Int) {
        guard let index = items.firstIndex(where: { if case .tools(start, _) = $0 { return true } else { return false } }) else { return }
        expanded.formSymmetricDifference([start])
        let rendered = render(items[index])
        let offset = lengths.prefix(index).reduce(0, +)
        storage.replaceCharacters(in: NSRange(location: offset, length: lengths[index]), with: rendered)
        lengths[index] = rendered.length
    }

    private func grow(itemContaining charIndex: Int, by delta: Int) {
        var end = 0
        for index in lengths.indices {
            end += lengths[index]
            if charIndex < end {
                lengths[index] += delta
                return
            }
        }
        streamLength += delta
    }
}
