import XCTest
@testable import Nook

final class TaskSchedulerTests: XCTestCase {
    private typealias Agent = TaskScheduler.Agent
    private let (a, b) = ("/work/zipdemand", "/work/sternfall")

    private func task(_ title: String, _ agent: String?, _ status: NookTask.Status = .queued, priority: NookTask.Priority = .none,
                      after: [NookTask] = [], autoRun: Bool = false, due: Date? = nil) -> NookTask {
        NookTask(title: title, priority: priority, due: due, dueHasTime: due != nil, agent: agent, status: status,
                 after: after.map(\.id), autoRun: autoRun)
    }

    private func plan(_ tasks: [NookTask], _ agents: [Agent], limit: Int = 5) -> TaskScheduler.Plan {
        TaskScheduler.plan(tasks: tasks, agents: agents, limit: limit)
    }

    // MARK: the auto queue

    func testNothingIsSentUnlessAutoIsOnOrTheTaskIsMarked() {
        let one = task("one", a)
        XCTAssertEqual(plan([one], [Agent(key: a, state: .idle)]), .init(), "off by default means off")
        XCTAssertEqual(plan([one], [Agent(key: a, state: .idle, auto: true)]).sends, [.init(task: one.id, agent: a, source: .autoQueue)])
        let marked = task("marked, but waits on nothing", a, autoRun: true)
        XCTAssertEqual(plan([marked], [Agent(key: a, state: .idle)]), .init(), "the mark only means something on a task that waits")
        let urgent = task("urgent", a, priority: .urgent)
        XCTAssertEqual(plan([urgent], [Agent(key: a, state: .idle)]), .init(), "urgent bypasses nothing")
        XCTAssertEqual(plan([urgent], [Agent(key: a, state: .pendingPermission, auto: true)]), .init())
    }

    func testAutoWaitsWhileBusyOrAskingAndOneTaskAtATime() {
        let one = task("one", a)
        for state in [TaskScheduler.AgentState.busy, .pendingPermission] {
            XCTAssertEqual(plan([one], [Agent(key: a, state: state, auto: true)]), .init(), "\(state)")
        }
        for out in [NookTask.Status.sent, .running] {
            XCTAssertEqual(plan([task("out", a, out), one], [Agent(key: a, state: .idle, auto: true)]), .init(), "one at a time")
        }
    }

    func testAutoGoesByPriorityThenDueDateThenListOrder() {
        let soon = Date(timeIntervalSince1970: 2_000_000_000)
        let low = task("low", a, priority: .low)
        let first = task("first", a)
        let dated = task("dated", a, due: soon.addingTimeInterval(86_400))
        let sooner = task("sooner", a, due: soon)
        let high = task("high", a, priority: .high)
        let urgentElsewhere = task("urgent", b, priority: .urgent)
        let tasks = [first, low, dated, sooner, high, urgentElsewhere]
        XCTAssertEqual(tasks.ready(for: a).map(\.title), ["high", "low", "sooner", "dated", "first"])
        XCTAssertEqual(plan(tasks, [Agent(key: a, state: .idle, auto: true)]).sends.map(\.task), [high.id])
    }

    func testTheLimitAndAFailedTurnHoldRatherThanSend() {
        let one = task("one", a)
        XCTAssertEqual(plan([one], [Agent(key: a, state: .idle, auto: true, sentThisRun: 4)]).sends.count, 1)
        var result = plan([one], [Agent(key: a, state: .idle, auto: true, sentThisRun: 5)])
        XCTAssertTrue(result.sends.isEmpty)
        XCTAssertEqual(result.holds.map(\.source), [.autoQueue])
        XCTAssertTrue(result.holds[0].why.contains("limit of 5"))
        result = plan([one], [Agent(key: a, state: .lastTurnFailed, auto: true)])
        XCTAssertTrue(result.sends.isEmpty)
        XCTAssertEqual(result.holds.map(\.task), [one.id])
        XCTAssertEqual(plan([one], [Agent(key: a, state: .lastTurnFailed)]), .init(), "nothing to hold when nothing was going to go")
        XCTAssertEqual(plan([one], [Agent(key: a, state: .idle, auto: true, sentThisRun: 1)], limit: 1).holds.count, 1)
    }

    // MARK: chains

    func testAChainAcrossAgentsAdvancesOnlyWhenThePrerequisiteIsDone() {
        var x = task("X", a)
        let y = task("Y", b, after: [x], autoRun: true)
        let agents = [Agent(key: a, state: .idle), Agent(key: b, state: .idle)]
        for status in [NookTask.Status.queued, .sent, .running] {
            x.status = status
            XCTAssertEqual(plan([x, y], agents), .init(), "\(status)")
            XCTAssertEqual([x, y].blocker(of: y), .waiting([x.id]))
        }
        x.status = .done
        XCTAssertNil([x, y].blocker(of: y))
        XCTAssertEqual(plan([x, y], agents).sends, [.init(task: y.id, agent: b, source: .chain)])
    }

    func testAChainNeedsTheMarkOrTheDependentsAgentOnAuto() {
        let x = task("X", a, .done)
        let y = task("Y", b, after: [x])
        XCTAssertEqual(plan([x, y], [Agent(key: a, state: .idle, auto: true), Agent(key: b, state: .idle)]), .init(),
                       "auto on the agent that finished does not move the other agent's task")
        XCTAssertEqual(plan([x, y], [Agent(key: a, state: .idle), Agent(key: b, state: .idle, auto: true)]).sends,
                       [.init(task: y.id, agent: b, source: .autoQueue)])
    }

    func testNothingRunsPastAFailedCancelledOrDeletedPrerequisite() {
        let agents = [Agent(key: a, state: .idle, auto: true), Agent(key: b, state: .idle, auto: true)]
        for status in [NookTask.Status.failed, .cancelled] {
            let x = task("X", a, status)
            let y = task("Y", b, priority: .urgent, after: [x], autoRun: true)
            let z = task("Z", b, after: [y], autoRun: true)
            XCTAssertEqual(plan([x, y, z], agents), .init(), "\(status)")
            XCTAssertEqual([x, y, z].blocker(of: y), .broken(x.id, status))
            XCTAssertTrue([x, y, z].blockText(.broken(x.id, status)).contains("“X” (zipdemand)"), "it says why")
            XCTAssertEqual([x, y, z].blocker(of: z), .waiting([y.id]))
        }
        let gone = task("gone", a)
        let orphan = task("orphan", b, after: [gone], autoRun: true)
        XCTAssertEqual([orphan].blocker(of: orphan), .missing)
        XCTAssertEqual(plan([orphan], agents), .init())
    }

    func testABlockedTaskDoesNotHoldUpTheRestOfTheQueue() {
        let x = task("X", a, .failed)
        let blocked = task("blocked", b, priority: .urgent, after: [x])
        let free = task("free", b)
        XCTAssertEqual(plan([x, blocked, free], [Agent(key: b, state: .idle, auto: true)]).sends.map(\.task), [free.id])
    }

    func testChainedSendsCountTowardTheLimitAndRespectTheAgent() {
        let x = task("X", a, .done)
        let y = task("Y", b, after: [x], autoRun: true)
        var result = plan([x, y], [Agent(key: b, state: .idle, sentThisRun: 5)])
        XCTAssertTrue(result.sends.isEmpty)
        XCTAssertEqual(result.holds, [.init(task: y.id, agent: b, source: .chain, why: "it reached its limit of 5 automatic tasks in a row")])
        result = plan([x, y], [Agent(key: b, state: .lastTurnFailed)])
        XCTAssertTrue(result.sends.isEmpty)
        XCTAssertEqual(result.holds.map(\.source), [.chain])
        XCTAssertEqual(plan([x, y], [Agent(key: b, state: .pendingPermission)]), .init())
        XCTAssertEqual(plan([x, y], [Agent(key: b, state: .busy)]), .init())
    }

    func testWithAutoOffOnlyTheMarkedTaskGoesEvenIfAnotherOutranksIt() {
        let x = task("X", a, .done)
        let marked = task("marked", b, after: [x], autoRun: true)
        let urgent = task("urgent", b, priority: .urgent)
        XCTAssertEqual(plan([x, urgent, marked], [Agent(key: b, state: .idle)]).sends.map(\.task), [marked.id])
        XCTAssertEqual(plan([x, urgent, marked], [Agent(key: b, state: .idle, auto: true)]).sends.map(\.task), [urgent.id])
    }

    // MARK: agents

    func testMissingClosedAndInboxTasksAreNeverSent() {
        let x = task("X", a, .done)
        let y = task("Y", b, after: [x], autoRun: true)
        let inbox = task("inbox", nil, after: [x], autoRun: true)
        XCTAssertEqual(plan([x, y, inbox], []), .init())
        XCTAssertEqual(plan([x, y, inbox], [Agent(key: a, state: .idle, auto: true)]), .init(), "b is closed")
    }

    func testTwoAgentsFinishingAtOnceEachGetOneTaskAndNoTaskGoesTwice() {
        let x = task("X", a, .done)
        let w = task("W", b, .done)
        let y = task("Y", b, after: [x], autoRun: true)
        let y2 = task("Y2", b, after: [x], autoRun: true)
        let v = task("V", a, after: [w, x], autoRun: true)
        let tasks = [x, w, y, y2, v]
        let agents = [Agent(key: a, state: .idle), Agent(key: b, state: .idle)]
        XCTAssertEqual(plan(tasks, agents).sends, [.init(task: v.id, agent: a, source: .chain), .init(task: y.id, agent: b, source: .chain)])
        // Two windows on one folder are one agent.
        XCTAssertEqual(plan(tasks, agents + agents).sends.count, 2)
        // Once Y is out, Y2 waits its turn.
        var next = tasks
        next[2].status = .sent
        next[4].status = .sent
        XCTAssertEqual(plan(next, [Agent(key: a, state: .busy), Agent(key: b, state: .busy)]), .init())
        XCTAssertEqual(plan(next, agents), .init(), "even if the agent looks idle, its task is still out")
    }

    func testPlanIsDeterministic() {
        let x = task("X", a, .done)
        let tasks = [x] + (0..<6).map { task("t\($0)", $0 % 2 == 0 ? a : b, after: [x], autoRun: true) }
        let agents = [Agent(key: b, state: .idle), Agent(key: a, state: .idle)]
        XCTAssertEqual(plan(tasks, agents), plan(tasks, agents))
        XCTAssertEqual(plan(tasks, agents).sends.map(\.agent), [b, a], "in the agents' order")
    }

    // MARK: the user's own send

    func testRefusalSaysWhyATaskCannotGoNow() {
        let x = task("X", a, .failed)
        let y = task("Y", b, after: [x])
        let free = task("free", b)
        let tasks = [x, y, free, task("inbox", nil)]
        let idle = Agent(key: b, state: .idle)
        XCTAssertNil(TaskScheduler.refusal(free, in: tasks, agent: idle))
        XCTAssertNil(TaskScheduler.refusal(free, in: tasks, agent: Agent(key: b, state: .lastTurnFailed)), "the user may follow a failed turn")
        XCTAssertEqual(TaskScheduler.refusal(y, in: tasks, agent: idle), "Blocked: “X” (zipdemand) failed")
        XCTAssertEqual(TaskScheduler.refusal(tasks[3], in: tasks, agent: nil), "Assign it to an agent first")
        XCTAssertEqual(TaskScheduler.refusal(free, in: tasks, agent: nil), "sternfall is not open")
        XCTAssertNotNil(TaskScheduler.refusal(free, in: tasks, agent: Agent(key: b, state: .busy)))
        XCTAssertNotNil(TaskScheduler.refusal(free, in: tasks, agent: Agent(key: b, state: .pendingPermission)))
        XCTAssertNotNil(TaskScheduler.refusal(x, in: tasks, agent: Agent(key: a, state: .idle)), "not queued")
        XCTAssertNotNil(TaskScheduler.refusal(free, in: tasks + [task("out", b, .running)], agent: idle))
    }

    // MARK: prompts

    func testTheDependentsPromptCarriesResultsAndFolders() {
        var x = task("Build the API", a, .done)
        x.result = "3 files changed, tests pass"
        var demo = task("Demo step", "demo:Pip", .done)
        demo.result = ""
        let unfinished = task("Not yet", a)
        var y = task("Write the client", b, after: [x, demo, unfinished])
        y.notes = "Use the new endpoints."
        let tasks = [x, demo, unfinished, y]
        let prompt = TaskPrompt.compose(y, in: tasks)
        XCTAssertTrue(prompt.hasPrefix("Write the client\n\nUse the new endpoints.\n\nContext:"))
        XCTAssertTrue(prompt.contains("- “Build the API” (ran in /work/zipdemand): 3 files changed, tests pass"))
        XCTAssertTrue(prompt.contains("- “Demo step”: no summary was reported"), "a demo agent has no folder")
        XCTAssertFalse(prompt.contains("Not yet"))
        XCTAssertEqual(TaskPrompt.compose(x, in: tasks), "Build the API")

        let labels: (String) -> String = NookTask.label(forAgent:)
        XCTAssertEqual(TaskPrompt.note(x, in: tasks, source: nil, labels: labels), "Queued task: Build the API")
        let chained = TaskPrompt.note(y, in: tasks, source: .chain, labels: labels)
        XCTAssertTrue(chained.hasPrefix("Queued task (chained, sent automatically"))
        // The notifications feature tells unattended sends from the user's own by these words.
        XCTAssertTrue(AgentTransition.isAutomaticRun(chained))
        XCTAssertTrue(AgentTransition.isAutomaticRun(TaskPrompt.note(x, in: tasks, source: .autoQueue, labels: labels)))
        XCTAssertFalse(AgentTransition.isAutomaticRun(TaskPrompt.note(x, in: tasks, source: nil, labels: labels)))
        XCTAssertTrue(chained.contains("“Build the API” (zipdemand)"), "names what it waited on: \(chained)")
        XCTAssertTrue(TaskPrompt.note(x, in: tasks, source: .autoQueue, labels: labels).contains("auto queue"))
    }
}
