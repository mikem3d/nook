import Foundation

/// Parsing and formatting for the chat input's `!` escape. Pure: no process, no UI, no defaults,
/// so all of it is covered by tests.
enum ShellCommand {
    /// What a line typed into the chat input means.
    enum Parsed: Equatable {
        /// Ordinary text for the agent; a leading `\!` has been unescaped.
        case message(String)
        /// A command for Nook to run itself.
        case run(String)
        /// A bare `!`: nothing to do.
        case nothing
    }

    /// Output kept per command. The tail is what the user wants, so the head is dropped.
    static let outputLimit = 256 * 1024
    /// One runaway line (a progress bar, a minified file) cannot be allowed to set the log's width.
    static let lineLimit = 4096
    /// How much of a result is worth sending to the model when the user shares it.
    static let shareLimit = 8 * 1024

    static func parse(_ raw: String) -> Parsed {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\\!") { return .message(String(text.dropFirst())) }
        guard text.hasPrefix("!") else { return .message(text) }
        let command = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? .nothing : .run(command)
    }

    // MARK: cd

    /// The destination of a command that is nothing but a `cd`. Each command runs in a fresh
    /// `$SHELL -lc`, so a `cd` would otherwise be forgotten; Nook keeps the folder itself instead.
    /// Anything compound (`cd x && ls`) is left to the shell, where the `cd` is local to that line.
    static func cdArgument(_ command: String) -> String? {
        let text = command.trimmingCharacters(in: .whitespaces)
        guard text == "cd" || text.hasPrefix("cd ") else { return nil }
        let rest = String(text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !rest.contains(where: { ";&|\n<>`$()".contains($0) }) else { return nil }
        return unquote(rest)
    }

    private static func unquote(_ text: String) -> String {
        if text.count >= 2, let first = text.first, first == "\"" || first == "'", text.last == first {
            return String(text.dropFirst().dropLast())
        }
        return text.replacingOccurrences(of: "\\ ", with: " ")
    }

    /// Where a `cd` argument lands. nil when there is nowhere to go (`cd -` with no previous folder).
    static func resolve(_ argument: String, from base: URL, home: URL, previous: URL? = nil) -> URL? {
        if argument.isEmpty || argument == "~" { return home }
        if argument == "-" { return previous }
        var path = argument
        if path == "~" || path.hasPrefix("~/") { path = home.path + String(path.dropFirst(1)) }
        let joined = path.hasPrefix("/") ? path : base.path + "/" + path
        return URL(fileURLWithPath: (joined as NSString).standardizingPath)
    }

    // MARK: limits

    /// The last `limit` bytes of `text`, cut on a character boundary. `dropped` says whether
    /// anything was thrown away, so the block can mark the cut.
    static func tail(_ text: String, limit: Int) -> (text: String, dropped: Bool) {
        guard text.utf8.count > limit else { return (text, false) }
        var kept = 0
        var start = text.endIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            let size = String(text[previous]).utf8.count
            if kept + size > limit { break }
            kept += size
            start = previous
        }
        return (String(text[start...]), true)
    }

    /// Caps every line at `limit` characters, marking each cut. `column` is how far into a line
    /// the previous chunk left off; the returned column continues it, so a line split across
    /// chunks is still capped as one line. A column past `limit` means "swallowing this line".
    static func clamp(_ text: String, column: Int, limit: Int = lineLimit) -> (text: String, column: Int) {
        guard !text.isEmpty else { return (text, column) }
        var out = ""
        out.reserveCapacity(text.count)
        var column = column
        for character in text {
            if character == "\n" {
                out.append(character)
                column = 0
            } else if column < limit {
                out.append(character)
                column += 1
            } else if column == limit {
                out.append("…")
                column += 1
            }
        }
        return (out, column)
    }

    // MARK: sharing

    /// The message sent to the agent when the user shares a result. The agent sees nothing of a
    /// command until this is built, so it says plainly where the text came from.
    static func shareMessage(command: String, directory: String, exitCode: Int32, output: String,
                             limit: Int = shareLimit) -> String {
        let cut = tail(output, limit: limit)
        var body = cut.text
        if cut.dropped { body = "…earlier output trimmed…\n" + body }
        if !body.isEmpty, !body.hasSuffix("\n") { body += "\n" }
        let fence = self.fence(around: body + command)
        return """
            I ran this myself in \(directory) — output from my machine, not from you:

            \(fence)console
            $ \(command)
            \(body)[exit \(exitCode)]
            \(fence)
            """
    }

    /// A fence long enough that nothing inside the block can close it early.
    private static func fence(around text: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return String(repeating: "`", count: max(3, longest + 1))
    }
}
