import AppKit

/// What the panel's options row says, whichever way the folder is then picked.
struct NewAgentOptions {
    /// A scene id from `Art.sceneChoices`; nil follows the `nook.newAgentScene` preference.
    var scene: String?
    var resume = false
    var message = ""
}

/// The new-agent panel: type to filter recent and suggested folders, arrows and Return to start.
/// Takes typing without activating Nook, and goes away as soon as the user clicks elsewhere.
final class NewAgentPanel: MiniPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Row {
        case header(String)
        case folder(FolderChoice)
    }

    var onStart: ((FolderChoice, NewAgentOptions) -> Void)?
    var onChooseFolder: ((NewAgentOptions) -> Void)?
    var onRemove: ((String) -> Void)?

    private let search = NSSearchField()
    private let table = NSTableView()
    private let scenePicker = NSPopUpButton()
    private let resume = NSButton(checkboxWithTitle: "Resume last session", target: nil, action: nil)
    private let message = NSTextField()
    private let empty = NSTextField(labelWithString: "")
    private let scenes: [(id: String, name: String)]
    private var choices: [FolderChoice] = []
    private var open = Set<String>()
    private var rows: [Row] = []

    init(scenes: [(id: String, name: String)]) {
        self.scenes = scenes
        let size = TextSize.current
        super.init(size: NSSize(width: size.metric(460), height: size.metric(430)))
        isMovableByWindowBackground = false // a drag inside the list is a scroll or a selection, not a move

        search.placeholderString = "Search project folders"
        search.font = TextSize.font(.body)
        search.focusRingType = .none
        search.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(start)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        empty.font = TextSize.font(.secondary)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center

        scenePicker.addItem(withTitle: "Scene: per settings")
        scenes.forEach { scenePicker.addItem(withTitle: "Scene: \($0.name)") }
        scenePicker.font = TextSize.font(.secondary)
        scenePicker.isHidden = scenes.isEmpty
        resume.font = TextSize.font(.secondary)
        resume.toolTip = "Continue the newest Claude Code session in this folder instead of starting fresh."

        message.placeholderString = "First message (optional)"
        message.font = TextSize.font(.body)
        message.bezelStyle = .roundedBezel
        message.focusRingType = .none
        message.delegate = self

        let choose = NSButton(title: "Choose Folder…", target: self, action: #selector(chooseFolder))
        let go = NSButton(title: "Start Agent", target: self, action: #selector(start))
        go.keyEquivalent = "\r"
        for button in [choose, go] {
            button.bezelStyle = .rounded
            button.font = TextSize.font(.secondary)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let options = NSStackView(views: [scenePicker, resume])
        let buttons = NSStackView(views: [choose, spacer, go])

        let stack = NSStackView(views: [search, scroll, empty, options, message, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = size.metric(9)
        let side = size.metric(14)
        stack.edgeInsets = NSEdgeInsets(top: side, left: side, bottom: size.metric(12), right: side)
        stack.frame = glass.bounds
        stack.autoresizingMask = [.width, .height]
        glass.addSubview(stack)
        for view in [search, scroll, empty, message, buttons] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -side * 2).isActive = true
        }
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
        onCancel = { [weak self] in self?.dismiss() }
    }

    // MARK: showing

    /// `anchor` is the plus orb's frame; without one the panel takes the middle of the pointer's screen.
    func present(beside anchor: NSRect?) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? mouse) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        if let anchor {
            setFrameOrigin(Self.origin(for: frame.size, beside: anchor, in: area))
        } else {
            setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
    }

    /// Also called when the background scan finishes, so it keeps the selection where it can.
    func show(_ choices: [FolderChoice], open: Set<String>) {
        self.choices = choices
        self.open = open
        reload()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }

    /// Clicking anywhere else closes it, like a menu.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    // MARK: rows

    private var selected: FolderChoice? {
        guard rows.indices.contains(table.selectedRow), case .folder(let choice) = rows[table.selectedRow] else { return nil }
        return choice
    }

    private func reload() {
        let keep = selected?.path
        let matches = FolderSearch.rank(search.stringValue, in: choices)
        rows = []
        for (title, source) in [("RECENT", FolderChoice.Source.recent), ("SUGGESTED", .suggested)] {
            let group = matches.filter { $0.source == source }
            if !group.isEmpty { rows += [.header(title)] + group.map(Row.folder) }
        }
        table.reloadData()
        let index = rows.firstIndex { if case .folder(let c) = $0 { return c.path == keep } else { return false } }
            ?? rows.firstIndex { if case .folder = $0 { return true } else { return false } }
        if let index { select(index) }
        empty.stringValue = choices.isEmpty ? "No folders yet. Choose one to start your first agent."
                                            : "No folder matches. Return opens the folder chooser."
        empty.isHidden = !matches.isEmpty
        selectionChanged()
    }

    private func select(_ index: Int) {
        table.selectRowIndexes([index], byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    /// Arrow keys skip the headers and stop at the ends.
    private func moveSelection(_ delta: Int) {
        var index = table.selectedRow + delta
        while rows.indices.contains(index) {
            if case .folder = rows[index] { return select(index) }
            index += delta
        }
    }

    private func selectionChanged() {
        resume.isHidden = selected?.sessionID == nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return TextSize.metric(24) }
        return TextSize.metric(44)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .folder = rows[row] { return true }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) { selectionChanged() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let label = NSTextField(labelWithString: title)
            label.font = TextSize.font(.caption, weight: .semibold)
            label.textColor = .tertiaryLabelColor
            let cell = NSTableCellView()
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                                         label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3)])
            return cell
        case .folder(let choice):
            let tag = open.contains(choice.path) ? "open" : choice.sessionID != nil ? "can resume" : ""
            return FolderCell(choice, tag: tag) { [weak self] in self?.onRemove?(choice.path) }
        }
    }

    // MARK: keys and actions

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === search { reload() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): start()
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc clears a search first, as search fields do, and closes the panel otherwise.
            guard control === search, !search.stringValue.isEmpty else { dismiss(); return true }
            search.stringValue = ""
            reload()
        default: return false
        }
        return true
    }

    private var options: NewAgentOptions {
        let picked = scenePicker.indexOfSelectedItem - 1
        return NewAgentOptions(scene: scenes.indices.contains(picked) ? scenes[picked].id : nil,
                               resume: !resume.isHidden && resume.state == .on,
                               message: message.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func start() {
        guard isVisible else { return } // Return can arrive from the field and from the default button
        guard let selected else { return chooseFolder() }
        let options = self.options
        dismiss()
        onStart?(selected, options)
    }

    @objc private func chooseFolder() {
        let options = self.options
        dismiss()
        onChooseFolder?(options)
    }
}

/// One folder: its name, where it is, what is known about it, and (for recents) a way to forget it.
private final class FolderCell: NSTableCellView {
    private let remove: (() -> Void)?

    init(_ choice: FolderChoice, tag: String, remove: @escaping () -> Void) {
        self.remove = choice.source == .recent ? remove : nil
        super.init(frame: .zero)
        let name = NSTextField(labelWithString: choice.name)
        name.font = TextSize.font(.body, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        let path = NSTextField(labelWithString: choice.shortPath)
        path.font = TextSize.font(.caption)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingHead
        let text = NSStackView(views: [name, path])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let note = NSTextField(labelWithString: tag)
        note.font = TextSize.font(.caption)
        note.textColor = .secondaryLabelColor
        var views: [NSView] = [text, note]
        if self.remove != nil, let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove from recents") {
            let button = NSButton(image: image, target: self, action: #selector(removed))
            button.isBordered = false
            button.contentTintColor = .tertiaryLabelColor
            button.toolTip = "Remove from recents"
            views.append(button)
        }
        let row = NSStackView(views: views)
        row.spacing = TextSize.metric(8)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = choice.path
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func removed() { remove?() }
}

/// Two agents in one folder is legitimate, but usually the user wants the one that is there.
final class DuplicatePrompt: MiniPanel {
    private var goToExisting: (() -> Void)?
    private var startAnother: (() -> Void)?

    init(folder: String, near anchor: NSRect?, goToExisting: @escaping () -> Void, startAnother: @escaping () -> Void) {
        let size = TextSize.current
        super.init(size: NSSize(width: size.metric(400), height: size.metric(92)))
        self.goToExisting = goToExisting
        self.startAnother = startAnother
        onCancel = { [weak self] in self?.end(nil) }

        let label = NSTextField(labelWithString: "\(folder) already has an agent")
        label.font = TextSize.font(.title, weight: .semibold)
        label.lineBreakMode = .byTruncatingMiddle
        let go = NSButton(title: "Go to Existing", target: self, action: #selector(go))
        go.keyEquivalent = "\r"
        let another = NSButton(title: "Start Another", target: self, action: #selector(another))
        for button in [go, another] {
            button.bezelStyle = .rounded
            button.font = TextSize.font(.secondary)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, another, go])
        let column = NSStackView(views: [label, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = size.metric(10)
        let side = size.metric(16)
        column.edgeInsets = NSEdgeInsets(top: size.metric(14), left: side, bottom: size.metric(12), right: side)
        column.frame = glass.bounds
        column.autoresizingMask = [.width, .height]
        glass.addSubview(column)
        for view in [label, buttons] as [NSView] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -side * 2).isActive = true
        }

        let centre = anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        let area = (NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main)?.visibleFrame ?? .zero
        setFrameOrigin(anchor.map { Self.origin(for: frame.size, beside: $0, in: area) }
            ?? NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
        makeKeyAndOrderFront(nil)
    }

    @objc private func go() { end(goToExisting) }
    @objc private func another() { end(startAnother) }

    /// Left behind (the user clicked elsewhere) counts as Cancel.
    override func resignKey() {
        super.resignKey()
        end(nil)
    }

    private func end(_ action: (() -> Void)?) {
        guard goToExisting != nil else { return }
        goToExisting = nil
        startAnother = nil
        orderOut(nil)
        action?()
    }
}

/// The first-run hint beside the plus orb. One line, no keyboard; a click anywhere on it dismisses it.
final class CoachMark: NSPanel {
    init(_ text: String, beside anchor: NSRect) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NookLevel.prompt
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 10
        glass.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: text)
        label.font = TextSize.font(.label, weight: .medium)
        label.sizeToFit()
        let pad = TextSize.metric(12)
        label.setFrameOrigin(NSPoint(x: pad, y: pad - 2))
        glass.addSubview(label)
        contentView = glass

        let size = NSSize(width: label.frame.width + pad * 2, height: label.frame.height + pad * 2 - 4)
        let centre = NSPoint(x: anchor.midX, y: anchor.midY)
        let area = (NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main)?.visibleFrame ?? .zero
        setFrame(NSRect(origin: MiniPanel.origin(for: size, beside: anchor, in: area), size: size), display: true)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) { orderOut(nil) }
}
