import Foundation

enum AgentState: String {
    case idle, thinking, working, talking, alert, done, sleeping

    var busy: Bool { [.thinking, .working, .talking, .alert].contains(self) }
}

struct TranscriptEntry {
    enum Kind { case user, assistant, tool, system }
    let kind: Kind
    let text: String
}

struct PermissionRequest {
    let requestID: String
    let tool: String
    let summary: String
    let input: [String: Any]
}

/// One agent: a live `claude` process driven over its streaming JSON protocol,
/// or a scripted stand-in when `cwd` is nil (demo mode).
final class AgentSession {
    let id = UUID()
    let label: String
    let cwd: URL?

    private(set) var state: AgentState = .idle
    private(set) var bubble = ""
    private(set) var transcript: [TranscriptEntry] = []
    private(set) var pending: PermissionRequest?
    private(set) var costUSD = 0.0
    private(set) var model = ""
    var unread = 0

    // --- Contract for the UI; the engine fills these in. ---
    /// Claude Code's own session id, once known. Pass it back as `resume` to continue later.
    private(set) var sessionID: String?
    /// Assistant text of the message currently being streamed, empty between messages.
    private(set) var streamingText = ""
    /// One line describing how the last turn ended ("3 files changed, tests pass").
    private(set) var summary = ""
    /// Tokens in the context window, and the window's size.
    private(set) var contextTokens = 0
    private(set) var contextLimit = 200_000
    /// Uncommitted files in the working folder, if it is a git repository.
    private(set) var changedFiles = 0
    /// When the current turn began; nil while the agent is not working.
    private(set) var turnStarted: Date?

    /// Called on the main thread whenever anything visible changed.
    var onChange: (() -> Void)?

    /// Extra `claude` flags appended last; the headless engine test uses this to pick a cheap model.
    var extraArguments: [String] = []

    /// NOOK_LOG=1 prints every state change, for checking the engine without the UI.
    private static let logging = ProcessInfo.processInfo.environment["NOOK_LOG"] != nil

    /// Asks the agent to end each turn with a line the engine lifts out as `summary`.
    private static let summaryPrompt = """
        At the very end of the final message of every turn, add one last line of the form \
        `SUMMARY: <at most 12 words on how the turn ended>`. Plain text, no markdown, nothing after it.
        """
    private static let summaryTag = "SUMMARY:"
    private static let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                     "gif": "image/gif", "webp": "image/webp"]
    /// The API rejects larger images; those are passed by path instead.
    private static let imageByteLimit = 5_000_000
    private static let streamInterval = 1.0 / 15

    private var since = 0.0
    private var process: Process?
    private var stdin: FileHandle?

    private let resume: String?
    /// True from launch with `--resume` until the CLI proves the session exists (system/init).
    private var awaitingResume = false
    private var resumeFailed = false
    /// The user message the CLI has not reacted to yet, kept so it can be replayed if the process
    /// turns out to be gone (a failed resume, or a death just before the message was written).
    private var inFlight: [String: Any]?
    private var replayed = false
    private var interrupted = false

    private var streamRaw = ""
    private var lastStreamFlush = 0.0
    private var streamFlushScheduled = false
    private var turnSummary: String?
    private var lastAssistantText = ""

    init(label: String, cwd: URL?, resume: String? = nil) {
        self.label = label
        self.cwd = cwd
        self.resume = resume
    }

    // MARK: lifecycle

    func start() {
        guard let cwd, process == nil else { return }
        guard let claude = ClaudeLocator.path else {
            note("Could not find the `claude` command. Install Claude Code, then reopen this agent.")
            set(.sleeping)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--permission-prompt-tool", "stdio", "--include-partial-messages",
                         "--append-system-prompt", Self.summaryPrompt]
        // A session that died mid-conversation picks up where it left off.
        let resuming = resumeFailed ? sessionID : (sessionID ?? resume)
        if let resuming { arguments += ["--resume", resuming] }
        if let model = UserDefaults.standard.string(forKey: Prefs.model), !model.isEmpty {
            arguments += ["--model", model]
        }
        if UserDefaults.standard.bool(forKey: Prefs.alwaysAsk) {
            arguments += ["--settings", Prefs.alwaysAskSettings]
        }
        p.arguments = arguments + extraArguments
        p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        p.environment = env

        let (input, output, errors) = (Pipe(), Pipe(), Pipe())
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        // Lines are split and parsed off the main thread; tool results can be megabytes.
        let reader = LineReader()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let events = reader.feed(data)
            guard !events.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                events.forEach(self.handle)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.ended(proc) }
        }
        do {
            try p.run()
            process = p
            stdin = input.fileHandleForWriting
            awaitingResume = resuming != nil
            note(resuming == nil ? "Started in \(cwd.path)" : "Resuming in \(cwd.path)")
            refreshChangedFiles()
        } catch {
            note("Could not start claude: \(error.localizedDescription)")
            set(.sleeping)
        }
    }

    func stop() {
        try? stdin?.close()
        process?.terminate()
    }

    private func ended(_ proc: Process) {
        guard process === proc else { return }
        process = nil
        stdin = nil
        if awaitingResume { return startFresh() }
        if let replay = inFlight, !replayed {
            replayed = true
            start()
            if process != nil { return write(replay) }
        }
        let wasBusy = state.busy
        pending = nil
        inFlight = nil
        turnStarted = nil
        clearStream()
        if wasBusy { summary = "Session ended unexpectedly" }
        let remark = "Session ended (exit \(proc.terminationStatus))." + (wasBusy ? " Send a message to pick it back up." : "")
        transcript.append(.init(kind: .system, text: remark))
        set(.sleeping, bubble: wasBusy ? summary : "")
    }

    /// `--resume` named a session the CLI does not have: carry on in a new one and say so.
    private func startFresh() {
        awaitingResume = false
        resumeFailed = true
        let replay = inFlight
        if let old = process {
            process = nil
            stdin = nil
            old.terminate()
        }
        note("Could not resume the earlier session, so this is a fresh one.")
        start()
        if let replay, process != nil { write(replay) }
    }

    // MARK: user actions

    /// `attachments` are files (images included) the agent should look at with this message.
    func send(_ text: String, attachments: [URL] = []) {
        let names = attachments.map(\.lastPathComponent)
        transcript.append(.init(kind: .user, text: names.isEmpty ? text : "\(text) [\(names.joined(separator: ", "))]"))
        if cwd == nil {
            set(.thinking)
            return
        }
        if let old = process, !old.isRunning {
            // It died and its termination handler has not run yet; `ended` will ignore it now.
            process = nil
            stdin = nil
        }
        if process == nil { start() }
        guard process != nil else { return }
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": Self.content(text, attachments)]]
        inFlight = message
        replayed = false
        interrupted = false
        turnSummary = nil
        lastAssistantText = ""
        if turnStarted == nil { turnStarted = Date() }
        write(message)
        set(.thinking)
    }

    func answerPermission(allow: Bool) {
        guard let req = pending else { return }
        pending = nil
        let decision: [String: Any] = allow
            ? ["behavior": "allow", "updatedInput": req.input]
            : ["behavior": "deny", "message": "The user denied this request."]
        write(["type": "control_response",
               "response": ["subtype": "success", "request_id": req.requestID, "response": decision]])
        note(allow ? "Allowed \(req.tool)." : "Denied \(req.tool).")
        set(allow ? .working : .thinking, bubble: allow ? req.tool : "")
    }

    func interrupt() {
        guard process != nil, state.busy else { return }
        interrupted = true
        write(["type": "control_request", "request_id": UUID().uuidString, "request": ["subtype": "interrupt"]])
    }

    /// Demo and tests drive the avatar directly.
    func simulate(_ state: AgentState, text: String = "", log: TranscriptEntry.Kind? = nil, countsAsUnread: Bool = false) {
        if let log, !text.isEmpty { transcript.append(.init(kind: log, text: text)) }
        if countsAsUnread { unread += 1 }
        set(state, bubble: text)
    }

    /// State decay: finished and talking poses relax to idle, long idle falls asleep.
    func tick(_ dt: Double) {
        since += dt
        let limit: Double
        switch state {
        case .done: limit = 5
        case .talking: limit = 4 + Double(bubble.count) * 0.06
        case .idle: limit = 300
        default: return
        }
        if since > limit { set(state == .idle ? .sleeping : .idle) }
    }

    // MARK: protocol

    private func write(_ object: [String: Any]) {
        guard let stdin, let process, process.isRunning,
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        // SIGPIPE is ignored in main.swift, so a process that died under us is a thrown error, not a crash.
        try? stdin.write(contentsOf: data)
    }

    private func handle(_ event: [String: Any]) {
        let nested = event["parent_tool_use_id"] is String // a subagent's traffic, not this conversation's
        switch event["type"] as? String {
        case "system":
            guard event["subtype"] as? String == "init" else { return }
            awaitingResume = false
            inFlight = nil
            model = event["model"] as? String ?? model
            sessionID = event["session_id"] as? String ?? sessionID
            onChange?()
        case "stream_event":
            inFlight = nil
            guard !nested, let inner = event["event"] as? [String: Any] else { return }
            stream(inner)
        case "assistant":
            inFlight = nil
            let message = event["message"] as? [String: Any] ?? [:]
            if !nested, let usage = message["usage"] as? [String: Any] {
                let tokens = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                    .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
                if tokens > 0 { contextTokens = tokens }
            }
            for block in message["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "thinking":
                    if !nested { set(.thinking) }
                case "text":
                    guard !nested else { continue }
                    clearStream()
                    let (text, line) = Self.splitSummary(block["text"] as? String ?? "")
                    if let line { turnSummary = line }
                    guard !text.isEmpty else { continue }
                    lastAssistantText = text
                    transcript.append(.init(kind: .assistant, text: text))
                    unread += 1
                    set(.talking, bubble: text)
                case "tool_use":
                    let name = block["name"] as? String ?? "tool"
                    let brief = Self.brief(block["input"] as? [String: Any] ?? [:])
                    transcript.append(.init(kind: .tool, text: brief.isEmpty ? name : "\(name): \(brief)"))
                    if pending == nil { set(.working, bubble: name) }
                default:
                    break
                }
            }
        case "user":
            // Tool results coming back: the agent is reading them.
            if state == .working { set(.thinking) }
        case "control_request":
            control(event)
        case "control_cancel_request":
            // The CLI withdrew a question (the turn was interrupted, or a hook answered it).
            guard let req = pending, req.requestID == event["request_id"] as? String else { return }
            pending = nil
            set(.thinking)
        case "result":
            if awaitingResume, event["is_error"] as? Bool == true { return startFresh() }
            finish(event)
        default:
            break
        }
    }

    private func control(_ event: [String: Any]) {
        guard let rid = event["request_id"] as? String else { return }
        let request = event["request"] as? [String: Any] ?? [:]
        let subtype = request["subtype"] as? String ?? "unknown"
        guard subtype == "can_use_tool" else {
            // Hooks, MCP messages and the like are SDK host features Nook does not offer; say so rather than hang the CLI.
            write(["type": "control_response",
                   "response": ["subtype": "error", "request_id": rid, "error": "Nook does not handle \(subtype) requests."]])
            return
        }
        let tool = request["display_name"] as? String ?? request["tool_name"] as? String ?? "tool"
        let input = request["input"] as? [String: Any] ?? [:]
        let summary = Self.brief(input)
        pending = PermissionRequest(requestID: rid, tool: tool, summary: summary, input: input)
        transcript.append(.init(kind: .system, text: "Permission needed for \(tool): \(summary)"))
        unread += 1
        set(.alert, bubble: "Allow \(tool)? \(summary)")
    }

    private func finish(_ result: [String: Any]) {
        costUSD = result["total_cost_usd"] as? Double ?? costUSD
        sessionID = result["session_id"] as? String ?? sessionID
        if let usage = result["modelUsage"] as? [String: [String: Any]] {
            let window = usage[model]?["contextWindow"] as? Int
                ?? usage.values.compactMap { $0["contextWindow"] as? Int }.max()
            if let window, window > 0 { contextLimit = window }
        }
        let failed = result["is_error"] as? Bool ?? false
        var remark: String?
        if interrupted {
            summary = "Interrupted"
            remark = "Interrupted."
        } else if failed {
            summary = "Something went wrong"
            remark = "The turn ended with an error" + ((result["result"] as? String).map { ": " + $0.prefix(200) } ?? ".")
        } else {
            summary = turnSummary ?? Self.firstSentence(lastAssistantText)
        }
        interrupted = false
        pending = nil
        inFlight = nil
        turnStarted = nil
        clearStream()
        if let remark { transcript.append(.init(kind: .system, text: remark)) }
        set(.done, bubble: summary)
        refreshChangedFiles()
    }

    // MARK: streaming

    private func stream(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "content_block_start":
            if (event["content_block"] as? [String: Any])?["type"] as? String == "text" { streamRaw = "" }
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            guard delta["type"] as? String == "text_delta", let text = delta["text"] as? String else { return }
            streamRaw += text
            flushStream()
        default:
            break
        }
    }

    /// Publishes the streamed text at most `1 / streamInterval` times a second.
    private func flushStream() {
        let now = ProcessInfo.processInfo.systemUptime
        let wait = lastStreamFlush + Self.streamInterval - now
        if wait > 0 {
            guard !streamFlushScheduled else { return }
            streamFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.streamFlushScheduled = false
                if !self.streamRaw.isEmpty { self.flushStream() }
            }
            return
        }
        lastStreamFlush = now
        let visible = Self.hidingSummary(streamRaw)
        guard visible != streamingText else { return }
        streamingText = visible
        state = .talking
        bubble = visible
        since = 0
        onChange?()
    }

    private func clearStream() {
        streamRaw = ""
        streamingText = ""
    }

    // MARK: summary

    /// Splits a finished message into what the user reads and the `SUMMARY:` line, if it has one.
    private static func splitSummary(_ raw: String) -> (text: String, summary: String?) {
        var lines = raw.components(separatedBy: "\n")
        var found: String?
        if let i = lines.lastIndex(where: { marker($0) != nil }), let line = marker(lines[i]) {
            found = String(line.split(separator: " ").prefix(14).joined(separator: " "))
            lines.remove(at: i)
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, found?.isEmpty == false ? found : nil)
    }

    /// The summary's words if `line` is a summary line; tolerates markdown emphasis around the tag.
    private static func marker(_ line: String) -> String? {
        let bare = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t*_`>#-"))
        guard bare.hasPrefix(summaryTag) else { return nil }
        return bare.dropFirst(summaryTag.count).trimmingCharacters(in: CharacterSet(charactersIn: " \t*_`"))
    }

    /// Streaming view of a partial message: drops the summary line, even while it is still being typed.
    private static func hidingSummary(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        if let last = lines.last {
            let bare = last.trimmingCharacters(in: CharacterSet(charactersIn: " \t*_`>#-"))
            if !bare.isEmpty, bare.hasPrefix(summaryTag) || summaryTag.hasPrefix(bare) { lines.removeLast() }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstSentence(_ text: String) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? ""
        var sentence = line
        if let end = line.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            sentence = String(line[..<end.lowerBound])
        }
        let words = sentence.split(separator: " ")
        return words.prefix(12).joined(separator: " ") + (words.count > 12 ? "…" : "")
    }

    // MARK: attachments

    /// Images travel inline as base64 blocks; anything else is named by path for the agent to open itself.
    private static func content(_ text: String, _ attachments: [URL]) -> Any {
        guard !attachments.isEmpty else { return text }
        var images: [[String: Any]] = []
        var paths: [String] = []
        for url in attachments {
            if let type = imageTypes[url.pathExtension.lowercased()],
               let data = try? Data(contentsOf: url), data.count <= imageByteLimit {
                images.append(["type": "image",
                               "source": ["type": "base64", "media_type": type, "data": data.base64EncodedString()]])
            } else {
                paths.append(url.standardizedFileURL.path)
            }
        }
        var prose = text
        if !paths.isEmpty {
            prose += "\n\nAttached files (read them as needed):\n" + paths.map { "- \($0)" }.joined(separator: "\n")
        }
        return [["type": "text", "text": prose]] + images
    }

    // MARK: working folder

    /// Counts uncommitted files off the main thread; stays 0 when the folder is not a repository.
    private func refreshChangedFiles() {
        guard let cwd else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["status", "--porcelain"]
            git.currentDirectoryURL = cwd
            let out = Pipe()
            git.standardOutput = out
            git.standardError = FileHandle.nullDevice
            var count = 0
            if (try? git.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                git.waitUntilExit()
                if git.terminationStatus == 0 { count = data.split(separator: 0x0A).count }
            }
            DispatchQueue.main.async {
                guard let self, self.changedFiles != count else { return }
                self.changedFiles = count
                self.onChange?()
            }
        }
    }

    private static func brief(_ input: [String: Any]) -> String {
        for key in ["command", "file_path", "pattern", "url", "query", "description", "prompt"] {
            if let v = input[key] as? String { return String(v.prefix(80)) }
        }
        return ""
    }

    private func note(_ text: String) {
        transcript.append(.init(kind: .system, text: text))
        onChange?()
    }

    private func set(_ new: AgentState, bubble text: String = "") {
        if Self.logging {
            FileHandle.standardError.write(Data("[\(label)] \(new.rawValue) \(text.prefix(80)) unread=\(unread) pending=\(pending?.tool ?? "-")\n".utf8))
        }
        state = new
        bubble = text
        since = 0
        onChange?()
    }
}

/// Engine preferences.
private enum Prefs {
    /// Model name or alias passed as `--model`; unset means Claude Code's own default.
    static let model = "nook.model"
    /// When true, tools that change things always ask, even if the user's Claude Code settings allow them.
    static let alwaysAsk = "nook.alwaysAsk"
    static let alwaysAskSettings = #"{"permissions":{"ask":["Bash","Write","Edit","NotebookEdit"]}}"#
}

/// Splits the CLI's stdout into JSON lines on the pipe's reader thread. Lines that are not JSON objects are dropped.
private final class LineReader {
    private var buffer = Data()
    private var scanned = 0 // bytes already known to hold no newline, so long lines are not rescanned per chunk

    func feed(_ data: Data) -> [[String: Any]] {
        buffer.append(data)
        var events: [[String: Any]] = []
        var lineStart = 0
        while let newline = buffer[scanned...].firstIndex(of: 0x0A) {
            if let object = try? JSONSerialization.jsonObject(with: buffer[lineStart..<newline]) as? [String: Any] {
                events.append(object)
            }
            lineStart = newline + 1
            scanned = lineStart
        }
        if lineStart > 0 { buffer = Data(buffer[lineStart...]) } // re-based, so indices start at 0 again
        scanned = buffer.count
        return events
    }
}

/// Finds the user's own Claude Code install; the app only ever launches that unmodified binary.
enum ClaudeLocator {
    static let path: String? = {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let usual = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        for dir in fromPath + usual {
            let candidate = dir + "/claude"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }()
}
