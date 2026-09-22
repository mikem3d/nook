import XCTest
@testable import Nook

final class ShellCommandTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(ShellCommand.parse("!git status"), .run("git status"))
        XCTAssertEqual(ShellCommand.parse("  !  npm test  "), .run("npm test"))
        XCTAssertEqual(ShellCommand.parse("!"), .nothing)
        XCTAssertEqual(ShellCommand.parse("!   "), .nothing)
        XCTAssertEqual(ShellCommand.parse("hello!"), .message("hello!"))
        XCTAssertEqual(ShellCommand.parse("what about foo!bar"), .message("what about foo!bar"))
    }

    func testEscapedBang() {
        XCTAssertEqual(ShellCommand.parse("\\!git status"), .message("!git status"))
        XCTAssertEqual(ShellCommand.parse("\\!"), .message("!"))
    }

    func testMultiLineCommand() {
        XCTAssertEqual(ShellCommand.parse("!for f in a b\ndo echo $f\ndone"), .run("for f in a b\ndo echo $f\ndone"))
    }

    // MARK: cd

    func testCdArgument() {
        XCTAssertEqual(ShellCommand.cdArgument("cd src"), "src")
        XCTAssertEqual(ShellCommand.cdArgument("cd"), "")
        XCTAssertEqual(ShellCommand.cdArgument("  cd   ../up  "), "../up")
        XCTAssertEqual(ShellCommand.cdArgument("cd \"my folder\""), "my folder")
        XCTAssertEqual(ShellCommand.cdArgument("cd my\\ folder"), "my folder")
        // Compound commands keep the shell's own semantics: the cd is local to that line.
        XCTAssertNil(ShellCommand.cdArgument("cd src && ls"))
        XCTAssertNil(ShellCommand.cdArgument("cd $(mktemp -d)"))
        XCTAssertNil(ShellCommand.cdArgument("cdx"))
        XCTAssertNil(ShellCommand.cdArgument("ls"))
    }

    func testResolve() {
        let base = URL(fileURLWithPath: "/tmp/work/app")
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(ShellCommand.resolve("src", from: base, home: home)?.path, "/tmp/work/app/src")
        XCTAssertEqual(ShellCommand.resolve("../lib", from: base, home: home)?.path, "/tmp/work/lib")
        XCTAssertEqual(ShellCommand.resolve("/etc", from: base, home: home)?.path, "/etc")
        XCTAssertEqual(ShellCommand.resolve("", from: base, home: home)?.path, home.path)
        XCTAssertEqual(ShellCommand.resolve("~", from: base, home: home)?.path, home.path)
        XCTAssertEqual(ShellCommand.resolve("~/code", from: base, home: home)?.path, "/Users/someone/code")
        XCTAssertEqual(ShellCommand.resolve("-", from: base, home: home, previous: home)?.path, home.path)
        XCTAssertNil(ShellCommand.resolve("-", from: base, home: home, previous: nil))
    }

    // MARK: limits

    func testTailKeepsTheEnd() {
        XCTAssertEqual(ShellCommand.tail("abcdef", limit: 10).text, "abcdef")
        XCTAssertFalse(ShellCommand.tail("abcdef", limit: 10).dropped)
        let cut = ShellCommand.tail("abcdef", limit: 3)
        XCTAssertEqual(cut.text, "def")
        XCTAssertTrue(cut.dropped)
    }

    func testTailCutsOnCharacterBoundaries() {
        let text = String(repeating: "é", count: 10) // two bytes each
        let cut = ShellCommand.tail(text, limit: 5)
        XCTAssertEqual(cut.text, "éé")
        XCTAssertTrue(cut.dropped)
    }

    func testClampCapsLines() {
        let (text, column) = ShellCommand.clamp("abcdefgh\nij", column: 0, limit: 4)
        XCTAssertEqual(text, "abcd…\nij")
        XCTAssertEqual(column, 2)
    }

    func testClampContinuesAcrossChunks() {
        var (text, column) = ShellCommand.clamp("abc", column: 0, limit: 4)
        XCTAssertEqual(text, "abc")
        (text, column) = ShellCommand.clamp("defg", column: column, limit: 4)
        XCTAssertEqual(text, "d…")
        (text, column) = ShellCommand.clamp("hij\nk", column: column, limit: 4)
        XCTAssertEqual(text, "\nk")
        XCTAssertEqual(column, 1)
    }

    // MARK: sharing

    func testShareMessage() {
        let message = ShellCommand.shareMessage(command: "ls", directory: "/tmp/app", exitCode: 0, output: "one\ntwo\n")
        XCTAssertTrue(message.contains("/tmp/app"))
        XCTAssertTrue(message.contains("$ ls"))
        XCTAssertTrue(message.contains("one\ntwo\n"))
        XCTAssertTrue(message.contains("[exit 0]"))
    }

    func testShareMessageTruncatesAndMarksIt() {
        let output = String(repeating: "x", count: 100) + "TAIL"
        let message = ShellCommand.shareMessage(command: "big", directory: "/tmp", exitCode: 3, output: output, limit: 10)
        XCTAssertTrue(message.contains("…earlier output trimmed…"))
        XCTAssertTrue(message.contains("TAIL"))
        XCTAssertFalse(message.contains(String(repeating: "x", count: 50)))
        XCTAssertTrue(message.contains("[exit 3]"))
    }

    func testShareMessageFenceSurvivesBackticksInOutput() {
        let message = ShellCommand.shareMessage(command: "cat", directory: "/tmp", exitCode: 0, output: "```\ncode\n```\n")
        XCTAssertTrue(message.contains("````console"))
    }
}

final class ShellHistoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private let folder = URL(fileURLWithPath: "/tmp/nook-history-test")

    override func setUp() {
        defaults = UserDefaults(suiteName: "nook.tests.shell.\(UUID().uuidString)")
    }

    func testRemembersPerFolderNewestLast() {
        ShellHistory.add("ls", for: folder, defaults: defaults)
        ShellHistory.add("git status", for: folder, defaults: defaults)
        ShellHistory.add("git status", for: folder, defaults: defaults) // a repeat in a row is one entry
        XCTAssertEqual(ShellHistory.commands(for: folder, defaults: defaults), ["ls", "git status"])
        XCTAssertEqual(ShellHistory.commands(for: URL(fileURLWithPath: "/tmp/elsewhere"), defaults: defaults), [])
    }

    func testKeepsTheLastHundred() {
        for i in 0..<130 { ShellHistory.add("cmd \(i)", for: folder, defaults: defaults) }
        let list = ShellHistory.commands(for: folder, defaults: defaults)
        XCTAssertEqual(list.count, ShellHistory.limit)
        XCTAssertEqual(list.first, "cmd 30")
        XCTAssertEqual(list.last, "cmd 129")
    }

    func testRecallPrefersTheLastThingSent() {
        let run = ShellRun(command: "ls -la", directory: folder, agentFolder: folder)
        let transcript: [TranscriptEntry] = [.init(kind: .user, text: "hello"), .init(kind: .shell(run), text: "ls -la"),
                                             .init(kind: .assistant, text: "hi")]
        XCTAssertEqual(ShellRecall.last(transcript: transcript, history: []), "!ls -la")
        XCTAssertEqual(ShellRecall.last(transcript: [.init(kind: .user, text: "hello")], history: ["old"]), "hello")
        XCTAssertEqual(ShellRecall.last(transcript: [], history: ["ls", "make"]), "!make")
        XCTAssertNil(ShellRecall.last(transcript: [], history: []))
    }
}

final class ShellRunTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp")

    private func made() -> ShellRun { ShellRun(command: "x", directory: folder, agentFolder: folder) }

    func testInterleavesAndMarksStderr() {
        let run = made()
        run.append("out1\n", isError: false)
        run.append("bad\n", isError: true)
        run.append("out2\n", isError: false)
        XCTAssertEqual(run.text, "out1\nbad\nout2\n")
        XCTAssertEqual(ShellBlock.lines(of: run).map(\.text), ["out1", "bad", "out2"])
        XCTAssertEqual(ShellBlock.lines(of: run).map(\.isError), [false, true, false])
    }

    func testJoinsPartialLinesAcrossChunks() {
        let run = made()
        run.append("half", isError: false)
        run.append(" done\n", isError: false)
        XCTAssertEqual(ShellBlock.lines(of: run).map(\.text), ["half done"])
    }

    func testKeepsTheTailWithinTheCap() {
        let run = made()
        // Many ordinary lines: one endless line is capped by `clamp` long before the tail cap.
        let block = (0..<1000).map { "line \($0) " + String(repeating: "a", count: 64) }.joined(separator: "\n") + "\n"
        for _ in 0..<6 { run.append(block, isError: false) }
        run.append("LAST\n", isError: false)
        XCTAssertTrue(run.dropped)
        XCTAssertLessThanOrEqual(run.bytes, ShellCommand.outputLimit)
        XCTAssertTrue(run.text.hasSuffix("LAST\n"))
    }

    func testVersionMovesOnEveryVisibleChange() {
        let run = made()
        let start = run.version
        run.append("x\n", isError: false)
        run.finish(exitCode: 0, duration: 0.1)
        run.toggleExpanded()
        XCTAssertGreaterThan(run.version, start + 2)
        XCTAssertFalse(run.isRunning)
        XCTAssertEqual(run.duration, 0.1)
    }

    func testFinishIsRecordedOnce() {
        let run = made()
        run.finish(exitCode: 3, duration: 1)
        run.finish(exitCode: 0, duration: 99)
        XCTAssertEqual(run.exitCode, 3)
        XCTAssertTrue(run.failed)
    }
}

/// The runner itself, against real (harmless) commands in a temporary folder.
final class ShellRunnerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs a command to completion on the main run loop and hands back what it printed.
    @discardableResult
    private func execute(_ command: String, timeout: TimeInterval = 20,
                         while running: ((ShellRunner) -> Void)? = nil) -> (run: ShellRun, code: Int32) {
        let run = ShellRun(command: command, directory: folder, agentFolder: folder)
        let done = expectation(description: command)
        var code: Int32 = -1
        let runner = ShellRunner(onOutput: { text, isError in run.append(text, isError: isError) },
                                 onExit: { status, duration in
                                     run.finish(exitCode: status, duration: duration)
                                     code = status
                                     done.fulfill()
                                 })
        runner.start(command: command, directory: folder, shell: "/bin/sh")
        running?(runner)
        wait(for: [done], timeout: timeout)
        return (run, code)
    }

    func testEcho() {
        let (run, code) = execute("echo hello")
        XCTAssertEqual(code, 0)
        XCTAssertTrue(run.text.contains("hello\n"))
        XCTAssertGreaterThan(run.duration, 0)
        XCTAssertFalse(run.isRunning)
    }

    func testExitCode() {
        XCTAssertEqual(execute("exit 3").code, 3)
    }

    func testStderrIsMarked() {
        let (run, code) = execute("echo out; echo boom 1>&2")
        XCTAssertEqual(code, 0)
        let lines = ShellBlock.lines(of: run)
        XCTAssertTrue(lines.contains { $0.text == "boom" && $0.isError })
        XCTAssertTrue(lines.contains { $0.text == "out" && !$0.isError })
    }

    func testRunsInTheGivenFolder() {
        let (run, code) = execute("pwd")
        XCTAssertEqual(code, 0)
        XCTAssertTrue(run.text.contains(folder.lastPathComponent))
    }

    func testStdinIsClosedSoInteractiveProgramsFailFast() {
        // With no terminal and /dev/null on stdin, a read ends at once instead of hanging.
        let (run, code) = execute("read line; echo \"got:[$line]\"")
        XCTAssertNotEqual(code, 128 + SIGKILL)
        XCTAssertTrue(run.text.contains("got:[]"))
    }

    func testLargeOutputIsCappedButKeepsTheEnd() {
        let (run, code) = execute("seq 1 100000", timeout: 60)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(run.dropped)
        XCTAssertLessThanOrEqual(run.bytes, ShellCommand.outputLimit)
        XCTAssertTrue(run.text.hasSuffix("100000\n"))
    }

    func testStopKillsTheCommand() {
        let (run, code) = execute("sleep 30") { runner in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { runner.stop() }
        }
        XCTAssertEqual(code, 128 + SIGTERM)
        XCTAssertTrue(run.failed)
        XCTAssertLessThan(run.duration, 10)
    }

    func testOutputBeforeAStopIsKept() {
        let (run, _) = execute("echo first; sleep 30") { runner in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runner.stop() }
        }
        XCTAssertTrue(run.text.contains("first"))
    }
}
