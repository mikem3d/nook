import AppKit
import XCTest
@testable import Nook

final class MarkdownTests: XCTestCase {
    func testBlocks() {
        let source = """
        # Title
        First line
        second line

        - one
          continued
          - nested
        2) two
        ---
        ```swift
        let x = 1

        # not a heading
        ```
        after
        """
        XCTAssertEqual(Markdown.blocks(source), [
            .heading(level: 1, text: "Title"),
            .paragraph("First line\nsecond line"),
            .bullet(level: 0, text: "one\ncontinued"),
            .bullet(level: 1, text: "nested"),
            .numbered(level: 0, marker: "2.", text: "two"),
            .rule,
            .code(language: "swift", text: "let x = 1\n\n# not a heading"),
            .paragraph("after"),
        ])
    }

    func testUnterminatedFenceWhileStreaming() {
        XCTAssertEqual(Markdown.blocks("Look:\n```\nls -la"), [.paragraph("Look:"), .code(language: "", text: "ls -la")])
        XCTAssertEqual(Markdown.blocks("```py"), [.code(language: "py", text: "")])
    }

    func testNotLists() {
        XCTAssertEqual(Markdown.blocks("-5 degrees\n*bold* start\n#hashtag"), [.paragraph("-5 degrees\n*bold* start\n#hashtag")])
    }

    func testInlineStyles() {
        let text = Markdown.inline("a **bold** and *slanted* `code` [site](https://example.com) x", font: .systemFont(ofSize: 13), color: .labelColor)
        XCTAssertEqual(text.string, "a bold and slanted code site x")
        func traits(_ word: String) -> NSFontDescriptor.SymbolicTraits {
            let range = (text.string as NSString).range(of: word)
            return (text.attribute(.font, at: range.location, effectiveRange: nil) as! NSFont).fontDescriptor.symbolicTraits
        }
        XCTAssertTrue(traits("bold").contains(.bold))
        XCTAssertTrue(traits("slanted").contains(.italic))
        XCTAssertTrue(traits("code").contains(.monoSpace))
        XCTAssertFalse(traits("and").contains(.bold))
        let link = (text.string as NSString).range(of: "site")
        XCTAssertEqual(text.attribute(.link, at: link.location, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
    }

    func testInlineKeepsAwkwardText() {
        for plain in ["snake_case_name and other_name", "Array<Int> and a < b > c", "2 * 3 * 4", "path/to/file.swift:12"] {
            XCTAssertEqual(Markdown.inline(plain, font: .systemFont(ofSize: 13), color: .labelColor).string, plain)
        }
    }

    func testBareURLBecomesLink() {
        let text = Markdown.inline("see https://example.com/a now", font: .systemFont(ofSize: 13), color: .labelColor)
        let range = (text.string as NSString).range(of: "https")
        XCTAssertNotNil(text.attribute(.link, at: range.location, effectiveRange: nil))
        XCTAssertNil(text.attribute(.link, at: 0, effectiveRange: nil))
    }

    func testCodeBlockRendering() {
        let code = "let x = 1\nlet y = 2"
        let text = Markdown.render("Intro\n```swift\n\(code)\n```\nOutro")
        XCTAssertEqual(text.string, "Intro\nswift   Copy\n\(code)\n\nOutro\n")
        let copy = (text.string as NSString).range(of: "Copy")
        XCTAssertEqual(text.attribute(.nookCopy, at: copy.location, effectiveRange: nil) as? String, code)
        var block = NSRange()
        _ = text.attribute(.nookCode, at: copy.location, longestEffectiveRange: &block, in: NSRange(location: 0, length: text.length))
        XCTAssertEqual((text.string as NSString).substring(with: block), "swift   Copy\n\(code)\n")
        let body = (text.string as NSString).range(of: "let y")
        let font = text.attribute(.font, at: body.location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertNil(text.attribute(.nookCode, at: 0, effectiveRange: nil))
    }

    func testSoftBreaksStayInOneParagraph() {
        XCTAssertEqual(Markdown.render("a\nb").string, "a\u{2028}b\n")
        XCTAssertEqual(Markdown.render("- x\n1. y").string, "•\tx\n1.\ty\n")
    }
}

final class LogModelTests: XCTestCase {
    private func entries(_ spec: [(TranscriptEntry.Kind, String)]) -> [TranscriptEntry] {
        spec.map { TranscriptEntry(kind: $0.0, text: $0.1) }
    }

    private func row(_ name: String, id: String? = nil) -> ToolRow { ToolRow(id: id ?? name, name: name, status: .ok) }

    func testGroupsConsecutiveTools() {
        let items = LogModel.group(entries([(.user, "hi"), (.tool, "a"), (.tool, "b"), (.assistant, "ok"), (.tool, "c")]))
        XCTAssertEqual(items, [
            .message(.user, "hi"), .tools(start: 1, rows: [row("a", id: "1"), row("b", id: "2")]),
            .message(.assistant, "ok"), .tools(start: 4, rows: [row("c", id: "4")]),
        ])
    }

    /// The log redraws from the first item that differs, so a growing tool run re-renders one item
    /// and a new message re-renders none of what came before it.
    func testFirstChangeFindsTheOneItemThatMoved() {
        let all = entries([(.user, "go")] + (0..<20).map { (.tool, "t\($0)") } + [(.assistant, "done")])
        let early = LogModel.group(Array(all.prefix(5)))
        let later = LogModel.group(Array(all.prefix(6)))
        XCTAssertEqual(LogModel.firstChange(from: early, to: later), 1) // the run grew
        XCTAssertEqual(LogModel.firstChange(from: later, to: LogModel.group(all)), 1)
        XCTAssertNil(LogModel.firstChange(from: later, to: later))
        let full = LogModel.group(all)
        XCTAssertEqual(LogModel.firstChange(from: full, to: full + [.message(.system, "x")]), full.count)
        XCTAssertEqual(full.count, 3)
    }

    func testThinkingIsAnItemOfItsOwnAndCanBeHidden() {
        var spec = entries([(.user, "go")])
        spec.append(TranscriptEntry(kind: .thinking, text: "let me look", thinkingTokens: 40))
        spec += entries([(.assistant, "done")])
        XCTAssertEqual(LogModel.group(spec, openThinking: 1), [
            .message(.user, "go"), .thinking(start: 1, text: "let me look", tokens: 40, live: true),
            .message(.assistant, "done"),
        ])
        XCTAssertEqual(LogModel.group(spec, showThinking: false), [.message(.user, "go"), .message(.assistant, "done")])
    }

    func testMidTurnMessageSaysWhenItWillBeRead() {
        let typed = [TranscriptEntry(kind: .user, text: "also check the tests", midTurn: true)]
        XCTAssertEqual(LogModel.group(typed), [
            .message(.user, "also check the tests"),
            .message(.system, "sent mid-turn; the agent reads it at its next step"),
        ])
    }

    func testToolBurstCollapsesAndExpands() {
        let rows = (0..<20).map { ToolRow(id: "\($0)", name: "Bash", argument: "step \($0)", status: .ok, detail: "1 line") }
        let burst = LogItem.tools(start: 1, rows: rows)
        let collapsed = LogRenderer.render(burst, expanded: false)
        XCTAssertTrue(collapsed.string.hasPrefix("⚙ 20 tool calls ▸"))
        XCTAssertTrue(collapsed.string.contains("step 19"))
        XCTAssertFalse(collapsed.string.contains("step 3\n"))
        XCTAssertEqual(collapsed.attribute(.nookToggle, at: 0, effectiveRange: nil) as? Int, 1)

        let expanded = LogRenderer.render(burst, expanded: true)
        XCTAssertTrue(expanded.string.hasPrefix("⚙ 20 tool calls ▾\n"))
        XCTAssertEqual(expanded.string.components(separatedBy: "✓ Bash").count - 1, 20)

        let short = LogRenderer.render(.tools(start: 0, rows: [row("Read: a"), row("Read: b")]), expanded: false)
        XCTAssertEqual(short.string, "✓ Read: a\n✓ Read: b\n\n")
        XCTAssertNil(short.attribute(.nookToggle, at: 0, effectiveRange: nil))
    }

    /// A long burst may fold, but never over the call that is running right now.
    func testCollapsedBurstStillShowsTheRunningCall() {
        var rows = (0..<8).map { ToolRow(id: "\($0)", name: "Read", argument: "f\($0)", status: .ok, detail: "3 lines") }
        rows.insert(ToolRow(id: "live", name: "Bash", argument: "npm test", status: .running), at: 4)
        let text = LogRenderer.render(.tools(start: 0, rows: rows), expanded: false, spinner: "⠹").string
        XCTAssertTrue(text.contains("⠹ Bash  npm test"))
        XCTAssertFalse(text.contains("f7"))
    }

    func testThinkingRendersDimAndFoldsAway() {
        let live = LogRenderer.render(.thinking(start: 2, text: "weighing options", tokens: 120, live: true), expanded: false, spinner: "⠙")
        XCTAssertTrue(live.string.hasPrefix("⠙ Thinking…"))
        XCTAssertTrue(live.string.contains("120 tokens"))
        XCTAssertTrue(live.string.contains("weighing options"))

        let done = LogRenderer.render(.thinking(start: 2, text: "weighing options", tokens: 120, live: false), expanded: false)
        XCTAssertTrue(done.string.hasPrefix("✲ Thought · 120 tokens  ▸"))
        XCTAssertFalse(done.string.contains("weighing options"))
        XCTAssertEqual(done.attribute(.nookToggle, at: 0, effectiveRange: nil) as? Int, 2)
        XCTAssertTrue(LogRenderer.render(.thinking(start: 2, text: "weighing options", tokens: 120, live: false), expanded: true)
            .string.contains("weighing options"))

        // The text is usually withheld; the count carries the line on its own and nothing expands.
        let withheld = LogRenderer.render(.thinking(start: 0, text: "", tokens: 240, live: false), expanded: false)
        XCTAssertEqual(withheld.string, "✲ Thought · 240 tokens\n\n")
        XCTAssertNil(withheld.attribute(.nookToggle, at: 0, effectiveRange: nil))
    }

    func testStreamingLooksLikeTheFinalEntry() {
        let text = "Working on **it**\n\n```\nls"
        XCTAssertEqual(LogRenderer.renderStreaming(text), LogRenderer.render(.message(.assistant, text), expanded: false))
    }
}

final class ReplyChipTests: XCTestCase {
    private func transcript(_ spec: [(TranscriptEntry.Kind, String)]) -> [TranscriptEntry] {
        spec.map { TranscriptEntry(kind: $0.0, text: $0.1) }
    }

    func testSituation() {
        let finished = transcript([(.user, "go"), (.tool, "Bash"), (.assistant, "All done.")])
        XCTAssertEqual(ReplyChips.situation(busy: false, transcript: finished), .done)
        XCTAssertNil(ReplyChips.situation(busy: true, transcript: finished))
        XCTAssertNil(ReplyChips.situation(busy: false, transcript: []))
        XCTAssertNil(ReplyChips.situation(busy: false, transcript: transcript([(.assistant, "hi"), (.user, "go")])))
        let failed = finished + transcript([(.system, "The turn ended with an error.")])
        XCTAssertEqual(ReplyChips.situation(busy: false, transcript: failed), .failed)
    }

    func testUserTableOverridesBuiltIn() {
        let name = "nook.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ReplyChips.titles(for: .done, defaults: defaults).first, "Continue")
        XCTAssertEqual(ReplyChips.titles(for: nil, defaults: defaults), [])
        defaults.set(["done": ["Ship it"]], forKey: ReplyChips.defaultsKey)
        XCTAssertEqual(ReplyChips.titles(for: .done, defaults: defaults), ["Ship it"])
        XCTAssertEqual(ReplyChips.titles(for: .failed, defaults: defaults), ["Try again", "What went wrong?"])
    }
}

final class LogViewTests: XCTestCase {
    /// Appending entries one at a time must leave the same text as rendering everything at once,
    /// and must not disturb a selection earlier in the log.
    func testIncrementalUpdatesMatchFullRenderAndKeepSelection() {
        let session = AgentSession(label: "demo", cwd: nil)
        let view = LogView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        let text = view.documentView as! NSTextView

        session.send("Fix the bug")
        view.show(session)
        text.setSelectedRange(NSRange(location: 0, length: 3))
        for step in 0..<8 {
            session.simulate(.working, text: "Bash: step \(step)", log: .tool)
            view.show(session)
        }
        session.simulate(.talking, text: "Done. See `main.swift`:\n```\nok\n```", log: .assistant)
        view.show(session)
        view.show(session) // nothing new: must be a no-op

        let full = NSMutableAttributedString()
        LogModel.group(session.transcript).forEach { full.append(LogRenderer.render($0, expanded: false)) }
        XCTAssertEqual(text.string, full.string)
        XCTAssertTrue(text.string.contains("⚙ 8 tool calls ▸"))
        XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: 3))

        // Expanding the group in place keeps later items intact.
        let toggle = (text.string as NSString).range(of: "⚙ 8 tool calls")
        XCTAssertTrue(view.textView(text, clickedOnLink: Markdown.actionURL, at: toggle.location))
        XCTAssertTrue(text.string.contains("⚙ 8 tool calls ▾\n✓ Bash: step 0\n"))
        XCTAssertTrue(text.string.hasSuffix("ok\n\n\n"))
        session.simulate(.working, text: "Read: x", log: .tool)
        view.show(session)
        XCTAssertTrue(text.string.hasSuffix("✓ Read: x\n\n"))
        XCTAssertTrue(text.string.contains("✓ Bash: step 7\n"))
    }
}

final class ChatPanelTests: XCTestCase {
    /// Builds the panel off screen (never ordered front) and lays it out in each state.
    func testPanelLaysOutInEveryState() throws {
        let panel = ChatPanel()
        let session = AgentSession(label: "demo", cwd: nil)
        panel.render(session)
        panel.contentView?.layoutSubtreeIfNeeded()
        session.send("hello")
        session.simulate(.working, text: "Bash: ls", log: .tool)
        panel.render(session)
        panel.contentView?.layoutSubtreeIfNeeded()
        session.simulate(.done, text: "All **done**.", log: .assistant)
        panel.render(session)
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(panel.frame.size, ChatMetrics.panelSize(saved: nil, textSize: .current))

        // Live text-size changes: at every size the content still fits the panel's smallest frame
        // (Auto Layout would otherwise push the window wider or taller) and the input fits its font.
        let before = TextSize.current
        defer { TextSize.current = before }
        session.simulate(.alert, text: "Allow Bash?", log: .system)
        for size in TextSize.allCases {
            TextSize.current = size
            let minimum = ChatMetrics.minimumSize(textSize: size)
            panel.setFrame(NSRect(origin: .zero, size: minimum), display: false)
            panel.render(session)
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame.size, minimum, "\(size)")
            let input = try XCTUnwrap(Self.find(InputBox.self, in: panel.contentView))
            let font = try XCTUnwrap(input.textView.font)
            XCTAssertEqual(font.pointSize, size.points(.input))
            XCTAssertGreaterThanOrEqual(input.frame.height, NSLayoutManager().defaultLineHeight(for: font) + 8, "\(size)")
        }
    }

    /// A log longer than the card grows its text view and opens on the newest line; it once
    /// stopped at the visible height, clipping everything below with nothing to scroll to.
    func testLongLogScrollsToTheNewestLine() throws {
        let panel = ChatPanel()
        let session = AgentSession(label: "demo", cwd: nil)
        for i in 0..<30 { session.simulate(.done, text: "Paragraph \(i).", log: .assistant) }
        panel.render(session)
        panel.contentView?.layoutSubtreeIfNeeded()
        let log = try XCTUnwrap(Self.find(LogView.self, in: panel.contentView))
        let text = try XCTUnwrap(log.documentView)
        XCTAssertGreaterThan(text.frame.height, log.contentView.bounds.height)
        XCTAssertEqual(log.contentView.bounds.maxY, text.frame.height, accuracy: 1)
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }
}
