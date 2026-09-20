import AppKit

/// The three ways to point at the screen.
enum GrabMode: String, CaseIterable {
    case region, window, screen

    var title: String {
        switch self {
        case .region: return "Look at Region…"
        case .window: return "Look at Front Window"
        case .screen: return "Look at This Screen"
        }
    }

    var hotkeyPreference: String { "nook.hotkey.capture.\(rawValue)" }

    var defaultHotkey: String {
        switch self {
        case .region: return "ctrl+opt+r"
        case .window: return "ctrl+opt+w"
        case .screen: return "ctrl+opt+s"
        }
    }
}

/// Pure planning for a grab: which window, which rectangle, which arguments. No capture happens here.
enum GrabPlan {
    /// Picks the frontmost ordinary window that is not ours from a `CGWindowListCopyWindowInfo`
    /// listing (front to back). Prefers the frontmost app; falls back to whatever is on top.
    static func frontWindowID(in listing: [[String: Any]], ownPID: Int32, frontPID: Int32?) -> UInt32? {
        func number(_ info: [String: Any], _ key: CFString) -> Int? { (info[key as String] as? NSNumber)?.intValue }
        let candidates = listing.filter { info in
            guard let pid = number(info, kCGWindowOwnerPID), pid != Int(ownPID) else { return false }
            guard number(info, kCGWindowLayer) == 0 else { return false }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0 { return false }
            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let w = (bounds["Width"] as? NSNumber)?.doubleValue, let h = (bounds["Height"] as? NSNumber)?.doubleValue,
               w < 40 || h < 40 { return false } // status items and other slivers
            return true
        }
        let chosen = candidates.first { frontPID != nil && number($0, kCGWindowOwnerPID) == frontPID.map(Int.init) } ?? candidates.first
        return chosen.flatMap { number($0, kCGWindowNumber) }.map(UInt32.init)
    }

    /// AppKit screen frame (origin bottom-left of the main screen) to the top-left based
    /// rectangle `screencapture -R` expects.
    static func captureRect(screenFrame: NSRect, mainHeight: CGFloat) -> String {
        let x = Int(screenFrame.minX.rounded()), y = Int((mainHeight - screenFrame.maxY).rounded())
        return "\(x),\(y),\(Int(screenFrame.width.rounded())),\(Int(screenFrame.height.rounded()))"
    }

    /// -x: silent. -i: the system's own region selection. -o: no window shadow.
    static func arguments(region path: String) -> [String] { ["-i", "-x", path] }
    static func arguments(window id: UInt32, path: String) -> [String] { ["-x", "-o", "-l", String(id), path] }
    static func arguments(rect: String, path: String) -> [String] { ["-x", "-R", rect, path] }
}

/// Runs the system `screencapture` tool. Only ever called from an explicit user action.
enum ScreenGrab {
    static let tool = "/usr/sbin/screencapture"

    /// Calls back on the main thread with the image file, or nil if the user cancelled or it failed.
    static func run(_ arguments: [String], output: URL, done: @escaping (URL?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                done(size > 0 ? output : nil)
            }
        }
        do { try process.run() } catch { done(nil) }
    }

    static func frontWindowID() -> UInt32? {
        let listing = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return GrabPlan.frontWindowID(in: listing, ownPID: ProcessInfo.processInfo.processIdentifier,
                                      frontPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

/// Screen Recording permission, handled in the open: say why first, ask once, then point at Settings.
enum ScreenAccess {
    private static let askedKey = "nook.capture.askedScreenAccess"
    private static let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// True if a grab may go ahead now. Otherwise the user has been told what to do.
    static func ensure() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let defaults = UserDefaults.standard
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        if !defaults.bool(forKey: askedKey) {
            alert.messageText = "Let Nook look at your screen?"
            alert.informativeText = "To show an agent a region, a window or a screen, macOS requires the Screen Recording permission. Nook only captures when you ask it to, and never its own windows. macOS will ask next, and may want Nook reopened afterwards."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Not Now")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            defaults.set(true, forKey: askedKey)
            return CGRequestScreenCaptureAccess()
        }
        alert.messageText = "Nook cannot see your screen"
        alert.informativeText = "Screen Recording is turned off for Nook. Turn it on in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen Nook."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(settings) }
        return false
    }
}

/// Opt-in: the frontmost app's selected text, read through Accessibility.
enum SelectedText {
    static let preference = "nook.capture.selection"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: preference) }

    /// Turning it on is the only moment the Accessibility prompt may appear.
    static func setOn(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: preference)
        guard on else { return }
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Nil when the option is off, permission is missing, or nothing is selected. Never prompts.
    static func current() -> String? {
        guard isOn, AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return label(text, from: app.localizedName)
    }

    static func label(_ text: String, from app: String?) -> String {
        "Selected text in \(app ?? "the front app"):\n\(text)"
    }
}
