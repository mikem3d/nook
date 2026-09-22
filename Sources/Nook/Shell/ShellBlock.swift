import AppKit

extension NSAttributedString.Key {
    /// On a shell block's buttons. Value: a `ShellAction`.
    static let nookShell = NSAttributedString.Key("nook.shell")
}

/// A clickable affordance inside a shell result block.
final class ShellAction: NSObject {
    enum Kind { case stop, share, expand, autoShare }
    let kind: Kind
    let run: ShellRun

    init(_ kind: Kind, _ run: ShellRun) {
        self.kind = kind
        self.run = run
    }
}

/// Draws one shell result: the command, where and how long it ran, its output, and the buttons
/// that stop it or hand it to the agent. Monospaced throughout, so it reads as a terminal and
/// never as something the agent said.
enum ShellBlock {
    /// A long result is clamped to its tail until the user asks for all of it.
    static let collapsedLines = 24

    static func render(_ run: ShellRun) -> NSAttributedString {
        let scale = TextSize.current
        let out = NSMutableAttributedString()
        let failed = run.failed

        // The command itself, prominent.
        let head = NSMutableAttributedString(string: "❯ ", attributes: [
            .font: TextSize.mono(.code, weight: .bold), .foregroundColor: NSColor.tertiaryLabelColor])
        head.append(NSAttributedString(string: run.command.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: [
            .font: TextSize.mono(.code, weight: .semibold),
            .foregroundColor: failed ? NSColor.systemRed : NSColor.labelColor]))
        out.append(paragraph(head, before: scale.metric(8), after: scale.metric(2)))

        out.append(paragraph(meta(run), after: scale.metric(4)))
        out.append(body(run))
        if let footer = footer(run) { out.append(paragraph(footer, after: scale.metric(6))) }
        return out
    }

    // MARK: pieces

    /// Where it ran, how long it took, how it ended, and whether it seems stuck.
    private static func meta(_ run: ShellRun) -> NSAttributedString {
        let font = TextSize.font(.caption)
        let line = NSMutableAttributedString()
        func add(_ text: String, _ colour: NSColor) {
            if line.length > 0 {
                line.append(NSAttributedString(string: "  ·  ", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
            }
            line.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour]))
        }
        if run.showsDirectory { add(abbreviate(run.directory), .secondaryLabelColor) }
        if run.isRunning {
            add(run.stopping ? "stopping…" : String(format: "running  %.0fs", run.elapsed), .secondaryLabelColor)
            line.append(NSAttributedString(string: "  ·  ", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
            line.append(button("Stop", .stop, run))
            if run.isStalled {
                add("still running with no output — no terminal here, so it may be waiting for input. Stop?", .systemOrange)
            }
        } else {
            add(duration(run.duration), .secondaryLabelColor)
            if let code = run.exitCode, code != 0 { add("exit \(code)", .systemRed) }
        }
        return line
    }

    /// The output, clamped to its tail unless the user expanded it.
    private static func body(_ run: ShellRun) -> NSAttributedString {
        let scale = TextSize.current
        let mono = TextSize.mono(.secondary)
        let out = NSMutableAttributedString()
        let lines = self.lines(of: run)
        let hidden = run.expanded ? 0 : max(0, lines.count - collapsedLines)

        if run.dropped || hidden > 0 {
            let note = run.dropped ? "earlier output dropped (kept the last \(ShellCommand.outputLimit / 1024) KB)" : ""
            let head = NSMutableAttributedString()
            if hidden > 0 {
                head.append(button("… \(hidden) earlier line\(hidden == 1 ? "" : "s") — show all", .expand, run))
            } else if run.expanded, lines.count > collapsedLines {
                head.append(button("… show less", .expand, run))
            }
            if !note.isEmpty {
                if head.length > 0 { head.append(NSAttributedString(string: "  ·  ", attributes: [.font: TextSize.font(.caption), .foregroundColor: NSColor.tertiaryLabelColor])) }
                head.append(NSAttributedString(string: note, attributes: [.font: TextSize.font(.caption), .foregroundColor: NSColor.tertiaryLabelColor]))
            }
            if head.length > 0 { out.append(paragraph(head, indent: scale.metric(12), after: scale.metric(2))) }
        } else if run.expanded, lines.count > collapsedLines {
            out.append(paragraph(button("… show less", .expand, run), indent: scale.metric(12), after: scale.metric(2)))
        }

        let shown = hidden > 0 ? Array(lines.suffix(collapsedLines)) : lines
        if shown.isEmpty, !run.isRunning {
            out.append(paragraph(NSAttributedString(string: "no output", attributes: [
                .font: TextSize.font(.caption), .foregroundColor: NSColor.tertiaryLabelColor]), indent: scale.metric(12), after: scale.metric(2)))
            return out
        }
        let text = NSMutableAttributedString()
        for (index, line) in shown.enumerated() {
            text.append(NSAttributedString(string: line.text + (index == shown.count - 1 ? "\n" : "\u{2028}"), attributes: [
                .font: mono, .foregroundColor: line.isError ? NSColor.systemOrange : NSColor.labelColor]))
        }
        let style = NSMutableParagraphStyle()
        let inset = scale.metric(12)
        style.firstLineHeadIndent = inset
        style.headIndent = inset
        style.tailIndent = -inset
        style.paragraphSpacing = scale.metric(6)
        style.lineBreakMode = .byCharWrapping
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        // The log's layout manager draws the rounded box behind this; the value is per-run so two
        // blocks in a row do not merge into one box.
        text.addAttribute(.nookCode, value: "shell-" + run.id.uuidString, range: NSRange(location: 0, length: text.length))
        out.append(text)
        return out
    }

    /// Sharing is the only thing that puts output in front of the model, so it says so plainly.
    private static func footer(_ run: ShellRun) -> NSAttributedString? {
        guard !run.isRunning else { return nil }
        let font = TextSize.font(.caption)
        let line = NSMutableAttributedString()
        if run.shared {
            line.append(NSAttributedString(string: "Sent to the agent", attributes: [
                .font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        } else {
            line.append(button("Share with agent", .share, run))
            line.append(NSAttributedString(string: "  (the agent has not seen this)", attributes: [
                .font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        line.append(NSAttributedString(string: "  ·  ", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        line.append(button(ShellPrefs.autoShareEnabled ? "auto-share: on" : "auto-share: off", .autoShare, run))
        return line
    }

    // MARK: helpers

    private static func button(_ title: String, _ kind: ShellAction.Kind, _ run: ShellRun) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: TextSize.font(.caption, weight: .medium),
            .foregroundColor: kind == .stop ? NSColor.systemRed : NSColor.secondaryLabelColor,
            .link: Markdown.actionURL, .nookShell: ShellAction(kind, run)])
    }

    /// Output as display lines. A line carrying anything from stderr is marked as one.
    static func lines(of run: ShellRun) -> [(isError: Bool, text: String)] {
        var lines: [(isError: Bool, text: String)] = []
        var open = false // the last line has no newline yet, so the next chunk continues it
        for chunk in run.chunks {
            var pieces = chunk.text.components(separatedBy: "\n")
            let terminated = pieces.count > 1 && pieces[pieces.count - 1].isEmpty
            if terminated { pieces.removeLast() } // the split's artefact, not a blank line
            for (index, piece) in pieces.enumerated() {
                if index == 0, open, !lines.isEmpty {
                    lines[lines.count - 1].text += piece
                    lines[lines.count - 1].isError = lines[lines.count - 1].isError || chunk.isError
                } else {
                    lines.append((chunk.isError, piece))
                }
            }
            open = !terminated
        }
        return lines
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        seconds < 10 ? String(format: "%.2fs", seconds) : String(format: "%.1fs", seconds)
    }

    private static func abbreviate(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func paragraph(_ content: NSAttributedString, indent: CGFloat = 0,
                                  before: CGFloat = 0, after: CGFloat = 0) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: content)
        let attributes = out.length > 0 ? out.attributes(at: out.length - 1, effectiveRange: nil) : [:]
        out.append(NSAttributedString(string: "\n", attributes: attributes))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        let newline = NSRange(location: out.length - 1, length: 1)
        out.removeAttribute(.link, range: newline)
        out.removeAttribute(.nookShell, range: newline)
        return out
    }
}
