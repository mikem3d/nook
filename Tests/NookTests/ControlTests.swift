import Carbon.HIToolbox
import XCTest
@testable import Nook

final class KeyComboTests: XCTestCase {
    func testDescriptionUsesStandardModifierOrder() {
        XCTAssertEqual(KeyCombo(kVK_ANSI_A, [.control, .option]).description, "⌃⌥A")
        XCTAssertEqual(KeyCombo(kVK_Space, [.control, .option]).description, "⌃⌥Space")
        XCTAssertEqual(KeyCombo(kVK_ANSI_K, [.command, .shift, .option, .control]).description, "⌃⌥⇧⌘K")
        XCTAssertEqual(KeyCombo(kVK_F5, []).description, "F5")
        XCTAssertEqual(KeyCombo(keyCode: 0x7F, modifiers: UInt32(cmdKey)).description, "⌘Key 127")
    }

    func testEncodingRoundTrips() {
        let combo = KeyCombo(kVK_ANSI_D, [.control, .option])
        XCTAssertEqual(combo.encoded, "\(controlKey | optionKey):\(kVK_ANSI_D)")
        XCTAssertEqual(KeyCombo(encoded: combo.encoded), combo)
    }

    func testDecodingRejectsGarbage() {
        for bad in ["", "abc", "1", "1:2:3", "-1:4", "256:999", "1:4", ":"] {
            XCTAssertNil(KeyCombo(encoded: bad), bad)
        }
    }

    func testIrrelevantModifierBitsAreDropped() {
        let flags: NSEvent.ModifierFlags = [.control, .capsLock, .numericPad, .function]
        XCTAssertEqual(KeyCombo(kVK_ANSI_A, flags), KeyCombo(kVK_ANSI_A, [.control]))
    }

    func testPlainKeysAreNotSafeGlobally() {
        XCTAssertFalse(KeyCombo(kVK_ANSI_A, []).isSafeGlobally)
        XCTAssertFalse(KeyCombo(kVK_ANSI_A, [.shift]).isSafeGlobally)
        XCTAssertTrue(KeyCombo(kVK_ANSI_A, [.option]).isSafeGlobally)
        XCTAssertTrue(KeyCombo(kVK_F6, []).isSafeGlobally)
    }

    func testStoredComboFallsBackAndCanBeSwitchedOff() throws {
        let suite = "nook.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fallback = KeyCombo(kVK_ANSI_A, [.control, .option])
        let custom = KeyCombo(kVK_ANSI_J, [.command, .shift])

        XCTAssertEqual(HotkeyCenter.stored(id: "x", fallback: fallback, defaults: defaults), fallback)
        defaults.set(custom.encoded, forKey: "nook.hotkey.x")
        XCTAssertEqual(HotkeyCenter.stored(id: "x", fallback: fallback, defaults: defaults), custom)
        defaults.set("", forKey: "nook.hotkey.x")
        XCTAssertNil(HotkeyCenter.stored(id: "x", fallback: fallback, defaults: defaults))
        defaults.set("nonsense", forKey: "nook.hotkey.x")
        XCTAssertEqual(HotkeyCenter.stored(id: "x", fallback: fallback, defaults: defaults), fallback)
    }
}

final class AttentionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testOldestPendingWins() {
        let agents = [
            Attention.Candidate(pendingSince: at(30)),
            Attention.Candidate(unread: 9),
            Attention.Candidate(pendingSince: at(10)),
            Attention.Candidate(pendingSince: at(20)),
        ]
        XCTAssertEqual(Attention.oldestPending(agents), 2)
    }

    func testOldestPendingTieGoesToStackOrderAndEmptyIsNil() {
        XCTAssertEqual(Attention.oldestPending([.init(pendingSince: at(5)), .init(pendingSince: at(5))]), 0)
        XCTAssertNil(Attention.oldestPending([.init(unread: 3), .init(finishedAt: at(1))]))
        XCTAssertNil(Attention.oldestPending([]))
    }

    func testNeedyOrderIsPendingThenUnreadThenRecentlyFinished() {
        var agents = [
            Attention.Candidate(finishedAt: at(50)),
            Attention.Candidate(unread: 2),
            Attention.Candidate(unread: 5, finishedAt: at(10)),
            Attention.Candidate(pendingSince: at(40)),
        ]
        XCTAssertEqual(Attention.mostNeedy(agents), 3)
        agents[3].pendingSince = nil
        XCTAssertEqual(Attention.mostNeedy(agents), 2)
        agents[1].unread = 0
        agents[2].unread = 0
        XCTAssertEqual(Attention.mostNeedy(agents), 0)
        agents[2].finishedAt = at(60)
        XCTAssertEqual(Attention.mostNeedy(agents), 2)
    }

    func testNeedyTiesAndNothing() {
        XCTAssertEqual(Attention.mostNeedy([.init(unread: 4), .init(unread: 4)]), 0)
        XCTAssertNil(Attention.mostNeedy([.init(), .init()]))
        XCTAssertNil(Attention.mostNeedy([]))
    }

    func testCycleWraps() {
        XCTAssertNil(Attention.next(after: nil, count: 0))
        XCTAssertEqual(Attention.next(after: nil, count: 3), 0)
        XCTAssertEqual(Attention.next(after: 0, count: 3), 1)
        XCTAssertEqual(Attention.next(after: 2, count: 3), 0)
    }

    func testApprovalGuard() {
        XCTAssertTrue(Attention.acceptsAnswer(now: at(0), lastConfirmationShown: nil, minimum: 0.3))
        XCTAssertFalse(Attention.acceptsAnswer(now: at(0.1), lastConfirmationShown: at(0), minimum: 0.3))
        XCTAssertTrue(Attention.acceptsAnswer(now: at(0.5), lastConfirmationShown: at(0), minimum: 0.3))
    }
}

final class QuietRuleTests: XCTestCase {
    func testMeetingAppMatchesBundleIDOrNameIgnoringCase() {
        let list = ["us.zoom.xos", " FaceTime ", ""]
        XCTAssertTrue(QuietMode.shouldBeQuiet(frontmostBundleID: "US.ZOOM.xos", frontmostName: "zoom.us", meetingApps: list, mirroring: false))
        XCTAssertTrue(QuietMode.shouldBeQuiet(frontmostBundleID: "com.apple.FaceTime", frontmostName: "FaceTime", meetingApps: list, mirroring: false))
        XCTAssertFalse(QuietMode.shouldBeQuiet(frontmostBundleID: "com.apple.Safari", frontmostName: "Safari", meetingApps: list, mirroring: false))
        XCTAssertFalse(QuietMode.shouldBeQuiet(frontmostBundleID: nil, frontmostName: nil, meetingApps: list, mirroring: false))
    }

    func testMirroringAloneIsEnough() {
        XCTAssertTrue(QuietMode.shouldBeQuiet(frontmostBundleID: "com.apple.Safari", frontmostName: "Safari", meetingApps: [], mirroring: true))
    }
}
