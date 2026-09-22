import XCTest
@testable import Nook

/// The pure half of "present": reading a tool call while it is still arriving, saying what its
/// result amounted to, naming the phase, and holding typed-ahead text.
final class PartialJSONTests: XCTestCase {
    func testCompleteInput() {
        XCTAssertEqual(PartialJSON.argument(#"{"file_path": "/tmp/a.ts", "offset": 2}"#), "/tmp/a.ts")
        XCTAssertEqual(PartialJSON.argument(#"{"description": "list", "command": "ls -la"}"#), "ls -la",
                       "the command matters more than its description")
    }

    func testCutAnywhere() {
        let whole = #"{"command": "grep -rn \"TODO\" src/"}"#
        for cut in 0...whole.count {
            _ = PartialJSON.argument(String(whole.prefix(cut))) // must never trap
        }
        XCTAssertEqual(PartialJSON.argument(#"{"command": "grep -rn"#), "grep -rn", "the value so far")
        XCTAssertEqual(PartialJSON.argument(#"{"comm"#), "")
        XCTAssertEqual(PartialJSON.argument(#"{"command":"#), "")
        XCTAssertEqual(PartialJSON.argument(""), "")
    }

    func testEscapes() {
        XCTAssertEqual(PartialJSON.argument(#"{"pattern": "a\"b\\c\nd"#), "a\"b\\c\nd")
        XCTAssertEqual(PartialJSON.argument(#"{"query": "café"#), "café")
        XCTAssertEqual(PartialJSON.argument(#"{"query": "half \u00"#), "half ", "cut inside an escape")
    }

    func testStreamedPieceByPiece() {
        let pieces = ["", "{\"file_path\": \"/private", "/tmp", "/nook", "/lookup.ts", "\"}"]
        var json = ""
        var seen: [String] = []
        for piece in pieces {
            json += piece
            seen.append(PartialJSON.argument(json))
        }
        XCTAssertEqual(seen, ["", "/private", "/private/tmp", "/private/tmp/nook",
                              "/private/tmp/nook/lookup.ts", "/private/tmp/nook/lookup.ts"])
    }
}

final class ToolReportTests: XCTestCase {
    func testShellResults() {
        let ran: [String: Any] = ["stdout": "a\nb\nc\n", "stderr": "", "interrupted": false]
        XCTAssertEqual(ToolReport.summarise(name: "Bash", result: ran, failed: false), "3 lines")
        XCTAssertEqual(ToolReport.summarise(name: "Bash", result: ["stdout": "", "stderr": ""], failed: false), "no output")
        XCTAssertEqual(ToolReport.summarise(name: "Bash", result: ["stdout": "", "stderr": "ls: no such file"], failed: true),
                       "failed: ls: no such file")
        XCTAssertEqual(ToolReport.summarise(name: "Bash", result: ["stdout": "x", "stderr": "", "interrupted": true], failed: false),
                       "interrupted")
    }

    func testFileAndSearchResults() {
        let read: [String: Any] = ["type": "text", "file": ["filePath": "/a/lookup.ts", "numLines": 5]]
        XCTAssertEqual(ToolReport.summarise(name: "Read", result: read, failed: false), "5 lines")
        XCTAssertEqual(ToolReport.summarise(name: "Grep", result: ["numFiles": 2, "numLines": 7], failed: false), "7 matches")
        XCTAssertEqual(ToolReport.summarise(name: "Glob", result: ["filenames": ["a", "b", "c"]], failed: false), "3 files")
        XCTAssertEqual(ToolReport.summarise(name: "Write", result: ["type": "create", "filePath": "/a/notes.md"], failed: false),
                       "created notes.md")
        XCTAssertEqual(ToolReport.summarise(name: "Read", result: ["file": ["numLines": 1]], failed: false), "1 line")
    }

    func testAnythingElseStillSaysSomething() {
        XCTAssertEqual(ToolReport.summarise(name: "X", result: nil, failed: false), "done")
        XCTAssertEqual(ToolReport.summarise(name: "X", result: nil, failed: true), "failed")
        XCTAssertEqual(ToolReport.summarise(name: "X", result: "", failed: false), "no output")
        XCTAssertEqual(ToolReport.summarise(name: "X", result: nil, failed: false, content: "one\ntwo"), "2 lines")
        XCTAssertEqual(ToolReport.summarise(name: "X", result: String(repeating: "x", count: 500), failed: false), "500 bytes")
    }
}

final class ActivityTests: XCTestCase {
    func testPhaseWords() {
        XCTAssertEqual(ActivityPhase.thinking(tokens: 0).words, "Thinking…")
        XCTAssertEqual(ActivityPhase.thinking(tokens: 240).words, "Thinking… 240 tokens")
        XCTAssertEqual(ActivityPhase.running(tool: "Read", argument: "src/lookup.ts").words, "Reading src/lookup.ts…")
        XCTAssertEqual(ActivityPhase.running(tool: "Bash", argument: "npm test").words, "Running npm test…")
        XCTAssertEqual(ActivityPhase.running(tool: "Grep", argument: "TODO").words, "Searching for TODO…")
        XCTAssertEqual(ActivityPhase.running(tool: "TodoWrite", argument: "").words, "Updating its plan…")
        XCTAssertEqual(ActivityPhase.running(tool: "Prettier", argument: "").words, "Using Prettier…")
        XCTAssertEqual(ActivityPhase.approval(tool: "Bash").words, "Waiting for approval: Bash")
        XCTAssertEqual(ActivityPhase.replying.words, "Replying…")
        XCTAssertEqual(ActivityPhase.idle.words, "")
    }

    /// The avatar reads the same phases, so it turns at the same moment the log does.
    func testPhasesDriveTheAvatar() {
        XCTAssertEqual(ActivityPhase.sending.state, .thinking)
        XCTAssertEqual(ActivityPhase.thinking(tokens: 1).state, .thinking)
        XCTAssertEqual(ActivityPhase.running(tool: "Bash", argument: "ls").state, .working)
        XCTAssertEqual(ActivityPhase.approval(tool: "Bash").state, .alert)
        XCTAssertEqual(ActivityPhase.replying.state, .talking)
        XCTAssertNil(ActivityPhase.idle.state)
    }

    func testShortening() {
        XCTAssertEqual(Activity.shorten("/a/very/deep/tree/of/folders/with/a/long/name/lookup.ts"), "…/name/lookup.ts")
        XCTAssertEqual(Activity.shorten("short.ts"), "short.ts")
        XCTAssertEqual(Activity.shorten(String(repeating: "x", count: 80)).count, 46)
        XCTAssertEqual(Activity.shorten("ls -la\nwc -l"), "ls -la wc -l")
    }

    func testClockAndSpinner() {
        XCTAssertEqual(Activity.elapsed(0), "0s")
        XCTAssertEqual(Activity.elapsed(4.9), "4s")
        XCTAssertEqual(Activity.elapsed(65), "1:05")
        XCTAssertEqual(Activity.elapsed(-3), "0s")
        XCTAssertEqual(Activity.frame(at: 0), Activity.frames[0])
        XCTAssertEqual(Activity.frame(at: 0.35), Activity.frames[3])
        XCTAssertEqual(Activity.frame(at: 1.0), Activity.frames[0], "one turn a second")
    }

    func testLine() {
        let line = Activity.line(phase: .running(tool: "Read", argument: "lookup.ts"), seconds: 7, at: 0.1)
        XCTAssertEqual(line, "⠙  Reading lookup.ts…  7s  ⌘. to stop")
        XCTAssertEqual(Activity.line(phase: .idle, seconds: 0, at: 0, hint: ""), "⠋  0s")
    }
}

final class MessageQueueTests: XCTestCase {
    func testQueueKeepsOrderAndCancels() {
        var queue = MessageQueue()
        let first = QueuedMessage(text: "one")
        let second = QueuedMessage(text: "two")
        queue.append(first)
        queue.append(second)
        XCTAssertFalse(queue.isEmpty)
        XCTAssertTrue(queue.cancel(first.id))
        XCTAssertFalse(queue.cancel(first.id), "already gone")
        XCTAssertEqual(queue.take().map(\.text), ["two"])
        XCTAssertTrue(queue.isEmpty, "taking empties it, so nothing is sent twice")
        XCTAssertEqual(queue.take(), [])
    }

    /// Typed text is never lost: a message goes into the queue while a permission question is
    /// open, and leaves it the moment the question is answered.
    func testSessionHoldsTypeAheadBehindAPermissionQuestion() {
        let session = AgentSession(label: "demo", cwd: nil)
        session.send("go") // demo mode: no process, nothing queued
        XCTAssertTrue(session.queue.isEmpty)
    }
}

final class SessionPresenceTests: XCTestCase {
    /// Feeding the engine the events a real turn sends, in the order and shape they arrive in
    /// (captured from a live `claude --include-partial-messages` run).
    func testStreamShowsThinkingAndToolsBeforeTheReply() {
        let session = AgentSession(label: "demo", cwd: nil)
        session.send("read it")
        XCTAssertEqual(session.phase, .sending)

        session.feed(["type": "stream_event", "event": [
            "type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": ""]]])
        XCTAssertEqual(session.phase, .thinking(tokens: 0))
        XCTAssertEqual(session.state, .thinking)
        XCTAssertEqual(session.transcript.last?.kind, .thinking)

        session.feed(["type": "system", "subtype": "thinking_tokens", "estimated_tokens": 120])
        XCTAssertEqual(session.phase, .thinking(tokens: 120))
        session.feed(["type": "stream_event", "event": [
            "type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": "weighing"]]])
        XCTAssertEqual(session.thinkingText, "weighing")
        XCTAssertEqual(session.transcript.last?.text, "weighing")
        session.feed(["type": "stream_event", "event": [
            "type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "abc"]]])
        XCTAssertEqual(session.thinkingText, "weighing", "signatures are not reasoning")

        session.feed(["type": "stream_event", "event": ["type": "content_block_stop", "index": 0]])
        XCTAssertNil(session.openThinking, "the block folds away when it ends")
        XCTAssertEqual(session.transcript.last?.thinkingTokens, 120, "but it stays in the transcript")

        // The call shows up as it forms, argument first.
        session.feed(["type": "stream_event", "event": [
            "type": "content_block_start", "index": 1,
            "content_block": ["type": "tool_use", "id": "t1", "name": "Read", "input": [:]]]])
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.runningTool?.name, "Read")
        for part in ["{\"file_path\": \"/a", "/lookup", ".ts\"}"] {
            session.feed(["type": "stream_event", "event": [
                "type": "content_block_delta", "index": 1, "delta": ["type": "input_json_delta", "partial_json": part]]])
        }
        XCTAssertEqual(session.phase, .running(tool: "Read", argument: "/a/lookup.ts"))

        session.feed(["type": "user", "tool_use_result": ["file": ["numLines": 5]],
                      "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1"]]]])
        XCTAssertNil(session.runningTool, "the row is finished")
        XCTAssertEqual(session.transcript.last?.tool?.status, .ok)
        XCTAssertEqual(session.transcript.last?.tool?.detail, "5 lines")

        session.feed(["type": "stream_event", "event": [
            "type": "content_block_start", "index": 2, "content_block": ["type": "text", "text": ""]]])
        session.feed(["type": "stream_event", "event": [
            "type": "content_block_delta", "index": 2, "delta": ["type": "text_delta", "text": "It adds one."]]])
        XCTAssertEqual(session.streamingText, "It adds one.", "the first token is published at once, not on the next tick")
        XCTAssertEqual(session.phase, .replying)
    }

    func testFailedToolSaysSo() {
        let session = AgentSession(label: "demo", cwd: nil)
        session.send("go")
        session.feed(["type": "stream_event", "event": [
            "type": "content_block_start", "index": 0,
            "content_block": ["type": "tool_use", "id": "t1", "name": "Bash", "input": [:]]]])
        session.feed(["type": "user",
                      "tool_use_result": ["stdout": "", "stderr": "npm: command not found"],
                      "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "is_error": true]]]])
        XCTAssertEqual(session.transcript.last?.tool?.status, .failed)
        XCTAssertEqual(session.transcript.last?.tool?.detail, "failed: npm: command not found")
    }

    /// Two calls in flight at once (the CLI runs them in parallel); each row finishes on its own id.
    func testParallelToolRows() {
        let session = AgentSession(label: "demo", cwd: nil)
        session.send("go")
        for (index, id) in [(0, "a"), (1, "b")] {
            session.feed(["type": "stream_event", "event": [
                "type": "content_block_start", "index": index,
                "content_block": ["type": "tool_use", "id": id, "name": "Bash", "input": [:]]]])
        }
        XCTAssertEqual(session.runningTool?.id, "b")
        session.feed(["type": "user", "tool_use_result": ["stdout": "hi\n"],
                      "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "b"]]]])
        XCTAssertEqual(session.runningTool?.id, "a", "the other one is still going")
        let rows = session.transcript.compactMap(\.tool)
        XCTAssertEqual(rows.map(\.status), [.running, .ok])
        XCTAssertEqual(rows[1].detail, "1 line")
    }
}
