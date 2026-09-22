import Foundation

/// One command Nook ran itself: its output as it arrives, and how it ended.
///
/// A reference type, because the log block re-renders in place while the command runs. Every
/// visible change bumps `version`; the log watches that rather than diffing the text.
final class ShellRun: Equatable {
    /// A stretch of output from one stream. Consecutive output from the same stream merges,
    /// so the two streams stay interleaved in arrival order without a chunk per read.
    struct Chunk: Equatable {
        var isError: Bool
        var text: String
    }

    /// Distinguishes two adjacent blocks for the layout manager's background drawing.
    let id = UUID()
    let command: String
    /// Where it ran.
    let directory: URL
    /// The agent's own folder, so the block can say when the command ran somewhere else.
    let agentFolder: URL

    private(set) var chunks: [Chunk] = []
    private(set) var bytes = 0
    /// True once output has been dropped from the front to stay under the cap.
    private(set) var dropped = false
    private(set) var exitCode: Int32?
    /// Wall-clock seconds, measured on the monotonic clock.
    private(set) var duration: TimeInterval = 0
    private(set) var stopping = false
    /// Set once the result has been sent to the agent; a result is never shared twice.
    private(set) var shared = false
    /// The user asked to see all of a long result.
    private(set) var expanded = false
    private(set) var version = 0

    private let startedAt: TimeInterval
    private var lastOutputAt: TimeInterval
    private var columns = [0, 0] // one per stream, so a line split across reads is capped as one line

    /// Running with nothing coming out for this long: probably waiting on a terminal it has not got.
    static let stallAfter: TimeInterval = 30

    init(command: String, directory: URL, agentFolder: URL, clock: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.command = command
        self.directory = directory
        self.agentFolder = agentFolder
        startedAt = clock
        lastOutputAt = clock
    }

    static func == (lhs: ShellRun, rhs: ShellRun) -> Bool { lhs === rhs }

    var isRunning: Bool { exitCode == nil }
    var failed: Bool { (exitCode ?? 0) != 0 }
    var elapsed: TimeInterval { isRunning ? ProcessInfo.processInfo.systemUptime - startedAt : duration }
    var isStalled: Bool { isRunning && ProcessInfo.processInfo.systemUptime - lastOutputAt > Self.stallAfter }
    /// The folder is worth showing only when it is not the agent's own.
    var showsDirectory: Bool { directory.standardizedFileURL != agentFolder.standardizedFileURL }

    /// Everything printed, both streams in order, as a terminal would have shown it.
    var text: String { chunks.map(\.text).joined() }

    // MARK: writing

    func append(_ text: String, isError: Bool) {
        guard !text.isEmpty else { return }
        let stream = isError ? 1 : 0
        let (clamped, column) = ShellCommand.clamp(text, column: columns[stream])
        columns[stream] = column
        guard !clamped.isEmpty else { return }
        if chunks.last?.isError == isError {
            chunks[chunks.count - 1].text += clamped
        } else {
            chunks.append(Chunk(isError: isError, text: clamped))
        }
        bytes += clamped.utf8.count
        trim()
        lastOutputAt = ProcessInfo.processInfo.systemUptime
        bump()
    }

    /// Keeps the tail within the cap, dropping whole chunks and then part of one.
    private func trim() {
        guard bytes > ShellCommand.outputLimit else { return }
        dropped = true
        while bytes > ShellCommand.outputLimit, let first = chunks.first {
            let size = first.text.utf8.count
            if bytes - size >= ShellCommand.outputLimit {
                chunks.removeFirst()
                bytes -= size
            } else {
                let keep = ShellCommand.tail(first.text, limit: ShellCommand.outputLimit - (bytes - size))
                bytes -= size - keep.text.utf8.count
                chunks[0].text = keep.text
            }
        }
    }

    func finish(exitCode: Int32, duration: TimeInterval) {
        guard isRunning else { return }
        self.exitCode = exitCode
        self.duration = duration
        stopping = false
        bump()
    }

    func markStopping() {
        stopping = true
        bump()
    }

    func markShared() {
        shared = true
        bump()
    }

    func toggleExpanded() {
        expanded.toggle()
        bump()
    }

    /// Anything the block draws that is not stored here (the elapsed clock, the stall notice).
    func bump() { version &+= 1 }
}

/// Runs one command through the user's login shell, reporting output as it arrives.
/// Every callback lands on the main thread; nothing blocks it.
final class ShellRunner {
    private let process = Process()
    private let onOutput: (String, Bool) -> Void
    private let onExit: (Int32, TimeInterval) -> Void
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var openPipes = 2
    private var status: (code: Int32, duration: TimeInterval)?
    private var killer: DispatchWorkItem?
    private var finished = false

    /// The user's own login shell, so their PATH, aliases and version managers are the ones they expect.
    static var shellPath: String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        return FileManager.default.isExecutableFile(atPath: shell) ? shell : "/bin/zsh"
    }

    init(onOutput: @escaping (String, Bool) -> Void, onExit: @escaping (Int32, TimeInterval) -> Void) {
        self.onOutput = onOutput
        self.onExit = onExit
    }

    /// Starts the command, or reports a non-zero exit straight away if it could not be launched.
    /// `shell` is the login shell to run it through; the tests pass a plain one.
    func start(command: String, directory: URL, shell: String = ShellRunner.shellPath) {
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = directory
        // Same treatment the agent's own process gets: the user's environment, minus the two
        // variables that would tell a nested tool it is running inside Claude Code.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        process.environment = env
        // There is no terminal here: interactive programs should fail at once rather than hang.
        process.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        read(out, isError: false)
        read(err, isError: true)
        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationReason == .uncaughtSignal ? 128 + proc.terminationStatus : proc.terminationStatus
            let duration = ProcessInfo.processInfo.systemUptime - (self?.startedAt ?? 0)
            DispatchQueue.main.async { self?.exited(code: code, duration: duration) }
        }
        do {
            try process.run()
        } catch {
            onOutput("Could not run the command: \(error.localizedDescription)\n", true)
            onExit(127, 0)
            finished = true
        }
    }

    /// SIGTERM, then SIGKILL if it is still there three seconds later.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let kill = DispatchWorkItem { [weak self] in
            guard let self, self.process.isRunning else { return }
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
        killer = kill
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: kill)
    }

    private func read(_ pipe: Pipe, isError: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                DispatchQueue.main.async { self?.pipeClosed() }
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.onOutput(text, isError) }
        }
    }

    private func pipeClosed() {
        openPipes -= 1
        settle()
    }

    /// The exit is only reported once both pipes have drained, so the last line is never lost.
    private func exited(code: Int32, duration: TimeInterval) {
        status = (code, duration)
        settle()
    }

    private func settle() {
        guard !finished, openPipes == 0, let status else { return }
        finished = true
        killer?.cancel()
        onExit(status.code, status.duration)
    }
}
