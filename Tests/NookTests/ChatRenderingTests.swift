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

    func testGroupsConsecutiveTools() {
        let items = LogModel.group(entries([(.user, "hi"), (.tool, "a"), (.tool, "b"), (.assistant, "ok"), (.tool, "c")]))
        XCTAssertEqual(items, [
            .message(.user, "hi"), .tools(start: 1, lines: ["a", "b"]), .message(.assistant, "ok"), .tools(start: 4, lines: ["c"]),
        ])
    }

    func testIncrementalAppendMatchesFullGrouping() {
        let all = entries([(.user, "go")] + (0..<20).map { (.tool, "t\($0)") } + [(.assistant, "done")])
        var items: [LogItem] = []
        var changes: [Int] = []
        for cut in [0, 1, 5, 21] {
            let next = [1, 5, 21, 22][changes.count]
            changes.append(LogModel.append(all[cut..<next], at: cut, to: &items))
        }
        XCTAssertEqual(items, LogModel.group(all))
        // user appended at 0; tool run created at 1; run at 1 grows (re-render it); assistant appended at 2.
        XCTAssertEqual(changes, [0, 1, 1, 2])
        XCTAssertEqual(items.count, 3)
    }

    func testToolBurstCollapsesAndExpands() {
        let burst = LogItem.tools(start: 1, lines: (0..<20).map { "Bash: step \($0)" })
        let collapsed = LogRenderer.render(burst, expanded: false)
        XCTAssertTrue(collapsed.string.hasPrefix("⚙ 20 tool calls ▸"))
        XCTAssertTrue(collapsed.string.contains("step 19"))
        XCTAssertFalse(collapsed.string.contains("step 3\n"))
        XCTAssertEqual(collapsed.attribute(.nookToggle, at: 0, effectiveRange: nil) as? Int, 1)

        let expanded = LogRenderer.render(burst, expanded: true)
        XCTAssertTrue(expanded.string.hasPrefix("⚙ 20 tool calls ▾\n"))
        XCTAssertEqual(expanded.string.components(separatedBy: "⚙ Bash").count - 1, 20)

        let short = LogRenderer.render(.tools(start: 0, lines: ["Read: a", "Read: b"]), expanded: false)
        XCTAssertEqual(short.string, "⚙ Read: a\n⚙ Read: b\n\n")
        XCTAssertNil(short.attribute(.nookToggle, at: 0, effectiveRange: nil))
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
        XCTAssertTrue(text.string.contains("⚙ 8 tool calls ▾\n⚙ Bash: step 0\n"))
        XCTAssertTrue(text.string.hasSuffix("ok\n\n\n"))
        session.simulate(.working, text: "Read: x", log: .tool)
        view.show(session)
        XCTAssertTrue(text.string.hasSuffix("⚙ Read: x\n\n"))
        XCTAssertTrue(text.string.contains("⚙ Bash: step 7\n"))
    }
}

final class ChatPanelTests: XCTestCase {
    /// Builds the panel off screen (never ordered front) and lays it out in each state.
    func testPanelLaysOutInEveryState() {
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
        XCTAssertEqual(panel.frame.width, 680)
    }
}
