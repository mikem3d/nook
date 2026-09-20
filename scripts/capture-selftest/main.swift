// Headless checks for the capture/handoff pure logic. Run with Scripts/capture-selftest.sh.
// Touches no screen, no permission, no general pasteboard; disk use is a throwaway temp folder.
import AppKit

var failures = 0
func check(_ ok: @autoclosure () -> Bool, _ what: String, line: Int = #line) {
    if ok() { print("ok    \(what)") } else { failures += 1; print("FAIL  \(what) (line \(line))") }
}

// MARK: pasteboard classification
func item(_ fill: (NSPasteboardItem) -> Void) -> NSPasteboardItem { let i = NSPasteboardItem(); fill(i); return i }
let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])

let file = item { $0.setString("file:///tmp/a%20b/report.pdf", forType: .fileURL) }
check(DropClassifier.classify(file) == .file(URL(fileURLWithPath: "/tmp/a b/report.pdf")), "file URL becomes a file")

let fileWithPreview = item { $0.setString("file:///tmp/pic.png", forType: .fileURL); $0.setData(pngBytes, forType: .png) }
check(DropClassifier.classify(fileWithPreview) == .file(URL(fileURLWithPath: "/tmp/pic.png")), "a real file beats its image data")

let browserImage = item { $0.setString("https://example.com/cat.png", forType: .URL); $0.setData(pngBytes, forType: .tiff) }
check(DropClassifier.classify(browserImage) == .image(pngBytes, ext: "tiff"), "browser image: data beats its address")

let both = item { $0.setData(pngBytes, forType: .png); $0.setData(Data([1]), forType: .tiff) }
check(DropClassifier.classify(both) == .image(pngBytes, ext: "png"), "png preferred over tiff")

let link = item { $0.setString("https://example.com/x?y=1", forType: .URL); $0.setString("Example", forType: .string) }
check(DropClassifier.classify(link) == .link(URL(string: "https://example.com/x?y=1")!), "link beats its title text")

let fileAsURL = item { $0.setString("file:///tmp/folder/", forType: .URL) }
check(DropClassifier.classify(fileAsURL) == .file(URL(fileURLWithPath: "/tmp/folder")), "file scheme under public.url is a file")

check(DropClassifier.classify(text: "  https://example.com  ") == .link(URL(string: "https://example.com")!), "bare address in text is a link")
check(DropClassifier.classify(text: "see https://example.com") == .text("see https://example.com"), "sentence with an address stays text")
check(DropClassifier.classify(text: "ftp://x.y") == .text("ftp://x.y"), "non-web scheme stays text")
check(DropClassifier.classify(text: " \n ") == nil, "blank text is nothing")
check(DropClassifier.classify(item { _ in }) == nil, "empty item is nothing")
check(DropClassifier.classify([file, file, link]).count == 2, "duplicate files collapse")

// A private, uniquely named pasteboard: a round trip through the real pasteboard server types.
let board = NSPasteboard(name: NSPasteboard.Name("nook.selftest.\(UUID().uuidString)"))
board.clearContents()
board.writeObjects([URL(fileURLWithPath: "/tmp/one.txt") as NSURL, URL(fileURLWithPath: "/tmp/two.txt") as NSURL])
let round = DropClassifier.classify(board.pasteboardItems ?? [])
check(round == [.file(URL(fileURLWithPath: "/tmp/one.txt")), .file(URL(fileURLWithPath: "/tmp/two.txt"))], "two files through a private NSPasteboard")
board.releaseGlobally()

// MARK: payload and temp store
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nook-selftest-\(UUID().uuidString)")
let store = IntakeStore(directory: root.appendingPathComponent("Intake"))
let stamp = Date(timeIntervalSince1970: 1_789_000_000)
let name = IntakeStore.name(kind: "Drop!", ext: ".PNG", date: stamp, token: "ab12")
check(name.hasPrefix("drop-") && name.hasSuffix("-ab12.png") && !name.contains("!"), "temp name is sanitised: \(name)")
check(name.range(of: #"^drop-\d{8}-\d{6}-ab12\.png$"#, options: .regularExpression) != nil, "temp name has a sortable timestamp")
check(IntakeStore.name(kind: "", ext: "") .hasPrefix("item-") && IntakeStore.name(kind: "", ext: "").hasSuffix(".dat"), "empty kind/ext fall back")
check(IntakeStore.name(kind: "a", ext: "b") != IntakeStore.name(kind: "a", ext: "b"), "names do not collide")

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let tiff = rep.tiffRepresentation!
let payload = store.payload(from: [.file(URL(fileURLWithPath: "/tmp/a.txt")), .image(tiff, ext: "tiff"),
                                   .link(URL(string: "https://example.com")!), .text("hello")])
check(payload.files.count == 2 && payload.files[0].path == "/tmp/a.txt", "payload keeps files and adds the written image")
check(payload.files.last?.pathExtension == "png" && payload.files.last?.deletingLastPathComponent().path == store.directory.path,
      "tiff data lands in the store as png")
check((try? Data(contentsOf: payload.files.last!))?.prefix(4) == pngBytes, "written file really is a PNG")
check(payload.text == ["https://example.com", "hello"], "links and text ride along as text")
check(payload.message == "Look at this.\n\nhttps://example.com\n\nhello", "fallback message")
check(IntakePayload(files: [URL(fileURLWithPath: "/x")]).message == "Look at this.", "fallback message with files only")
check(IntakePayload().isEmpty, "empty payload")

let now = Date()
let old = try! store.write(Data("old".utf8), kind: "region", ext: "png")
let fresh = try! store.write(Data("new".utf8), kind: "region", ext: "png")
try! FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-IntakeStore.maxAge - 60)], ofItemAtPath: old.path)
check(IntakeStore.expired([(old, now.addingTimeInterval(-IntakeStore.maxAge - 1)), (fresh, now)], now: now) == [old], "expiry is by age")
let removed = store.cleanUp(now: now)
check(removed.map(\.lastPathComponent) == [old.lastPathComponent], "cleanup removes only the old file")
check(!FileManager.default.fileExists(atPath: old.path) && FileManager.default.fileExists(atPath: fresh.path), "disk agrees")
check(IntakeStore(directory: root.appendingPathComponent("missing")).cleanUp().isEmpty, "cleanup of a missing folder is harmless")
try? FileManager.default.removeItem(at: root)

// MARK: handoff message
var message = HandoffMessage(sourceLabel: "zipdemand", sourceFolder: "/Users/me/work/zipdemand",
                             summary: " 3 files changed, tests pass ", lastReply: "Fixed the zip lookup.", instruction: "  ")
var text = message.text
check(text.hasPrefix("[Handoff from another agent: \"zipdemand\"]"), "handoff starts with where it came from")
check(text.contains("Its folder: /Users/me/work/zipdemand"), "handoff carries the folder")
check(text.contains("How its last turn ended: 3 files changed, tests pass\n"), "handoff carries the trimmed summary")
check(text.contains("<<<\nFixed the zip lookup.\n>>>"), "handoff fences the last reply")
check(text.hasSuffix("What the user wants from you: " + HandoffMessage.defaultInstruction), "empty instruction uses the default")
message.instruction = "Port this fix."
check(message.text.hasSuffix("What the user wants from you: Port this fix."), "instruction is used when given")
message = HandoffMessage(sourceLabel: "demo", sourceFolder: nil, summary: "", lastReply: nil, instruction: "x")
text = message.text
check(text.contains("none (demo agent)") && text.contains("not replied") && !text.contains("last turn ended"), "demo agent with nothing to say")
let long = String(repeating: "a", count: 9000) + "END"
check(HandoffMessage.clip(long).hasSuffix("END") && HandoffMessage.clip(long).count < 8100 && HandoffMessage.clip(long).hasPrefix("[…"), "long replies keep their ending")
check(HandoffMessage.clip("short") == "short", "short replies untouched")

// MARK: hotkeys
let r = HotkeySpec("ctrl+opt+r")
check(r?.key == "r" && r?.modifiers == [.control, .option], "default region hotkey parses")
check(r?.keyCode == 15 && r?.carbonModifiers == UInt32(0x1000 | 0x0800), "carbon key code and modifiers")
check(HotkeySpec("⌃+⌥+R") == r && HotkeySpec("Control-Option-R") == r && HotkeySpec("alt ctrl r") == r, "spellings agree")
check(HotkeySpec("r") == nil && HotkeySpec("ctrl+opt") == nil && HotkeySpec("hyper+r") == nil && HotkeySpec("") == nil, "bad specs rejected")
check(HotkeySpec("cmd+shift+4")?.text == "shift+cmd+4", "text form is canonical")
for mode in GrabMode.allCases { check(HotkeySpec(mode.defaultHotkey) != nil, "default for \(mode.hotkeyPreference) parses") }
let prefs = UserDefaults(suiteName: "nook.selftest.\(UUID().uuidString)")!
check(HotkeySpec.preference("nook.hotkey.capture.region", default: "ctrl+opt+r", in: prefs) == r, "missing preference uses default")
prefs.set("garbage", forKey: "nook.hotkey.capture.region")
check(HotkeySpec.preference("nook.hotkey.capture.region", default: "ctrl+opt+r", in: prefs) == r, "bad preference uses default")
prefs.set("cmd+shift+9", forKey: "nook.hotkey.capture.region")
check(HotkeySpec.preference("nook.hotkey.capture.region", default: "ctrl+opt+r", in: prefs).key == "9", "good preference wins")

// MARK: grab planning (synthetic window list; nothing is captured)
func win(_ id: Int, pid: Int, layer: Int = 0, w: Double = 800, h: Double = 600, alpha: Double = 1) -> [String: Any] {
    [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
     kCGWindowBounds as String: ["X": 0.0, "Y": 0.0, "Width": w, "Height": h]]
}
let listing = [win(1, pid: 50, layer: 25), win(2, pid: 99), win(3, pid: 70, w: 20, h: 20), win(4, pid: 70, alpha: 0), win(5, pid: 60), win(6, pid: 70)]
check(GrabPlan.frontWindowID(in: listing, ownPID: 99, frontPID: 70) == 6, "front app's first real window; ours, slivers, invisible skipped")
check(GrabPlan.frontWindowID(in: listing, ownPID: 99, frontPID: nil) == 5, "no front app: topmost ordinary window")
check(GrabPlan.frontWindowID(in: listing, ownPID: 99, frontPID: 99) == 5, "never our own window even if we are frontmost")
check(GrabPlan.frontWindowID(in: [win(2, pid: 99)], ownPID: 99, frontPID: 99) == nil, "only our windows: nothing")
check(GrabPlan.captureRect(screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117), mainHeight: 1117) == "0,0,1728,1117", "main screen rect")
check(GrabPlan.captureRect(screenFrame: NSRect(x: 1728, y: 37, width: 1920, height: 1080), mainHeight: 1117) == "1728,0,1920,1080", "second screen flips to top-left origin")
check(GrabPlan.captureRect(screenFrame: NSRect(x: -1920, y: -200, width: 1920, height: 1080), mainHeight: 1117) == "-1920,237,1920,1080", "screen left and below")
check(GrabPlan.arguments(region: "/t/a.png") == ["-i", "-x", "/t/a.png"], "region arguments")
check(GrabPlan.arguments(window: 42, path: "/t/a.png") == ["-x", "-o", "-l", "42", "/t/a.png"], "window arguments")

// MARK: prompt placement
let area = NSRect(x: 0, y: 0, width: 1000, height: 800)
let size = NSSize(width: 340, height: 64)
check(MiniPanel.origin(for: size, beside: NSRect(x: 800, y: 12, width: 188, height: 140), in: area) == NSPoint(x: 452, y: 50), "prompt sits left of a right-docked window")
check(MiniPanel.origin(for: size, beside: NSRect(x: 12, y: 700, width: 188, height: 140), in: area) == NSPoint(x: 208, y: 728), "prompt sits right of a left-docked window, kept on screen")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
