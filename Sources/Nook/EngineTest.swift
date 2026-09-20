import Foundation

/// Headless check of the engine: one session, no windows, everything logged to stderr.
///
///   Nook --engine-test <folder> --say=<text> [--auto-allow | --auto-deny]
///        [--attach=<file>]... [--resume=<session-id>] [--model=<name>] [--ask]
///        [--interrupt-after=<seconds>] [--then=<text>]
///
/// `--ask` makes Bash, Write and Edit prompt even when the user's settings allow them.
/// `--then` sends a second message after the first turn's result (exercises restart after a crash).
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
        session.onChange = {
            for entry in session.transcript[logged...] { log("  transcript \(entry.kind): \(entry.text)") }
            logged = session.transcript.count
            if !session.streamingText.isEmpty { streamUpdates += 1 }
            let bubble = session.bubble.prefix(60).replacingOccurrences(of: "\n", with: "⏎")
            let line = "state=\(session.state.rawValue) bubble=\"\(bubble)\" "
                + "stream=\(session.streamingText.count) summary=\"\(session.summary)\" "
                + "context=\(session.contextTokens)/\(session.contextLimit) changed=\(session.changedFiles) "
                + "turn=\(session.turnStarted == nil ? "-" : "running") session=\(session.sessionID ?? "-") "
                + "model=\(session.model) cost=\(session.costUSD)"
            if line != last { log(line); last = line }

            if let request = session.pending, request.requestID != answered {
                answered = request.requestID
                log("  permission \(request.tool) \(request.input)")
                if let allow {
                    DispatchQueue.main.async { session.answerPermission(allow: allow) }
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
                log("finished: streamUpdates=\(streamUpdates) \(last)")
                session.onChange = nil
                session.stop()
                exit(code)
            }
        }

        session.start()
        session.send(say, attachments: values("attach").map { URL(fileURLWithPath: $0) })
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
