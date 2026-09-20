import AppKit

/// One-click replies, chosen by how the last turn ended. The table is plain data so it can be
/// edited later: `defaults write … nook.replyChips -dict done -array "Continue" …`.
enum ReplyChips {
    static let defaultsKey = "nook.replyChips"

    enum Situation: String {
        case done, failed
    }

    static let builtIn: [String: [String]] = [
        Situation.done.rawValue: ["Continue", "Run the tests", "Commit this", "Explain what changed"],
        Situation.failed.rawValue: ["Try again", "What went wrong?"],
    ]

    /// Nothing while busy or before the agent has answered; `failed` when the turn ended in an error.
    static func situation(busy: Bool, transcript: [TranscriptEntry]) -> Situation? {
        guard !busy, let last = transcript.last else { return nil }
        if last.kind == .system, last.text.localizedCaseInsensitiveContains("error") { return .failed }
        guard let answered = transcript.lastIndex(where: { $0.kind == .assistant }) else { return nil }
        let asked = transcript.lastIndex { $0.kind == .user } ?? -1
        return answered > asked ? .done : nil
    }

    static func titles(for situation: Situation?, defaults: UserDefaults = .standard) -> [String] {
        guard let situation else { return [] }
        let custom = defaults.dictionary(forKey: defaultsKey)?[situation.rawValue] as? [String]
        return custom ?? builtIn[situation.rawValue] ?? []
    }
}

/// A small rounded button used for reply chips and attachment chips.
final class PillButton: NSButton {
    var onClick: (() -> Void)?

    init(title: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        font = .systemFont(ofSize: 11, weight: .medium)
        contentTintColor = .labelColor
        lineBreakMode = .byTruncatingMiddle
        target = self
        action = #selector(clicked)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: min(size.width + 18, 220), height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.2 : 0.09).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        super.draw(dirtyRect)
    }

    @objc private func clicked() { onClick?() }
}

/// Files dropped or pasted into the panel.
enum Attachments {
    static let dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]

    /// File URLs on the pasteboard, or a bare image (a screenshot, "Copy Image") saved to a
    /// temporary PNG. Empty when the pasteboard holds ordinary text.
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return files }
        guard pasteboard.string(forType: .string) == nil,
              pasteboard.availableType(from: [.png, .tiff]) != nil,
              let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return [] }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-attachments", isDirectory: true)
        let file = folder.appendingPathComponent("pasted-\(UUID().uuidString.prefix(8)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
            return [file]
        } catch {
            return []
        }
    }
}
