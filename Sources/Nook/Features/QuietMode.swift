import AppKit

/// Quiet mode: hides speech bubbles during meetings and screen sharing.
///
/// Manual: the menu item or the hotkey. Automatic, from signals that need no permission:
/// - a display is being mirrored (projector, AirPlay, most "share my whole screen" setups);
/// - the frontmost app is in the user's meeting-app list (bundle id or name).
/// Not used, on purpose: macOS Focus / Do Not Disturb (readable only with the Focus Status
/// permission plus an entitlement, or private API), camera and microphone state (no public,
/// permissionless API) and Google Meet in a browser (indistinguishable from browsing).
/// - the synced calendar says the user is in a meeting right now (`nook.quiet.calendar`; does
///   nothing until calendar sync has been used, since there are no events to go by).
/// Everything is notification driven. The calendar rule adds the only timer: one, set to the next
/// time a meeting starts or ends, and none when no meeting lies ahead.
///
/// Once the user toggles by hand, automatic changes stop until Nook is relaunched.
final class QuietMode: NSObject, Feature, NSMenuItemValidation {
    static let autoKey = "nook.quiet.auto"
    static let appsKey = "nook.quiet.apps"
    static let calendarKey = "nook.quiet.calendar"
    static let defaultApps = ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
                              "com.apple.FaceTime", "com.cisco.webexmeetingsapp"]

    /// Other features (the hotkey) reach the manual toggle through here.
    private(set) static weak var current: QuietMode?

    private weak var app: AppController?
    private var manual = false
    private var frontmost: (bundleID: String?, name: String?)
    private var boundary: Timer?

    func install(in app: AppController) {
        self.app = app
        Self.current = self
        UserDefaults.standard.register(defaults: [Self.autoKey: true, Self.appsKey: Self.defaultApps, Self.calendarKey: true])
        HUD.shared.isSuppressed = { [weak app] in app?.isQuiet ?? false }

        let item = NSMenuItem(title: "Quiet Mode", action: #selector(toggle), keyEquivalent: "")
        item.target = self
        app.addMenuItem(item)

        let front = NSWorkspace.shared.frontmostApplication
        frontmost = (front?.bundleIdentifier, front?.localizedName)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(evaluate),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(evaluate),
                                               name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(evaluate), name: .nookCalendarChanged, object: nil)
        // Asleep through a meeting's start or end: the timer fires late, so look again on wake.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(evaluate), name: NSWorkspace.didWakeNotification, object: nil)
        evaluate()
    }

    /// The manual switch. It wins over automatic detection for the rest of this run.
    @objc func toggle() {
        guard let app else { return }
        manual = true
        if app.isQuiet {
            app.isQuiet = false
            HUD.shared.show("Quiet mode off")
        } else {
            HUD.shared.show("Quiet mode on") // shown first: once quiet, this HUD would be suppressed
            app.isQuiet = true
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = app?.isQuiet == true ? .on : .off
        return true
    }

    @objc private func appActivated(_ note: Notification) {
        guard let front = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Nook coming forward (its settings window) says nothing about whether a meeting is on.
        guard front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        frontmost = (front.bundleIdentifier, front.localizedName)
        evaluate()
    }

    @objc private func evaluate() {
        guard Thread.isMainThread else { // defaults can change on any thread
            DispatchQueue.main.async { [weak self] in self?.evaluate() }
            return
        }
        boundary?.invalidate()
        boundary = nil
        guard let app, !manual else { return }
        let defaults = UserDefaults.standard
        let auto = defaults.bool(forKey: Self.autoKey)
        let events = auto && defaults.bool(forKey: Self.calendarKey) ? CalendarSync.current?.events ?? [] : []
        let now = Date()
        let wanted = auto && (MeetingClock.inMeeting(events, at: now) || Self.shouldBeQuiet(
            frontmostBundleID: frontmost.bundleID, frontmostName: frontmost.name,
            meetingApps: defaults.stringArray(forKey: Self.appsKey) ?? [], mirroring: Self.isMirroring))
        if app.isQuiet != wanted { app.isQuiet = wanted }
        guard let next = MeetingClock.nextBoundary(events, after: now) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.evaluate() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        boundary = timer
    }

    /// The automatic rule, as a pure function. List entries match a bundle id or an app name, ignoring case.
    static func shouldBeQuiet(frontmostBundleID: String?, frontmostName: String?, meetingApps: [String], mirroring: Bool) -> Bool {
        if mirroring { return true }
        let front = [frontmostBundleID, frontmostName].compactMap { $0?.lowercased() }
        return meetingApps.contains { entry in
            let wanted = entry.trimmingCharacters(in: .whitespaces).lowercased()
            return !wanted.isEmpty && front.contains(wanted)
        }
    }

    private static var isMirroring: Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsInMirrorSet(id) != 0
        }
    }
}
