import AppKit

/// The block structure of a message. Parsing is separate from styling so it can be tested headless.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(level: Int, text: String)
    case numbered(level: Int, marker: String, text: String)
    case code(language: String, text: String)
    case rule
}

extension NSAttributedString.Key {
    /// Covers a whole fenced code block; the log's layout manager draws the rounded background behind it.
    static let nookCode = NSAttributedString.Key("nook.code")
    /// On a code block's "Copy" affordance. Value: the code to copy.
    static let nookCopy = NSAttributedString.Key("nook.copy")
    /// On a tool group's disclosure line. Value: the group's start index in the transcript.
    static let nookToggle = NSAttributedString.Key("nook.toggle")
}

/// Lightweight Markdown for assistant text: blocks are parsed by hand (fences included, even
/// unterminated ones, so a streaming message renders sensibly), inline syntax by Foundation.
enum Markdown {
    /// Placeholder link target for in-log actions; the real payload is in a `nook*` attribute.
    static let actionURL = URL(string: "nook:action")!

    // MARK: blocks

    static func blocks(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            i += 1
            if let fence = fence(trimmed) {
                flush()
                var code: [String] = []
                while i < lines.count, !closes(lines[i], fence: fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // the closing fence, or past the end while still streaming
                let language = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flush()
            } else if let heading = heading(trimmed) {
                flush()
                blocks.append(heading)
            } else if isRule(trimmed) {
                flush()
                blocks.append(.rule)
            } else if let item = listItem(line) {
                flush()
                blocks.append(item)
            } else if paragraph.isEmpty, line.hasPrefix("  ") || line.hasPrefix("\t"), let last = blocks.last, let joined = continuing(last, with: trimmed) {
                blocks[blocks.count - 1] = joined
            } else {
                paragraph.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    private static func fence(_ trimmed: String) -> String? {
        for mark in ["`", "~"] as [Character] {
            let run = trimmed.prefix { $0 == mark }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    private static func closes(_ line: String, fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(fence) && trimmed.allSatisfy { $0 == fence.first }
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        let rest = trimmed.dropFirst(hashes.count)
        guard (1...6).contains(hashes.count), rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return .heading(level: hashes.count, text: text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let width = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let level = min(width / 2, 4)
        let body = line.dropFirst(indent.count)
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            return .bullet(level: level, text: body.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        let digits = body.prefix { $0.isASCII && $0.isNumber }
        let after = body.dropFirst(digits.count)
        if (1...9).contains(digits.count), let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " {
            return .numbered(level: level, marker: "\(digits).", text: after.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// An indented line directly under a list item belongs to that item.
    private static func continuing(_ block: MarkdownBlock, with text: String) -> MarkdownBlock? {
        switch block {
        case let .bullet(level, body): return .bullet(level: level, text: body + "\n" + text)
        case let .numbered(level, marker, body): return .numbered(level: level, marker: marker, text: body + "\n" + text)
        default: return nil
        }
    }

    // MARK: styling

    /// Sizes and spacing follow the text-size setting; `scale` maps the numbers below, written for `medium`.
    static func render(_ source: String, color: NSColor = .labelColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let scale = TextSize.current
        let body = NSFont.systemFont(ofSize: scale.points(.body))
        for block in blocks(source) {
            switch block {
            case let .paragraph(text):
                out.append(styled(inline(text, font: body, color: color), spacing: scale.metric(8)))
            case let .heading(level, text):
                let bump: CGFloat = level == 1 ? 6 : level == 2 ? 4 : level == 3 ? 2 : 0
                let font = NSFont.systemFont(ofSize: scale.points(TextSize.Role.body.base + bump), weight: level <= 2 ? .bold : .semibold)
                out.append(styled(inline(text, font: font, color: color), spacing: scale.metric(7), before: out.length == 0 ? 0 : scale.metric(6)))
            case let .bullet(level, text):
                out.append(listItem("•", text, level: level, markerWidth: scale.metric(17), font: body, color: color))
            case let .numbered(level, marker, text):
                out.append(listItem(marker, text, level: level, markerWidth: scale.metric(30), font: body, color: color))
            case let .code(language, text):
                out.append(codeBlock(language: language, code: text))
            case .rule:
                let line = NSAttributedString(string: "———", attributes: [.font: body, .foregroundColor: NSColor.tertiaryLabelColor])
                out.append(styled(line, spacing: scale.metric(8)))
            }
        }
        return out
    }

    /// Terminates a block with a newline and gives it paragraph spacing. Soft line breaks become
    /// U+2028 so they stay inside the one paragraph.
    private static func styled(_ text: NSAttributedString, spacing: CGFloat, before: CGFloat = 0,
                               configure: ((NSMutableParagraphStyle) -> Void)? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: text)
        out.mutableString.replaceOccurrences(of: "\n", with: "\u{2028}", options: [], range: NSRange(location: 0, length: out.length))
        let last = out.length > 0 ? out.attributes(at: out.length - 1, effectiveRange: nil) : [:]
        out.append(NSAttributedString(string: "\n", attributes: [.font: last[.font] ?? TextSize.font(.body)]))
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = before
        style.lineSpacing = TextSize.metric(2)
        configure?(style)
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return out
    }

    private static func listItem(_ marker: String, _ text: String, level: Int, markerWidth: CGFloat,
                                 font: NSFont, color: NSColor) -> NSAttributedString {
        let line = NSMutableAttributedString(string: marker + "\t", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        line.append(inline(text, font: font, color: color))
        let indent = TextSize.metric(5) + CGFloat(level) * TextSize.metric(20)
        return styled(line, spacing: TextSize.metric(4)) { style in
            style.firstLineHeadIndent = indent
            style.headIndent = indent + markerWidth
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
        }
    }

    private static func codeBlock(language: String, code: String) -> NSAttributedString {
        let scale = TextSize.current
        let inset = scale.metric(12)
        func style(before: CGFloat = 0, after: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = inset
            style.headIndent = inset
            style.tailIndent = -inset
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.lineBreakMode = .byCharWrapping
            return style
        }
        let small = TextSize.font(.caption, weight: .medium)
        let out = NSMutableAttributedString()
        if !language.isEmpty {
            out.append(NSAttributedString(string: language + "   ", attributes: [.font: small, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        out.append(NSAttributedString(string: "Copy", attributes: [
            .font: small, .foregroundColor: NSColor.secondaryLabelColor, .link: actionURL, .nookCopy: code]))
        out.append(NSAttributedString(string: "\n", attributes: [.font: small]))
        out.addAttribute(.paragraphStyle, value: style(before: scale.metric(7), after: scale.metric(4)), range: NSRange(location: 0, length: out.length))

        let mono = TextSize.mono(.code)
        let bodyStart = out.length
        out.append(NSAttributedString(string: code + "\n", attributes: [.font: mono, .foregroundColor: NSColor.labelColor, .paragraphStyle: style()]))
        let lastLine = (code as NSString).range(of: "\n", options: .backwards)
        let lastStart = bodyStart + (lastLine.location == NSNotFound ? 0 : lastLine.location + 1)
        out.addAttribute(.paragraphStyle, value: style(after: scale.metric(8)), range: NSRange(location: lastStart, length: out.length - lastStart))
        out.addAttribute(.nookCode, value: code, range: NSRange(location: 0, length: out.length))
        // A sliver of a line outside the box, so the next block does not butt against it.
        out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: scale.metric(6))]))
        return out
    }

    // MARK: inline

    static func inline(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            let intent = run.inlinePresentationIntent ?? []
            var face = font
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.code) {
                face = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                traits = face.fontDescriptor.symbolicTraits
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor
            }
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            attributes[.font] = NSFont(descriptor: face.fontDescriptor.withSymbolicTraits(traits), size: face.pointSize) ?? face
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let url = run.link {
                attributes[.link] = url
                attributes[.foregroundColor] = NSColor.linkColor
            }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        linkBareURLs(in: out)
        return out
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func linkBareURLs(in text: NSMutableAttributedString) {
        guard text.string.contains("://"), let detector else { return }
        for match in detector.matches(in: text.string, range: NSRange(location: 0, length: text.length)) {
            guard let url = match.url, url.scheme?.hasPrefix("http") == true,
                  text.attribute(.link, at: match.range.location, effectiveRange: nil) == nil,
                  text.attribute(.backgroundColor, at: match.range.location, effectiveRange: nil) == nil else { continue }
            text.addAttributes([.link: url, .foregroundColor: NSColor.linkColor], range: match.range)
        }
    }
}
