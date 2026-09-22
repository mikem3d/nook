import Foundation

/// Headless check of the engine: one session, no windows, everything logged to stderr.
///
///   Nook --engine-test <folder> --say=<text> [--auto-allow | --auto-deny]
///        [--attach=<file>]... [--resume=<session-id>] [--model=<name>] [--ask]
///        [--interrupt-after=<seconds>] [--then=<text>]
///        [--meanwhile=<text>] [--meanwhile-after=<seconds>] [--allow-after=<seconds>]
///
/// `--ask` makes Bash, Write and Edit prompt even when the user's settings allow them.
/// `--then` sends a second message after the first turn's result (exercises restart after a crash).
/// `--meanwhile` types ahead while the first turn runs; `--allow-after` delays the permission answer,
/// so the typed-ahead message has to wait in the queue.
/// Exits 0 when the last turn's result arrives, 1 if the session dies first, 2 on bad usage.
enum EngineTest {
    static func run(_ args: [String]) -> Never {
        func values(_ name: String) -> [String] {
            args.filter { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
        }
        guard let at = args.firstIndex(of: "--engine-test"), args.count > at + 1,
              let say = values("say").first else {
            log("usage: Nook --engine-test <folder> --say=<text> [--auto-allow|--auto-deny]")
            exit(2)
        }
        let folder = URL(fileURLWithPath: args[at + 1])
        let allow: Bool? = args.contains("--auto-allow") ? true : args.contains("--auto-deny") ? false : nil
        var queued = values("then")

        let session = AgentSession(label: "test", cwd: folder, resume: values("resume").first)
        if let model = values("model").first { session.extraArguments += ["--model", model] }
        if args.contains("--ask") {
            session.extraArguments += ["--settings", #"{"permissions":{"ask":["Bash","Write","Edit"]}}"#]
        }

        var last = ""
        var logged = 0
        var answered: String?
        var streamUpdates = 0
        var wasBusy = false
        var todos: [AgentTodo] = []
        // Presence: how long the user sits with nothing to look at.
        let sent = ProcessInfo.processInfo.systemUptime
        var firstPresence: Double?   // anything at all: thinking, or a tool call forming
        var firstReply: Double?      // the old measure: the first token of the reply
        var rows: [String: ToolRow] = [:]
        func seconds() -> Double { ProcessInfo.processInfo.systemUptime - sent }
        session.onChange = {
            for entry in session.transcript[logged...] where entry.kind != .thinking {
                log("  transcript \(entry.kind): \(entry.text)")
            }
            logged = session.transcript.count
            for entry in session.transcript where entry.kind == .tool {
                guard let row = entry.tool, rows[row.id] != row else { continue }
                rows[row.id] = row
                log(String(format: "  %6.2f tool %@ [%@] %@ %@", seconds(), row.name,
                           "\(row.status)", row.argument, row.detail))
            }
            if firstPresence == nil, session.phase != .idle, session.phase != .sending {
                firstPresence = seconds()
                log(String(format: "  %6.2f FIRST PRESENCE: %@", firstPresence!, session.phase.words))
            }
            if firstReply == nil, !session.streamingText.isEmpty {
                firstReply = seconds()
                log(String(format: "  %6.2f FIRST REPLY TOKEN", firstReply!))
            }
            if !session.streamingText.isEmpty { streamUpdates += 1 }
            if session.todos != todos {
                todos = session.todos
                log("  todos " + todos.map { "[\($0.status.rawValue)] \($0.content) / \($0.activeForm)" }.joined(separator: "; "))
            }
            let bubble = session.bubble.prefix(60).replacingOccurrences(of: "\n", with: "⏎")
            let line = "state=\(session.state.rawValue) phase=\"\(session.phase.words)\" bubble=\"\(bubble)\" "
                + "stream=\(session.streamingText.count) summary=\"\(session.summary)\" "
                + "context=\(session.contextTokens)/\(session.contextLimit) changed=\(session.changedFiles) "
                + "turn=\(session.turnStarted == nil ? "-" : "running") session=\(session.sessionID ?? "-") "
                + "model=\(session.model) cost=\(session.costUSD)"
            if line != last { log(line); last = line }

            if let request = session.pending, request.requestID != answered {
                answered = request.requestID
                log("  permission \(request.tool) \(request.input)")
                if let allow {
                    // `--allow-after` leaves the question open for a while, which is the one state
                    // where a typed-ahead message has to wait in the queue.
                    let delay = values("allow-after").first.flatMap(Double.init) ?? 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        log("  answering \(allow ? "allow" : "deny"), queued=\(session.queue.items.count)")
                        session.answerPermission(allow: allow)
                    }
                } else {
                    log("  no --auto-allow or --auto-deny given; interrupting")
                    DispatchQueue.main.async { session.interrupt() }
                }
            }
            if session.state.busy { wasBusy = true }
            guard wasBusy, session.state == .done || session.state == .sleeping else { return }
            wasBusy = false
            if !queued.isEmpty {
                let next = queued.removeFirst()
                DispatchQueue.main.async { session.send(next) }
                return
            }
            let code: Int32 = session.state == .done ? 0 : 1
            // Leave a moment for the git status count to land.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                log(String(format: "presence: first anything %.2fs, first reply token %.2fs",
                           firstPresence ?? -1, firstReply ?? -1))
                log("finished: streamUpdates=\(streamUpdates) \(last)")
                session.onChange = nil
                session.stop()
                exit(code)
            }
        }

        session.start()
        session.send(say, attachments: values("attach").map { URL(fileURLWithPath: $0) })
        // Type-ahead: a message sent while the first turn is still running.
        if let text = values("meanwhile").first {
            let delay = values("meanwhile-after").first.flatMap(Double.init) ?? 2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                log(String(format: "  %6.2f typing ahead: %@ (state=%@)", seconds(), text, session.state.rawValue))
                session.send(text)
                log("  queued=\(session.queue.items.count)")
            }
        }
        if let seconds = values("interrupt-after").first.flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                log("  interrupting")
                session.interrupt()
            }
        }
        RunLoop.main.run()
        exit(1)
    }

    private static func log(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
