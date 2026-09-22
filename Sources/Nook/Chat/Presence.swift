import Foundation

/// Everything the "present" chat needs that is pure: how a tool call reads while it is still
/// arriving, what its result amounted to, what the agent is doing in plain words, and the queue
/// for text typed while the agent cannot take it. Kept free of AppKit so it is all unit tested.

// MARK: tool rows

enum ToolStatus: Equatable { case running, ok, failed }

/// One tool call as the log shows it: created the moment the call starts forming, its argument
/// filled in as the partial JSON arrives, and finished with whatever the result carried.
struct ToolRow: Equatable {
    var id: String
    var name: String
    /// The command, path or pattern: the one argument worth reading, as far as it has streamed.
    var argument = ""
    var status = ToolStatus.running
    /// What came back: "4 lines", "exit 0", "no output", "failed: …".
    var detail = ""

    /// The row without its status marker: "Bash  ls -la ." or, once back, with the result appended.
    var line: String {
        var out = name
        if !argument.isEmpty { out += "  " + argument.replacingOccurrences(of: "\n", with: " ") }
        if !detail.isEmpty { out += "  · " + detail }
        return out
    }
}

// MARK: partial JSON

/// Reads the one argument worth showing out of a tool call's input while it is still streaming.
enum PartialJSON {
    /// In the order we would rather show them: what the user most wants to see first.
    static let keys = ["command", "file_path", "path", "pattern", "url", "query", "prompt", "description"]

    /// The first interesting argument in `partial`, which may be a complete JSON object or a
    /// fragment cut anywhere — including inside the value, which then yields what has arrived.
    static func argument(_ partial: String) -> String {
        if let data = partial.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in keys {
                if let value = object[key] as? String { return value }
            }
            return ""
        }
        for key in keys {
            if let value = scan(key, in: partial) { return value }
        }
        return ""
    }

    /// Finds `"key": "…"` by hand and decodes the escapes it understands, stopping wherever the
    /// fragment stops. Returns nil when the key has not arrived yet.
    private static func scan(_ key: String, in partial: String) -> String? {
        guard let keyRange = partial.range(of: "\"\(key)\"") else { return nil }
        var index = keyRange.upperBound
        // past the colon and any spaces, to the opening quote
        while index < partial.endIndex, partial[index] == " " || partial[index] == ":" { index = partial.index(after: index) }
        guard index < partial.endIndex, partial[index] == "\"" else { return nil }
        index = partial.index(after: index)
        var out = ""
        while index < partial.endIndex {
            let character = partial[index]
            index = partial.index(after: index)
            if character == "\"" { return out }
            guard character == "\\" else {
                out.append(character)
                continue
            }
            guard index < partial.endIndex else { return out } // cut mid-escape
            let escape = partial[index]
            index = partial.index(after: index)
            switch escape {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "u":
                let digits = partial[index...].prefix(4)
                guard digits.count == 4, let code = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(code) else { return out }
                out.append(Character(scalar))
                index = partial.index(index, offsetBy: 4)
            default: out.append(escape) // \" \\ \/ and anything else stands for itself
            }
        }
        return out // the value is still being typed
    }
}

// MARK: results

/// Turns a `tool_use_result` into one substantive line: what came back, or how it failed.
enum ToolReport {
    static func summarise(name: String, result: Any?, failed: Bool, content: String = "") -> String {
        guard failed else {
            let body = detail(name: name, result: result, content: content)
            return body.isEmpty ? "done" : body
        }
        // A failure is worth its own words, not a line count.
        let said = problem(result: result, content: content)
        return "failed" + (said.isEmpty ? "" : ": " + said)
    }

    /// What the tool complained about: whichever of its channels actually said something.
    private static func problem(result: Any?, content: String) -> String {
        var candidates: [String] = []
        if let text = result as? String { candidates.append(text) }
        if let result = result as? [String: Any] {
            candidates += ["stderr", "error", "message", "content", "stdout"].compactMap { result[$0] as? String }
        }
        candidates.append(content)
        guard let said = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return "" }
        // The CLI puts the exit status on its own first line, so keep the line that says why too.
        let lines = said.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.prefix(2).joined(separator: " · ").prefix(100).description
    }

    private static func detail(name: String, result: Any?, content: String) -> String {
        if let text = result as? String { return text.isEmpty ? "no output" : size(text) }
        guard let result = result as? [String: Any] else {
            if let list = result as? [Any] { return count(list.count, "block") }
            return content.isEmpty ? "" : size(content)
        }
        // A shell command: what it printed, or what it complained about.
        if let stdout = result["stdout"] as? String {
            if result["interrupted"] as? Bool == true { return "interrupted" }
            let stderr = (result["stderr"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stderr.isEmpty ? "no output" : firstLine(stderr)
            }
            return size(stdout) + (stderr.isEmpty ? "" : ", stderr")
        }
        // A file read.
        if let file = result["file"] as? [String: Any] {
            if let lines = file["numLines"] as? Int { return count(lines, "line") }
            if let text = file["content"] as? String { return size(text) }
        }
        // A search.
        if let files = result["numFiles"] as? Int {
            if let matches = result["numLines"] as? Int, matches > 0 { return count(matches, "match", plural: "matches") }
            return count((result["filenames"] as? [Any])?.count ?? files, "file")
        }
        if let names = result["filenames"] as? [Any] { return count(names.count, "file") }
        if let lines = result["numLines"] as? Int { return count(lines, "line") }
        // A write or an edit.
        if let patch = result["structuredPatch"] as? [Any] { return count(patch.count, "hunk") }
        if let path = result["filePath"] as? String {
            let verb = result["type"] as? String == "create" ? "created " : "wrote "
            return verb + (path as NSString).lastPathComponent
        }
        if let todos = result["newTodos"] as? [Any] { return count(todos.count, "task") }
        if let text = result["content"] as? String { return text.isEmpty ? "no output" : size(text) }
        return content.isEmpty ? "" : size(content)
    }

    /// Lines when there are a few, bytes when it is one long blob.
    private static func size(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        if lines > 1 { return count(text.hasSuffix("\n") ? lines - 1 : lines, "line") }
        let bytes = text.utf8.count
        return bytes > 200 ? "\(bytes) bytes" : "1 line"
    }

    private static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? noun : plural ?? noun + "s")
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }
}

// MARK: activity

/// What the agent is doing right now, as the activity line and the avatar read it.
enum ActivityPhase: Equatable {
    case idle
    /// Sent, nothing back from the CLI yet.
    case sending
    case thinking(tokens: Int)
    case running(tool: String, argument: String)
    case approval(tool: String)
    case replying

    /// Plain words: "Thinking…", "Reading lookup.ts…", "Waiting for approval…".
    var words: String {
        switch self {
        case .idle: return ""
        case .sending: return "Sending…"
        case let .thinking(tokens): return tokens > 0 ? "Thinking… \(tokens) tokens" : "Thinking…"
        case let .running(tool, argument): return Activity.verb(tool: tool, argument: argument)
        case let .approval(tool): return "Waiting for approval: \(tool)"
        case .replying: return "Replying…"
        }
    }

    /// The avatar's pose for this phase. `nil` leaves the state alone.
    var state: AgentState? {
        switch self {
        case .idle: return nil
        case .sending, .thinking: return .thinking
        case .running: return .working
        case .approval: return .alert
        case .replying: return .talking
        }
    }
}

enum Activity {
    /// A calm braille spinner; one frame every 100 ms.
    static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    static let interval = 0.1

    static func frame(at time: Double) -> String {
        frames[Int(time / interval) % frames.count]
    }

    /// "Reading lookup.ts…". Tools we know get a verb; the rest are named plainly.
    static func verb(tool: String, argument: String) -> String {
        let what = shorten(argument)
        let verb: String
        switch tool {
        case "Read", "NotebookRead": verb = "Reading"
        case "Write": verb = "Writing"
        case "Edit", "MultiEdit", "NotebookEdit": verb = "Editing"
        case "Bash", "BashOutput": verb = "Running"
        case "Grep": verb = "Searching for"
        case "Glob": verb = "Looking for"
        case "WebFetch": verb = "Fetching"
        case "WebSearch": verb = "Searching the web for"
        case "Task": verb = "Running a subagent"
        case "TodoWrite": return "Updating its plan…"
        default: return what.isEmpty ? "Using \(tool)…" : "\(tool): \(what)…"
        }
        return what.isEmpty ? "\(verb)…" : "\(verb) \(what)…"
    }

    /// Paths keep their last two components; anything long is cut with an ellipsis.
    static func shorten(_ argument: String, limit: Int = 46) -> String {
        var text = argument.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if text.count > limit, text.contains("/"), !text.contains(" ") {
            let parts = text.split(separator: "/")
            text = parts.suffix(2).joined(separator: "/")
            if parts.count > 2 { text = "…/" + text }
        }
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    /// "4s", then "1:05" past a minute.
    static func elapsed(_ seconds: Double) -> String {
        let whole = max(Int(seconds), 0)
        return whole < 60 ? "\(whole)s" : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The whole line, as the tests read it: spinner, phase, clock, hint.
    static func line(phase: ActivityPhase, seconds: Double, at time: Double, hint: String = "⌘. to stop") -> String {
        [frame(at: time), phase.words, elapsed(seconds), hint].filter { !$0.isEmpty }.joined(separator: "  ")
    }
}

// MARK: type-ahead

/// A message typed while the agent could not take it yet. It is never lost and can be cancelled
/// until it goes. See `AgentSession.send` for when this happens: only while a permission question
/// is open, because the CLI cannot read stdin until it is answered.
struct QueuedMessage: Equatable {
    let id: UUID
    var text: String
    var attachments: [URL]

    init(id: UUID = UUID(), text: String, attachments: [URL] = []) {
        (self.id, self.text, self.attachments) = (id, text, attachments)
    }
}

struct MessageQueue: Equatable {
    private(set) var items: [QueuedMessage] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func append(_ message: QueuedMessage) { items.append(message) }

    @discardableResult
    mutating func cancel(_ id: UUID) -> Bool {
        let before = items.count
        items.removeAll { $0.id == id }
        return items.count != before
    }

    /// Hands over everything waiting, oldest first, and empties the queue.
    mutating func take() -> [QueuedMessage] {
        defer { items = [] }
        return items
    }
}
