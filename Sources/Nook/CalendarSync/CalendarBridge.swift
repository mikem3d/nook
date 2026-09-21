import Foundation

/// Nook is not an MCP client. It reaches the user's calendar by running their own `claude` CLI as
/// a short headless job that may call nothing but the calendar tools named on its command line,
/// and must answer in a fixed JSON shape. Nothing leaves the machine except through that CLI.
///
/// One job at a time. A job runs in an empty temporary folder (no project settings, no CLAUDE.md,
/// no files to read), without built-in tools, in `dontAsk` mode with nobody answering permission
/// prompts, so anything not allowed by name is refused rather than asked about.
final class CalendarBridge {
    static let modelKey = "nook.calendar.model"
    /// A hard stop in case a job loops; a normal sync costs a small fraction of this.
    static let budgetUSD = "0.50"

    enum Failure: Error, Equatable {
        case noClaude, busy, cancelled, timedOut
        /// The CLI ran but gave nothing usable; the text is the CLI's own error subtype, never event data.
        case failed(String)

        var message: String {
            switch self {
            case .noClaude: return "Could not find the `claude` command."
            case .busy: return "A calendar job is already running."
            case .cancelled: return "Cancelled."
            case .timedOut: return "The calendar job took too long and was stopped."
            case .failed(let why): return "The calendar job failed (\(why))."
            }
        }
    }

    enum Job: Equatable {
        /// Costs next to nothing: stopped as soon as the CLI has listed its tools.
        case discover
        case list(DateInterval, CalendarTools)
        case create(EventDraft, CalendarTools)
    }

    /// Exactly what a write-back job is asked to create; the panel shows these same values first.
    struct EventDraft: Equatable {
        var title: String
        var start: Date
        var end: Date
        var notes: String
    }

    /// The user's `claude`; tests put a script in its place.
    private let executable: String?
    private var process: Process?
    private var timeout: DispatchWorkItem?
    private var stopped: Failure?

    init(executable: String? = ClaudeLocator.path) { self.executable = executable }

    var isRunning: Bool { process != nil }

    /// Completes on the main queue.
    func run(_ job: Job, timeout seconds: TimeInterval = 240, completion: @escaping (Result<BridgeOutput, Failure>) -> Void) {
        guard process == nil else { return completion(.failure(.busy)) }
        guard let claude = executable else { return completion(.failure(.noClaude)) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-calendar-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = Self.arguments(for: job, model: UserDefaults.standard.string(forKey: Self.modelKey))
        p.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        p.environment = env
        let output = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice

        do { try p.run() } catch {
            try? FileManager.default.removeItem(at: folder)
            return completion(.failure(.failed("could not start")))
        }
        process = p
        stopped = nil
        let work = DispatchWorkItem { [weak self] in self?.stop(.timedOut) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)

        // Completion hangs off the process ending, not off the pipe closing: helper processes the
        // CLI starts inherit the pipe and can hold it open long after the CLI itself is gone.
        let discovering = job == .discover
        let collected = Collected()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return handle.readabilityHandler = nil }
            // Discovery needs the tool list only; stopping here means no turn is paid for.
            if collected.append(chunk, lookForTools: discovering) { kill(p.processIdentifier, SIGKILL) }
        }
        p.terminationHandler = { [weak self] _ in
            let handle = output.fileHandleForReading
            handle.readabilityHandler = nil
            try? FileManager.default.removeItem(at: folder)
            let parsed = BridgeOutput.parse(collected.data)
            DispatchQueue.main.async {
                guard let self else { return }
                self.timeout?.cancel()
                self.process = nil
                if let stopped = self.stopped { return completion(.failure(stopped)) }
                if discovering { return completion(parsed.tools == nil ? .failure(.failed("no tool list")) : .success(parsed)) }
                if let error = parsed.error { return completion(.failure(.failed(error))) }
                completion(.success(parsed))
            }
        }
    }

    func cancel() { stop(.cancelled) }

    /// SIGTERM first, so the CLI can close its connections; it was seen to ignore that mid-request
    /// (a live job outlived it by a quarter of an hour), so SIGKILL follows.
    private func stop(_ why: Failure) {
        guard let process, stopped == nil else { return }
        stopped = why
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if let running = self?.process, running.processIdentifier == pid, running.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// The job's output, filled on the pipe's queue and read once the process has ended.
    private final class Collected {
        private let lock = NSLock()
        private var buffer = Data()
        private var found = false

        var data: Data {
            lock.lock(); defer { lock.unlock() }
            return buffer
        }

        /// True the first time the tool list is complete in the buffer.
        func append(_ chunk: Data, lookForTools: Bool) -> Bool {
            lock.lock(); defer { lock.unlock() }
            buffer.append(chunk)
            guard lookForTools, !found, BridgeOutput.parse(buffer).tools != nil else { return false }
            found = true
            return true
        }
    }

    // MARK: the command line

    static func arguments(for job: Job, model: String?) -> [String] {
        let model = model.flatMap { $0.isEmpty ? nil : $0 } ?? "haiku"
        // The prompt comes first: the tool lists are variadic options and would swallow it.
        var arguments = ["-p", prompt(for: job), "--model", model, "--tools", "", "--no-session-persistence"]
        let allowed: [String], denied: [String], schema: String
        switch job {
        case .discover:
            return arguments + ["--output-format", "stream-json", "--verbose", "--permission-mode", "dontAsk", "--permission-prompts", "none"]
        case .list(_, let tools):
            (allowed, denied, schema) = (tools.read, tools.others, listSchema)
        case .create(_, let tools):
            (allowed, denied, schema) = (tools.create.map { [$0] } ?? [], tools.read + tools.others.filter { $0 != tools.create }, createSchema)
        }
        arguments += ["--output-format", "json", "--json-schema", schema, "--system-prompt", systemPrompt,
                      "--allowedTools", allowed.joined(separator: ",")]
        if !denied.isEmpty { arguments += ["--disallowedTools", denied.joined(separator: ",")] }
        return arguments + ["--permission-mode", "dontAsk", "--permission-prompts", "none", "--max-budget-usd", budgetUSD]
    }

    static let systemPrompt = "You are a data job run by a desktop app, with nobody reading along. Use only the calendar tools you were given. "
        + "Copy values exactly as the tools return them, never invent any, and answer only through the structured output."

    static func prompt(for job: Job, timeZone: TimeZone = .current) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.timeZone = timeZone
        switch job {
        case .discover:
            return "Reply with OK."
        case .list(let span, _):
            return """
            List every event on the user's calendars that overlaps the period from \(stamp.string(from: span.start)) to \(stamp.string(from: span.end)) (time zone \(timeZone.identifier)).
            First find the user's calendars if a tool for that exists, then list the events of each calendar they own or have selected, following every page of results. Expand repeating events into their single occurrences if the tool can.
            For each event give: id; calendar (its name); title; start and end exactly as returned (RFC 3339 with offset for timed events, YYYY-MM-DD for all-day events); allDay; location; attendees (how many people other than the user are invited, 0 if none); busy (false only if the event is marked free or transparent, or the user declined it); link (a video meeting URL from the conference data, location or description, else omit).
            Skip cancelled events. Set truncated to true only if you could not return everything.
            If a tool call fails, try it at most once more, then stop: set truncated to true and copy the tool's error message into problem.
            """
        case .create(let draft, _):
            return """
            Create exactly one event on the user's primary calendar, and nothing else:
            title: \(draft.title)
            start: \(stamp.string(from: draft.start))
            end: \(stamp.string(from: draft.end))
            time zone: \(timeZone.identifier)
            description: \(draft.notes)
            No attendees, no location, no video conference, no repetition. Make one attempt only. Report whether it was created, with its id and link.
            """
        }
    }

    static let listSchema = """
    {"type":"object","properties":{"events":{"type":"array","items":{"type":"object","properties":{\
    "id":{"type":"string"},"calendar":{"type":"string"},"title":{"type":"string"},"start":{"type":"string"},"end":{"type":"string"},\
    "allDay":{"type":"boolean"},"location":{"type":"string"},"attendees":{"type":"integer"},"busy":{"type":"boolean"},"link":{"type":"string"}},\
    "required":["id","title","start","end","allDay","attendees","busy"]}},"truncated":{"type":"boolean"},"problem":{"type":"string"}},"required":["events"]}
    """

    static let createSchema = """
    {"type":"object","properties":{"created":{"type":"boolean"},"id":{"type":"string"},"link":{"type":"string"},"problem":{"type":"string"}},"required":["created"]}
    """
}

/// What came back from a job, read from whatever the CLI printed: one result object, an array of
/// events, or one event per line.
struct BridgeOutput {
    /// Tool names from `system/init`, when the output included it.
    var tools: [String]?
    var structured: Any?
    /// The job's prose answer, kept ONLY so a refusal can be recognised. It may quote the user's
    /// calendar, so it is never shown, logged or stored: see `SyncProblem.isAuthorisation`.
    var saidText: String?
    var costUSD: Double = 0
    /// Set when the run did not succeed: the CLI's error subtype, or a short reason.
    var error: String?

    static func parse(_ data: Data) -> BridgeOutput {
        var events: [[String: Any]] = []
        if let whole = try? JSONSerialization.jsonObject(with: data) {
            events = (whole as? [[String: Any]]) ?? (whole as? [String: Any]).map { [$0] } ?? []
        } else {
            for line in data.split(separator: UInt8(ascii: "\n")) {
                if let event = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { events.append(event) }
            }
        }
        var output = BridgeOutput()
        var sawResult = false
        for event in events {
            switch event["type"] as? String {
            case "system" where event["subtype"] as? String == "init":
                output.tools = event["tools"] as? [String]
            case "result":
                sawResult = true
                output.costUSD = (event["total_cost_usd"] as? NSNumber)?.doubleValue ?? 0
                output.structured = event["structured_output"]
                output.saidText = event["result"] as? String
                if event["is_error"] as? Bool == true || event["subtype"] as? String != "success" {
                    output.error = (event["subtype"] as? String).flatMap { $0 == "success" ? nil : $0 } ?? "error"
                } else if output.structured == nil {
                    output.error = "no structured result"
                }
            default:
                break
            }
        }
        if !sawResult { output.error = "no result" }
        return output
    }
}
