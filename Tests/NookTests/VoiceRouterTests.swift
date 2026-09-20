import XCTest
@testable import Nook

final class VoiceRouterTests: XCTestCase {
    typealias Agent = VoiceRouter.Agent
    typealias Decision = VoiceRouter.Decision

    private let agents = [Agent(label: "zipdemand"), Agent(label: "sternfall"),
                          Agent(label: "asche-kron", aliases: ["ash crown"])]

    private func route(_ text: String, agents: [Agent]? = nil, active: Int? = 0, recent: Int? = nil) -> Decision {
        VoiceRouter.route(text, agents: agents ?? self.agents, active: active, recent: recent)
    }

    // MARK: names

    func testExactNameIsStripped() {
        XCTAssertEqual(route("Sternfall, run the tests"), .send(to: [1], text: "run the tests"))
    }

    func testNameSplitIntoWords() {
        XCTAssertEqual(route("stern fall run the tests"), .send(to: [1], text: "run the tests"))
        XCTAssertEqual(route("Zip demand refresh the cache."), .send(to: [0], text: "refresh the cache."))
    }

    func testHyphenatedLabelAndAlias() {
        XCTAssertEqual(route("Asche Kron, update pricing", active: 1), .send(to: [2], text: "update pricing"))
        XCTAssertEqual(route("ash crown update pricing", active: 1), .send(to: [2], text: "update pricing"))
    }

    func testLeadInWord() {
        XCTAssertEqual(route("Hey sternfall, what's left?"), .send(to: [1], text: "what's left?"))
    }

    func testOneSlipInALongName() {
        XCTAssertEqual(route("stern falls run the tests"), .send(to: [1], text: "run the tests"))
        XCTAssertEqual(route("zip demands status"), .send(to: [0], text: "status"))
    }

    func testTwoSlipsFallBack() {
        XCTAssertEqual(route("stern balls run the tests", active: 0), .send(to: [0], text: "stern balls run the tests"))
    }

    func testShortNamesMustMatchExactly() {
        let agents = [Agent(label: "main"), Agent(label: "tests")]
        XCTAssertEqual(route("test the build", agents: agents, active: 0), .send(to: [0], text: "test the build"))
        XCTAssertEqual(route("tests, run again", agents: agents, active: 0), .send(to: [1], text: "run again"))
    }

    func testNameMustOpenTheSentence() {
        XCTAssertEqual(route("copy the fix from sternfall", active: 0), .send(to: [0], text: "copy the fix from sternfall"))
    }

    func testAmbiguousNameFallsBack() {
        let agents = [Agent(label: "frontend1"), Agent(label: "frontend2"), Agent(label: "api")]
        XCTAssertEqual(route("frontend3 build", agents: agents, active: 2), .send(to: [2], text: "frontend3 build"))
        XCTAssertEqual(route("frontend2 build", agents: agents, active: 2), .send(to: [1], text: "build"))
    }

    func testLongerNameWins() {
        let agents = [Agent(label: "zip"), Agent(label: "zipdemand")]
        XCTAssertEqual(route("zip demand go", agents: agents), .send(to: [1], text: "go"))
        XCTAssertEqual(route("zip go", agents: agents), .send(to: [0], text: "go"))
    }

    func testNameAloneIsNotSent() {
        guard case .hint = route("Sternfall.") else { return XCTFail() }
    }

    // MARK: broadcast and fallback

    func testBroadcast() {
        XCTAssertEqual(route("Everyone, commit your work"), .send(to: [0, 1, 2], text: "commit your work"))
        XCTAssertEqual(route("all agents stop"), .send(to: [0, 1, 2], text: "stop"))
    }

    func testAllWithoutAgentsIsOrdinaryText() {
        XCTAssertEqual(route("all tests should pass", active: 1), .send(to: [1], text: "all tests should pass"))
    }

    func testFallbackOrder() {
        XCTAssertEqual(route("run the tests", active: 2, recent: 1), .send(to: [2], text: "run the tests"))
        XCTAssertEqual(route("run the tests", active: nil, recent: 1), .send(to: [1], text: "run the tests"))
        guard case .hint = route("run the tests", active: nil, recent: nil) else { return XCTFail() }
    }

    func testStaleIndexIsIgnored() {
        XCTAssertEqual(route("run the tests", active: 9, recent: 1), .send(to: [1], text: "run the tests"))
    }

    func testNoAgentsOrNoSpeech() {
        guard case .hint = route("run the tests", agents: [], active: nil) else { return XCTFail() }
        guard case .hint = route("  …  ") else { return XCTFail() }
    }

    // MARK: approvals

    private var waiting: [Agent] {
        [Agent(label: "zipdemand"), Agent(label: "sternfall", hasPending: true)]
    }

    func testAllowActsOnActiveOnlyWhenPending() {
        XCTAssertEqual(route("Allow.", agents: waiting, active: 1), .permission(agent: 1, allow: true))
        XCTAssertEqual(route("approve", agents: waiting, active: 1), .permission(agent: 1, allow: true))
        XCTAssertEqual(route("Deny", agents: waiting, active: 1), .permission(agent: 1, allow: false))
        guard case .hint = route("allow", agents: waiting, active: 0) else { return XCTFail() }
    }

    func testAllowNeverGuessesAnAgent() {
        guard case .hint = route("allow", agents: waiting, active: nil, recent: 1) else { return XCTFail() }
    }

    func testNamedApproval() {
        XCTAssertEqual(route("Sternfall, allow", agents: waiting, active: 0), .permission(agent: 1, allow: true))
        XCTAssertEqual(route("deny stern fall", agents: waiting, active: 0), .permission(agent: 1, allow: false))
        guard case .hint = route("zipdemand allow", agents: waiting, active: 1) else { return XCTFail() }
    }

    func testVerdictInsideASentenceIsJustText() {
        XCTAssertEqual(route("allow the user to retry", agents: waiting, active: 1),
                       .send(to: [1], text: "allow the user to retry"))
        XCTAssertEqual(route("requests from that host we should deny", agents: waiting, active: 1),
                       .send(to: [1], text: "requests from that host we should deny"))
    }
}
