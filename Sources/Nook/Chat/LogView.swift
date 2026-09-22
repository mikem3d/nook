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

    /// `nook.showThinking`: the agent's reasoning appears in the log as it arrives. On by default,
    /// because seeing it is the difference between waiting and watching.
    static let showThinkingKey = "nook.showThinking"
    static var showsThinking: Bool {
        UserDefaults.standard.object(forKey: showThinkingKey) as? Bool ?? true
    }

    private var sessionID: UUID?
    private var items: [LogItem] = []
    private var lengths: [Int] = []     // characters each item occupies in `storage`
    private var expanded = Set<Int>()
    private var streaming = ""
    private var streamLength = 0
    /// Turns the spinners on the rows that are still running; nil whenever nothing is running.
    private var spinnerTimer: Timer?
    private var spinner = Activity.frames[0]
    /// Item index -> the shell run's `version` as last drawn. A shell block changes in place
    /// (output arriving, a button pressed) without the item itself differing, so it is redrawn
    /// when its version moves.
    private var shellVersions: [Int: Int] = [:]

    /// A button inside a shell result block was clicked.
    var onShell: ((ShellAction) -> Void)?

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
        if session.id != sessionID {
            reset()
            sessionID = session.id
        }
        let wanted = LogModel.group(session.transcript, openThinking: session.openThinking,
                                    showThinking: Self.showsThinking)
        let stream = Self.tail(session.streamingText, after: wanted.last)
        var changed = LogModel.firstChange(from: items, to: wanted)
        items = wanted
        // A shell block is the same item while its output grows, so its version says when to redraw.
        for (index, drawn) in shellVersions {
            guard items.indices.contains(index), case let .message(.shell(run), _) = items[index],
                  run.version != drawn else { continue }
            changed = min(changed ?? index, index)
        }
        syncSpinner()
        guard changed != nil || stream != streaming else { return }
        redraw(from: changed ?? items.count, stream: stream)
    }

    /// Rewrites the storage from `firstChanged` on, leaving everything before it untouched.
    private func redraw(from firstChanged: Int, stream: String) {
        let pinned = isAtBottom
        storage.beginEditing()
        let keep = lengths.prefix(firstChanged).reduce(0, +)
        if firstChanged < items.count {
            storage.deleteCharacters(in: NSRange(location: keep, length: storage.length - keep))
            lengths.removeSubrange(min(firstChanged, lengths.count)...)
            shellVersions = shellVersions.filter { $0.key < firstChanged }
            for (index, item) in zip(firstChanged..., items[firstChanged...]) {
                let rendered = render(item)
                storage.append(rendered)
                lengths.append(rendered.length)
                if case let .message(.shell(run), _) = item { shellVersions[index] = run.version }
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
        (sessionID, items, lengths, expanded, streaming, streamLength) = (nil, [], [], [], "", 0)
        shellVersions = [:]
        storage.setAttributedString(NSAttributedString())
        syncSpinner()
    }

    // MARK: spinners

    /// One timer, only while something is actually running, and it redraws just the items that
    /// hold a running row: the rest of the log is never touched.
    private func syncSpinner() {
        let live = items.contains { $0.isLive }
        if live, spinnerTimer == nil, window != nil {
            let timer = Timer(timeInterval: Activity.interval, repeats: true) { [weak self] _ in self?.turnSpinner() }
            timer.tolerance = Activity.interval / 4
            RunLoop.main.add(timer, forMode: .common)
            spinnerTimer = timer
        } else if !live || window == nil {
            spinnerTimer?.invalidate()
            spinnerTimer = nil
        }
    }

    private func turnSpinner() {
        spinner = Activity.frame(at: ProcessInfo.processInfo.systemUptime)
        guard let first = items.firstIndex(where: { $0.isLive }) else { return syncSpinner() }
        let pinned = isAtBottom
        storage.beginEditing()
        for index in first..<items.count where items[index].isLive {
            let rendered = render(items[index])
            let offset = lengths.prefix(index).reduce(0, +)
            guard index < lengths.count, offset + lengths[index] <= storage.length else { continue }
            storage.replaceCharacters(in: NSRange(location: offset, length: lengths[index]), with: rendered)
            lengths[index] = rendered.length
        }
        storage.endEditing()
        if pinned { scrollToBottom() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncSpinner()
    }

    /// The engine may append the finished entry a beat before it clears `streamingText`;
    /// never show the same message twice.
    private static func tail(_ streamingText: String, after last: LogItem?) -> String {
        let stream = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .message(.assistant, text)? = last, !stream.isEmpty, text.hasPrefix(stream) { return "" }
        return stream
    }

    private func render(_ item: LogItem) -> NSAttributedString {
        LogRenderer.render(item, expanded: item.key.map(expanded.contains) ?? false, spinner: spinner)
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
        if let action = attributes[.nookShell] as? ShellAction {
            onShell?(action)
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
        guard let index = items.firstIndex(where: { $0.key == start }), index < lengths.count else { return }
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
