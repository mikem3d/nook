import AppKit

/// One visual unit of the log: a message, or a run of consecutive tool calls.
enum LogItem: Equatable {
    case message(TranscriptEntry.Kind, String)
    /// `start` is the run's first index in the transcript: a stable identity for its expanded state.
    case tools(start: Int, lines: [String])
}

enum LogModel {
    /// Runs longer than this collapse to a single disclosure line.
    static let inlineToolLimit = 3

    /// Folds new transcript entries into `items`, merging tool calls into the trailing run.
    /// `offset` is the transcript index of the first new entry. Returns the index of the first
    /// item that was added or changed, so the view re-renders only from there.
    @discardableResult
    static func append(_ entries: ArraySlice<TranscriptEntry>, at offset: Int, to items: inout [LogItem]) -> Int {
        var firstChanged = items.count
        for (index, entry) in zip(offset..., entries) {
            if entry.kind == .tool {
                if case let .tools(start, lines)? = items.last {
                    items[items.count - 1] = .tools(start: start, lines: lines + [entry.text])
                    firstChanged = min(firstChanged, items.count - 1)
                } else {
                    items.append(.tools(start: index, lines: [entry.text]))
                }
            } else {
                items.append(.message(entry.kind, entry.text))
            }
        }
        return firstChanged
    }

    static func group(_ transcript: [TranscriptEntry]) -> [LogItem] {
        var items: [LogItem] = []
        append(transcript[...], at: 0, to: &items)
        return items
    }
}

/// Turns log items into attributed text. Every item ends with a thin spacer line.
enum LogRenderer {
    private static var toolFont: NSFont { TextSize.mono(.secondary) }

    static func render(_ item: LogItem, expanded: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        switch item {
        case let .message(.assistant, text):
            out.append(Markdown.render(text))
        case let .message(.user, text):
            out.append(line(text, font: TextSize.font(.body, weight: .semibold), color: .controlAccentColor, spacing: TextSize.metric(8)))
        case let .message(.system, text):
            out.append(line("— " + text, font: TextSize.font(.secondary), color: .secondaryLabelColor, spacing: TextSize.metric(6)))
        case let .message(.tool, text):
            out.append(toolLine(text, indent: 0))
        case let .tools(start, lines):
            if lines.count <= LogModel.inlineToolLimit {
                lines.forEach { out.append(toolLine($0, indent: 0)) }
            } else {
                let title = NSMutableAttributedString(string: "⚙ \(lines.count) tool calls \(expanded ? "▾" : "▸")", attributes: [
                    .font: TextSize.font(.secondary, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
                    .link: Markdown.actionURL, .nookToggle: start])
                if !expanded, let last = lines.last {
                    title.append(NSAttributedString(string: "   " + last, attributes: [.font: toolFont, .foregroundColor: NSColor.tertiaryLabelColor]))
                }
                out.append(paragraph(title, spacing: TextSize.metric(3), truncates: true))
                if expanded { lines.forEach { out.append(toolLine($0, indent: TextSize.metric(17))) } }
            }
        }
        out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: TextSize.metric(6))]))
        return out
    }

    /// The message being streamed, styled exactly like the entry that will replace it.
    static func renderStreaming(_ text: String) -> NSAttributedString {
        render(.message(.assistant, text), expanded: false)
    }

    private static func toolLine(_ text: String, indent: CGFloat) -> NSAttributedString {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        let content = NSAttributedString(string: "⚙ " + single, attributes: [.font: toolFont, .foregroundColor: NSColor.secondaryLabelColor])
        return paragraph(content, spacing: TextSize.metric(3), truncates: true, indent: indent)
    }

    private static func line(_ text: String, font: NSFont, color: NSColor, spacing: CGFloat) -> NSAttributedString {
        let content = NSAttributedString(string: text.replacingOccurrences(of: "\n", with: "\u{2028}"),
                                         attributes: [.font: font, .foregroundColor: color])
        return paragraph(content, spacing: spacing, truncates: false)
    }

    private static func paragraph(_ content: NSAttributedString, spacing: CGFloat, truncates: Bool, indent: CGFloat = 0) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: content)
        out.append(NSAttributedString(string: "\n", attributes: content.length > 0 ? content.attributes(at: content.length - 1, effectiveRange: nil) : [:]))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        if truncates { style.lineBreakMode = .byTruncatingTail }
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        let newline = NSRange(location: out.length - 1, length: 1)
        out.removeAttribute(.link, range: newline)
        out.removeAttribute(.nookToggle, range: newline)
        return out
    }
}
