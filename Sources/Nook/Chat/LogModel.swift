import AppKit

/// One visual unit of the log: a message, a run of consecutive tool calls, or a block of thinking.
enum LogItem: Equatable {
    case message(TranscriptEntry.Kind, String)
    /// `start` is the run's first index in the transcript: a stable identity for its expanded state.
    case tools(start: Int, rows: [ToolRow])
    /// Reasoning. `live` while it is still arriving, which is also when it shows itself in full.
    case thinking(start: Int, text: String, tokens: Int, live: Bool)

    /// The transcript index that identifies a collapsible item.
    var key: Int? {
        switch self {
        case .message: return nil
        case let .tools(start, _): return start
        case let .thinking(start, _, _, _): return start
        }
    }

    /// True while something in this item is still happening, so the log keeps its spinner turning.
    var isLive: Bool {
        switch self {
        case let .tools(_, rows): return rows.contains { $0.status == .running }
        case let .thinking(_, _, _, live): return live
        case .message: return false
        }
    }
}

enum LogModel {
    /// Runs longer than this collapse to a single disclosure line.
    static let inlineToolLimit = 3

    /// Folds a transcript into log items. `openThinking` is the index of the thinking block still
    /// arriving, if any; `showThinking` is the `nook.showThinking` setting.
    static func group(_ transcript: [TranscriptEntry], openThinking: Int? = nil, showThinking: Bool = true) -> [LogItem] {
        var items: [LogItem] = []
        for (index, entry) in transcript.enumerated() {
            switch entry.kind {
            case .tool:
                let row = entry.tool ?? ToolRow(id: "\(index)", name: entry.text, status: .ok)
                if case let .tools(start, rows)? = items.last {
                    items[items.count - 1] = .tools(start: start, rows: rows + [row])
                } else {
                    items.append(.tools(start: index, rows: [row]))
                }
            case .thinking:
                guard showThinking else { continue }
                items.append(.thinking(start: index, text: entry.text, tokens: entry.thinkingTokens,
                                       live: index == openThinking))
            default:
                items.append(.message(entry.kind, entry.text))
                // Typed while the agent was busy: say plainly when it will be read.
                if entry.midTurn {
                    items.append(.message(.system, "sent mid-turn; the agent reads it at its next step"))
                }
            }
        }
        return items
    }

    /// The first index at which two groupings differ, or nil when they are the same. The log
    /// re-renders only from there, so a tool row updating never redraws the whole conversation.
    static func firstChange(from old: [LogItem], to new: [LogItem]) -> Int? {
        for index in 0..<min(old.count, new.count) where old[index] != new[index] { return index }
        return old.count == new.count ? nil : min(old.count, new.count)
    }
}

/// Turns log items into attributed text. Every item ends with a thin spacer line.
enum LogRenderer {
    private static var toolFont: NSFont { TextSize.mono(.secondary) }

    static func render(_ item: LogItem, expanded: Bool, spinner: String = "⠋") -> NSAttributedString {
        let out = NSMutableAttributedString()
        switch item {
        case let .message(.assistant, text):
            out.append(Markdown.render(text))
        case let .message(.user, text):
            out.append(line(text, font: TextSize.font(.body, weight: .semibold), color: .controlAccentColor, spacing: TextSize.metric(8)))
        case let .message(.system, text):
            out.append(line("— " + text, font: TextSize.font(.secondary), color: .secondaryLabelColor, spacing: TextSize.metric(6)))
        case let .message(_, text):
            out.append(line("— " + text, font: TextSize.font(.secondary), color: .secondaryLabelColor, spacing: TextSize.metric(6)))
        case let .thinking(start, text, tokens, live):
            out.append(thinking(start: start, text: text, tokens: tokens, live: live, expanded: expanded, spinner: spinner))
        case let .tools(start, rows):
            // A long burst folds away, but never over the call running right now.
            let running = rows.last { $0.status == .running }
            if rows.count <= LogModel.inlineToolLimit || expanded {
                if rows.count > LogModel.inlineToolLimit { out.append(disclosure(start: start, rows: rows, expanded: true, spinner: spinner)) }
                let indent = rows.count > LogModel.inlineToolLimit ? TextSize.metric(17) : 0
                rows.forEach { out.append(toolLine($0, indent: indent, spinner: spinner)) }
            } else {
                out.append(disclosure(start: start, rows: rows, expanded: false, spinner: spinner))
                if let shown = running ?? rows.last { out.append(toolLine(shown, indent: TextSize.metric(17), spinner: spinner)) }
            }
        }
        out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: TextSize.metric(6))]))
        return out
    }

    /// The message being streamed, styled exactly like the entry that will replace it.
    static func renderStreaming(_ text: String) -> NSAttributedString {
        render(.message(.assistant, text), expanded: false)
    }

    // MARK: pieces

    private static func disclosure(start: Int, rows: [ToolRow], expanded: Bool, spinner: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: "⚙ \(rows.count) tool calls \(expanded ? "▾" : "▸")", attributes: [
            .font: TextSize.font(.secondary, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor,
            .link: Markdown.actionURL, .nookToggle: start])
        return paragraph(title, spacing: TextSize.metric(3), truncates: true)
    }

    private static func toolLine(_ row: ToolRow, indent: CGFloat, spinner: String) -> NSAttributedString {
        let mark: String
        let color: NSColor
        switch row.status {
        case .running: (mark, color) = (spinner, .labelColor)
        case .ok: (mark, color) = ("✓", .secondaryLabelColor)
        case .failed: (mark, color) = ("✕", .systemRed)
        }
        let single = row.line.replacingOccurrences(of: "\n", with: " ")
        let content = NSAttributedString(string: "\(mark) \(single)", attributes: [.font: toolFont, .foregroundColor: color])
        return paragraph(content, spacing: TextSize.metric(3), truncates: true, indent: indent)
    }

    /// Reasoning: dim, italic, behind a left rule, and folded away once the reply starts. The text
    /// is often withheld by the CLI, so the token count carries the line on its own.
    private static func thinking(start: Int, text: String, tokens: Int, live: Bool,
                                 expanded: Bool, spinner: String) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = live || expanded
        let size = TextSize.points(.secondary)
        let italic = NSFontManager.shared.convert(.systemFont(ofSize: size), toHaveTrait: .italicFontMask)
        let measure = tokens > 0 ? "\(tokens) tokens" : (trimmed.isEmpty ? "" : "\(trimmed.count) characters")
        let head = live ? "\(spinner) Thinking…" : "✲ Thought" + (measure.isEmpty ? "" : " · " + measure)
        let title = NSMutableAttributedString(string: head + (trimmed.isEmpty ? "" : open ? "  ▾" : "  ▸"), attributes: [
            .font: TextSize.font(.secondary, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor] as [NSAttributedString.Key: Any])
        if !trimmed.isEmpty {
            title.addAttributes([.link: Markdown.actionURL, .nookToggle: start],
                                range: NSRange(location: 0, length: title.length))
        }
        if live, !measure.isEmpty {
            title.append(NSAttributedString(string: "  " + measure, attributes: [
                .font: TextSize.font(.caption), .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        let out = NSMutableAttributedString()
        out.append(paragraph(title, spacing: TextSize.metric(3), truncates: true))
        guard open, !trimmed.isEmpty else { return out }
        let body = NSAttributedString(string: trimmed.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: [
            .font: italic, .foregroundColor: NSColor.tertiaryLabelColor])
        out.append(paragraph(body, spacing: TextSize.metric(6), truncates: false, indent: TextSize.metric(14)))
        return out
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
