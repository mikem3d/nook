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

    /// NOOK_LOG=1 prints every state change, for checking the engine without the UI.
    private static let logging = ProcessInfo.processInfo.environment["NOOK_LOG"] != nil

    private var since = 0.0
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()

    private let resume: String?

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
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--permission-prompt-tool", "stdio"]
        p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        p.environment = env

        let (input, output, errors) = (Pipe(), Pipe(), Pipe())
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.process = nil
                self?.stdin = nil
                self?.note("Session ended (exit \(proc.terminationStatus)).")
                self?.set(.sleeping)
            }
        }
        do {
            try p.run()
            process = p
            stdin = input.fileHandleForWriting
            note("Started in \(cwd.path)")
        } catch {
            note("Could not start claude: \(error.localizedDescription)")
            set(.sleeping)
        }
    }

    func stop() {
        try? stdin?.close()
        process?.terminate()
    }

    // MARK: user actions

    /// `attachments` are files (images included) the agent should look at with this message.
    func send(_ text: String, attachments: [URL] = []) {
        transcript.append(.init(kind: .user, text: text))
        if cwd == nil {
            set(.thinking)
            return
        }
        if process == nil { start() }
        write(["type": "user", "message": ["role": "user", "content": text]])
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
        guard let stdin, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? stdin.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(object)
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "system":
            if event["subtype"] as? String == "init" {
                model = event["model"] as? String ?? ""
                onChange?()
            }
        case "assistant":
            let message = event["message"] as? [String: Any]
            for block in message?["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "thinking":
                    set(.thinking)
                case "text":
                    let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    transcript.append(.init(kind: .assistant, text: text))
                    unread += 1
                    set(.talking, bubble: text)
                case "tool_use":
                    let name = block["name"] as? String ?? "tool"
                    let brief = Self.brief(block["input"] as? [String: Any] ?? [:])
                    transcript.append(.init(kind: .tool, text: brief.isEmpty ? name : "\(name): \(brief)"))
                    set(.working, bubble: name)
                default:
                    break
                }
            }
        case "user":
            // Tool results coming back: the agent is reading them.
            if state == .working { set(.thinking) }
        case "control_request":
            let request = event["request"] as? [String: Any] ?? [:]
            guard request["subtype"] as? String == "can_use_tool", let rid = event["request_id"] as? String else { return }
            let tool = request["tool_name"] as? String ?? "tool"
            let input = request["input"] as? [String: Any] ?? [:]
            let summary = Self.brief(input)
            pending = PermissionRequest(requestID: rid, tool: tool, summary: summary, input: input)
            transcript.append(.init(kind: .system, text: "Permission needed for \(tool): \(summary)"))
            unread += 1
            set(.alert, bubble: "Allow \(tool)? \(summary)")
        case "result":
            costUSD = event["total_cost_usd"] as? Double ?? costUSD
            let failed = event["is_error"] as? Bool ?? false
            if failed { note("The turn ended with an error.") }
            set(.done, bubble: failed ? "Something went wrong." : bubble)
        default:
            break
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
