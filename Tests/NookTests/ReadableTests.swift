import XCTest
@testable import Nook

final class ReadableTests: XCTestCase {
    // MARK: text size

    func testSizeTableAtEverySetting() {
        XCTAssertEqual(TextSize.medium.points(.body), 16)
        XCTAssertEqual(TextSize.medium.points(.input), 17)
        XCTAssertEqual(TextSize.small.points(.body), 13, "small is the size Nook first shipped with")
        XCTAssertEqual(TextSize.large.points(.body), 19)
        XCTAssertEqual(TextSize.extraLarge.points(.body), 22)
        for role in TextSize.Role.allCases {
            XCTAssertGreaterThanOrEqual(TextSize.medium.points(role), 12, "\(role) at the default")
            XCTAssertGreaterThanOrEqual(TextSize.small.points(role), 10, "\(role) at small")
            let sizes = TextSize.allCases.map { $0.points(role) }
            XCTAssertEqual(sizes, sizes.sorted(), "\(role) grows with the setting")
            XCTAssertEqual(Set(sizes).count, sizes.count, "\(role): every setting is a visible step")
        }
    }

    func testStoredMultiplierSnapsToTheTable() {
        XCTAssertEqual(TextSize.nearest(to: 1), .medium)
        XCTAssertEqual(TextSize.nearest(to: 0.5), .small)
        XCTAssertEqual(TextSize.nearest(to: 1.25), .large)
        XCTAssertEqual(TextSize.nearest(to: 9), .extraLarge)
        for size in TextSize.allCases { XCTAssertEqual(TextSize.nearest(to: size.rawValue), size) }
    }

    func testMetricsScaleWithTheSetting() {
        XCTAssertEqual(TextSize.medium.metric(28), 28)
        XCTAssertEqual(TextSize.extraLarge.metric(28), 39) // 38.5 rounds to a whole point
        XCTAssertEqual(TextSize.small.metric(28), 23)
        for size in TextSize.allCases {
            // A chip is always taller than its text, and the panel's minimum fits inside its default.
            XCTAssertGreaterThan(size.metric(28), size.points(.secondary) * 1.2)
            let (panel, minimum) = (ChatMetrics.panelSize(saved: nil, textSize: size), ChatMetrics.minimumSize(textSize: size))
            XCTAssertGreaterThan(panel.width, minimum.width)
            XCTAssertGreaterThan(panel.height, minimum.height)
        }
    }

    func testChatPanelSize() {
        XCTAssertEqual(ChatMetrics.panelSize(saved: nil, textSize: .medium), NSSize(width: 820, height: 560))
        XCTAssertGreaterThan(ChatMetrics.panelSize(saved: nil, textSize: .small).width, 660)
        XCTAssertEqual(ChatMetrics.panelSize(saved: NSSize(width: 100, height: 100), textSize: .medium), ChatMetrics.baseDefault, "too small to be real")
        // What the user dragged out at one size comes back the same at that size, and scaled at another.
        let dragged = NSSize(width: 1000, height: 700)
        for size in TextSize.allCases {
            let shown = ChatMetrics.panelSize(saved: ChatMetrics.baseSize(of: dragged, textSize: size), textSize: size)
            XCTAssertEqual(shown.width, dragged.width, accuracy: 1)
            XCTAssertEqual(shown.height, dragged.height, accuracy: 1)
        }
        let base = ChatMetrics.baseSize(of: dragged, textSize: .medium)
        XCTAssertEqual(ChatMetrics.panelSize(saved: base, textSize: .extraLarge).width, 1375)
    }

    func testLogFollowsTheTextSize() throws {
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: TextSize.key)
        defer {
            defaults.set(before, forKey: TextSize.key)
            TextSize.current = TextSize.nearest(to: (before as? Double) ?? 1)
        }
        var seen = 0
        let token = NotificationCenter.default.addObserver(forName: TextSize.changed, object: nil, queue: nil) { _ in seen += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        TextSize.current = .medium
        func bodySize() -> CGFloat {
            let text = LogRenderer.render(.message(.assistant, "hello"), expanded: false)
            return (text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).pointSize
        }
        XCTAssertEqual(bodySize(), 16)
        seen = 0
        TextSize.current = .extraLarge
        XCTAssertEqual(seen, 1, "one notification per change")
        XCTAssertEqual(bodySize(), 22)
        TextSize.current = .extraLarge
        XCTAssertEqual(seen, 1, "none when nothing changed")
        XCTAssertFalse(TextSize.step(1), "already the largest")
        XCTAssertTrue(TextSize.step(-1))
        XCTAssertEqual(TextSize.current, .large)

        // Nothing in the log is below 12 pt at the default, tool lines and system notes included.
        TextSize.current = .medium
        let items: [LogItem] = [.message(.assistant, "# H\ntext `code`\n```sh\nls\n```\n- a"), .message(.user, "u"), .message(.system, "note"),
                                .tools(start: 0, lines: ["a", "b", "c", "d"])]
        for item in items {
            let text = LogRenderer.render(item, expanded: true)
            text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                let font = value as! NSFont
                let visible = !(text.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if visible { XCTAssertGreaterThanOrEqual(font.pointSize, 12, (text.string as NSString).substring(with: range)) }
            }
        }
    }

    // MARK: pixel text

    func testFontPixelIsCrispAndAsLargeAsTheHeaderAllows() {
        // (window scale, backing, step) -> points per font pixel
        let table: [(CGFloat, CGFloat, Int, CGFloat)] = [
            (1, 2, 0, 1), (1.5, 2, 0, 1.5), (2, 2, 0, 1.5),     // Retina, default
            (1, 2, 1, 1), (1.5, 2, 1, 1.5), (2, 2, 1, 2),       // Retina, large text
            (1, 2, -1, 1), (1.5, 2, -1, 1), (2, 2, -1, 1),      // Retina, small text: as first shipped at 2x
            (1, 1, 0, 1), (2, 1, 0, 1), (2, 1, 1, 2),           // a 1x display has no half points
        ]
        for (s, backing, step, expected) in table {
            let fp = PixelFont.pixel(atScale: s, backing: backing, step: step)
            XCTAssertEqual(fp, expected, "\(s)x window, \(backing)x display, step \(step)")
            XCTAssertEqual((fp * backing).truncatingRemainder(dividingBy: 1), 0, "a whole number of device pixels")
            XCTAssertLessThanOrEqual(fp * CGFloat(PixelFont.cellH), RoomScene.bar * s, "the text cell fits the header bar")
        }
    }

    func testBubbleStillHoldsUsefulText() {
        for s in [1, 1.5, 2] as [CGFloat] {
            for step in [-1, 0, 1] {
                let fp = PixelFont.pixel(atScale: s, backing: 2, step: step)
                let width = PixelFont.bubbleWidth(atScale: s, pixel: fp)
                let columns = Int(width * s / (CGFloat(PixelFont.cellW) * fp))
                XCTAssertGreaterThanOrEqual(columns, 22, "\(s)x, step \(step)")
                XCTAssertLessThanOrEqual(width + 6 + 4, RoomScene.W - 16, "the bubble and its padding stay inside the chamber")
            }
        }
    }

    /// NOOK_PREVIEW=/some/folder swift test --filter ReadableTests: a 2x chamber at each pixel-text step.
    func testRenderPixelTextSteps() throws {
        guard let folder = ProcessInfo.processInfo.environment["NOOK_PREVIEW"] else { throw XCTSkip("set NOOK_PREVIEW to a folder") }
        let renderer = try OffscreenRenderer()
        let art = try Art()
        PixelFont.register(art.url("fonts/DepartureMono-Regular.otf"))
        let before = TextSize.current
        defer { TextSize.current = before }
        for size in [TextSize.small, .medium, .large] {
            TextSize.current = size
            let scene = RoomScene(art: art, roomIndex: 0, title: "a-very-long-project-folder-name-indeed", avatarSeed: "/a")
            scene.scaleMode = .fill
            scene.size = CGSize(width: RoomScene.W * 2, height: RoomScene.H * 2)
            scene.configure(scale: 1, minimised: false) // the scene starts at 2x; go away and back so it lays out
            scene.configure(scale: 2, minimised: false)
            scene.show(state: .talking, bubble: "The configurator pricing table is out of date. Want me to refresh it? I can also regenerate the PDF.", unread: 120)
            let url = URL(fileURLWithPath: folder).appendingPathComponent("pixel-text-\(size)-2x.png")
            try renderer.write(renderer.image(of: scene, seconds: 3), to: url)
        }
    }

    // MARK: focus overlay

    func testOverlayStateMachine() {
        var state = OverlayState()
        XCTAssertFalse(state.shown, "nothing is active")
        state.active = true
        XCTAssertTrue(state.shown)
        XCTAssertTrue(state.takesClicks)
        XCTAssertEqual(state.dim, 0.45)

        state.quiet = true
        XCTAssertFalse(state.shown, "never in quiet mode")
        XCTAssertFalse(state.takesClicks, "and then it swallows nothing")
        state.quiet = false

        state.capturing = true
        XCTAssertFalse(state.shown, "never during a screen grab")
        XCTAssertFalse(state.takesClicks)
        state.capturing = false
        XCTAssertTrue(state.shown)

        state.clickToDismiss = false
        XCTAssertTrue(state.shown)
        XCTAssertFalse(state.takesClicks, "click-through when the setting is off")

        state.opacity = 0
        XCTAssertFalse(state.shown, "zero opacity disables it")
        state.opacity = -3
        XCTAssertFalse(state.shown)
        state.opacity = 5
        XCTAssertEqual(state.dim, 0.9, "never fully black")

        // Every combination: shown exactly when active, not quiet, not capturing and visible.
        for bits in 0..<16 {
            let s = OverlayState(active: bits & 1 != 0, quiet: bits & 2 != 0, capturing: bits & 4 != 0, opacity: bits & 8 != 0 ? 0.45 : 0)
            XCTAssertEqual(s.shown, bits == 0b1001, "\(s)")
        }
    }

    func testOverlaySitsBetweenOtherAppsAndNook() {
        XCTAssertGreaterThan(NookLevel.focusOverlay.rawValue, NSWindow.Level.normal.rawValue)
        for level in [NookLevel.agent, NookLevel.chat, NookLevel.prompt, NookLevel.hud, NookLevel.ghost] {
            XCTAssertLessThan(NookLevel.focusOverlay.rawValue, level.rawValue)
        }
    }
}
