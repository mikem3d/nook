import Foundation

/// Preferences for the shell escape. Both default to off/unshown.
enum ShellPrefs {
    /// Send every result to the agent as it finishes. Off by default: output can hold secrets,
    /// and sharing is what puts it in front of the model.
    static let autoShare = "nook.shell.autoShare"
    /// The one-time note in the log explaining the `!` escape.
    static let hintShown = "nook.shell.hintShown"

    static var autoShareEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoShare) }
        set { UserDefaults.standard.set(newValue, forKey: autoShare) }
    }
}

/// The shell side of one agent's chat: its working folder, its history, and the single command
/// that may be running at a time.
///
/// `handle` is the only way in, and it takes a `TypedLine`, whose initialiser is private to
/// ChatPanel.swift. Nothing else — not the agent's own text, a queued task, a schedule, a voice
/// transcript or a notification reply — can construct one, so nothing else can start a command.
final class ShellConsole {
    private static var consoles: [UUID: ShellConsole] = [:]

    static func console(for session: AgentSession) -> ShellConsole {
        if let existing = consoles[session.id] { return existing }
        consoles = consoles.filter { $0.value.session != nil } // closed agents leave nothing behind
        let console = ShellConsole(session: session)
        consoles[session.id] = console
        return console
    }

    /// What became of a line the user typed.
    enum Outcome: Equatable {
        /// Not a command: this is the text to send to the agent (a leading `\!` unescaped).
        case message(String)
        case ran
        /// A bare `!`.
        case nothing
        /// A command is already running for this agent.
        case busy
        /// This agent has no working folder (a demo agent), so there is nowhere to run.
        case noFolder
    }

    private weak var session: AgentSession?
    private(set) var directory: URL
    private var previousDirectory: URL?
    private var runner: ShellRunner?
    private(set) var current: ShellRun?
    private var tick: Timer?
    private var lastFlush = 0.0
    private var flushScheduled = false

    /// Output is published at most this often; a chatty build must not redraw the log per read.
    private static let flushInterval = 1.0 / 12

    private init(session: AgentSession) {
        self.session = session
        directory = session.cwd ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var isRunning: Bool { runner != nil }

    // MARK: the one way in

    @discardableResult
    func handle(_ line: TypedLine) -> Outcome {
        switch ShellCommand.parse(line.text) {
        case let .message(text): return .message(text)
        case .nothing: return .nothing
        case let .run(command): return run(command)
        }
    }

    private func run(_ command: String) -> Outcome {
        guard let session else { return .noFolder }
        guard let folder = session.cwd else {
            session.remark("This agent has no working folder, so there is nowhere to run a command.")
            return .noFolder
        }
        guard runner == nil else {
            session.remark("A command is already running here. Stop it first (⌘.), then try again.")
            return .busy
        }
        ShellHistory.add(command, for: folder)

        let run = ShellRun(command: command, directory: directory, agentFolder: folder)
        session.logShell(run)
        current = run

        // `cd` cannot survive a fresh `$SHELL -lc`, so Nook keeps the folder itself.
        if let argument = ShellCommand.cdArgument(command) {
            changeDirectory(to: argument, run: run)
            return .ran
        }
        let runner = ShellRunner(
            onOutput: { [weak self] text, isError in
                run.append(text, isError: isError)
                self?.publish()
            },
            onExit: { [weak self] code, duration in
                run.finish(exitCode: code, duration: duration)
                self?.ended(run)
            })
        self.runner = runner
        runner.start(command: command, directory: directory)
        startTicking()
        publish(now: true)
        return .ran
    }

    private func changeDirectory(to argument: String, run: ShellRun) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var isFolder: ObjCBool = false
        guard let target = ShellCommand.resolve(argument, from: directory, home: home, previous: previousDirectory) else {
            run.append("cd: no previous folder to go back to\n", isError: true)
            run.finish(exitCode: 1, duration: 0)
            return publish(now: true)
        }
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isFolder), isFolder.boolValue else {
            run.append("cd: no such folder: \(target.path)\n", isError: true)
            run.finish(exitCode: 1, duration: 0)
            return publish(now: true)
        }
        previousDirectory = directory
        directory = target
        run.append(target.path + "\n", isError: false)
        run.finish(exitCode: 0, duration: 0)
        publish(now: true)
    }

    // MARK: stopping

    /// True when there was something to stop; the chat panel uses that to decide what ⌘. means.
    @discardableResult
    func stop() -> Bool {
        guard let runner, let run = current, run.isRunning else { return false }
        run.markStopping()
        runner.stop()
        publish(now: true)
        return true
    }

    private func ended(_ run: ShellRun) {
        runner = nil
        current = nil
        stopTicking()
        publish(now: true)
        if ShellPrefs.autoShareEnabled { share(run) }
    }

    // MARK: sharing

    /// Sends a finished result to the agent as an ordinary user message. This is the only path
    /// by which anything a command printed reaches the API.
    func share(_ run: ShellRun) {
        guard let session, let code = run.exitCode, !run.shared else { return }
        run.markShared()
        session.send(ShellCommand.shareMessage(command: run.command, directory: run.directory.path,
                                               exitCode: code, output: run.text))
    }

    func toggleAutoShare() {
        ShellPrefs.autoShareEnabled.toggle()
        session?.remark(ShellPrefs.autoShareEnabled
            ? "Auto-share is ON: every command's output now goes to the agent, and to the API."
            : "Auto-share is OFF: command output stays on this machine until you share it.")
    }

    // MARK: redraw

    /// The elapsed clock and the "still running" notice need a beat; nothing ticks when idle.
    private func startTicking() {
        guard tick == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.current?.bump()
            self?.publish(now: true)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }

    /// Redraws the log, throttled, on the main thread.
    private func publish(now: Bool = false) {
        guard !now else {
            lastFlush = ProcessInfo.processInfo.systemUptime
            session?.onChange?()
            return
        }
        let wait = lastFlush + Self.flushInterval - ProcessInfo.processInfo.systemUptime
        guard wait > 0 else { return publish(now: true) }
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.flushScheduled = false
            self?.publish(now: true)
        }
    }
}
