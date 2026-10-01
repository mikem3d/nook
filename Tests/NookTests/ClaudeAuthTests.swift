import XCTest
@testable import Nook

final class ClaudeAuthTests: XCTestCase {
    func testParsesLoggedInStatus() throws {
        let json = #"{"loggedIn":true,"authMethod":"claude.ai","email":"a@b.co","subscriptionType":"team"}"#
        let status = try XCTUnwrap(ClaudeAuth.Status.parse(Data(json.utf8)))
        XCTAssertEqual(status, .init(loggedIn: true, email: "a@b.co", plan: "Team"))
        XCTAssertEqual(status.menuTitle, "Signed in as a@b.co · Team")
    }

    func testParsesLoggedOutStatus() throws {
        let status = try XCTUnwrap(ClaudeAuth.Status.parse(Data(#"{"loggedIn":false,"authMethod":"none"}"#.utf8)))
        XCTAssertFalse(status.loggedIn)
        XCTAssertEqual(status.menuTitle, ClaudeAuth.loginTitle)
    }

    func testRejectsOtherOutput() {
        XCTAssertNil(ClaudeAuth.Status.parse(Data("Not logged in".utf8)))
        XCTAssertNil(ClaudeAuth.Status.parse(Data(#"{"email":"a@b.co"}"#.utf8)))
    }

    func testQuotesPathsForTheShell() {
        XCTAssertEqual(ClaudeAuth.quoted("/a b/it's"), #"'/a b/it'\''s'"#)
    }

    /// The events `claude -p` sends when it has no login (recorded from Claude Code 2.1).
    func testLoggedOutTurnAsksForALogin() {
        let session = AgentSession(label: "demo", cwd: nil)
        session.send("hi")
        session.feed(["type": "assistant", "error": "authentication_failed", "message": [
            "model": "<synthetic>", "role": "assistant",
            "content": [["type": "text", "text": "Not logged in · Please run /login"]]]])
        session.feed(["type": "result", "subtype": "success", "is_error": true, "result": "Not logged in · Please run /login"])

        XCTAssertTrue(session.needsLogin)
        XCTAssertEqual(session.summary, "Not logged in")
        XCTAssertFalse(session.transcript.contains { $0.text.contains("/login") })
        XCTAssertTrue(session.transcript.last?.text.contains(ClaudeAuth.loginTitle) == true)

        session.loggedIn(as: "a@b.co")
        XCTAssertFalse(session.needsLogin)
        XCTAssertEqual(session.transcript.last?.text, "Logged in as a@b.co. Send your message again.")
    }

    func testAnOrdinaryErrorIsNotALoginProblem() {
        let session = AgentSession(label: "demo", cwd: nil)
        session.send("hi")
        session.feed(["type": "result", "subtype": "error_during_execution", "is_error": true, "result": "boom"])
        XCTAssertFalse(session.needsLogin)
        XCTAssertEqual(session.summary, "Something went wrong")
    }
}
