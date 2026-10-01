import AppKit

extension Notification.Name {
    /// The Claude Code login was checked and may have changed. Object: ClaudeAuth.
    static let nookAuthChanged = Notification.Name("nookAuthChanged")
}

/// Which account the agents run as, and a way to log in when there is none.
///
/// Nook has no account of its own: every agent is the user's `claude`, so the login is Claude
/// Code's. `claude auth status` says who that is; logging in runs `claude auth login` in Terminal,
/// where the browser hand-off, SSO and the paste-a-code fallback all work as they do by hand.
/// Nook then watches the status until the login lands and reconnects the agents that failed.
final class ClaudeAuth: Feature {
    static let loginTitle = "Log In to Claude…"
    /// How often, and for how long, a login started here is watched for.
    static let pollInterval: TimeInterval = 2
    static let pollLimit: TimeInterval = 10 * 60

    private(set) static weak var shared: ClaudeAuth?

    struct Status: Equatable {
        var loggedIn: Bool
        var email: String?
        var plan: String?

        /// `claude auth status --json`. Nil when the output is not that.
        static func parse(_ data: Data) -> Status? {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let loggedIn = json["loggedIn"] as? Bool else { return nil }
            return Status(loggedIn: loggedIn, email: json["email"] as? String,
                          plan: (json["subscriptionType"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() })
        }

        /// The account line in the menu bar menu.
        var menuTitle: String {
            guard loggedIn else { return ClaudeAuth.loginTitle }
            let who = email ?? "Claude"
            return plan.map { "Signed in as \(who) · \($0)" } ?? "Signed in as \(who)"
        }
    }

    private weak var app: AppController?
    private let item = NSMenuItem(title: "Checking Claude login…", action: nil, keyEquivalent: "")
    private(set) var status: Status?
    private var checking = false
    private var poll: Timer?
    private var pollStarted: Date?

    func install(in app: AppController) {
        self.app = app
        Self.shared = self
        item.target = self
        app.addMenuItem(item)
        NotificationCenter.default.addObserver(forName: .nookSessionChanged, object: nil, queue: .main) { [weak self] note in
            // A turn just failed for want of a login: the menu should say so too.
            if (note.object as? AgentWindow)?.session.needsLogin == true, self?.status?.loggedIn != false { self?.refresh() }
        }
        refresh()
    }

    /// Asks `claude auth status`, off the main thread; the answer lands on it.
    func refresh() {
        guard !checking, let claude = ClaudeLocator.path else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = Self.query(claude)
            DispatchQueue.main.async {
                self?.checking = false
                self?.update(status)
            }
        }
    }

    private static func query(_ claude: String) -> Status? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["auth", "status", "--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Status.parse(data)
    }

    private func update(_ new: Status?) {
        let gained = new?.loggedIn == true && status?.loggedIn != true
        status = new
        item.title = new?.menuTitle ?? "Claude login unknown"
        // Logged in, the line is a label; logged out (or unknown), it is the way in.
        item.action = new?.loggedIn == true ? nil : #selector(login)
        if gained {
            stopPolling()
            app?.windows.filter(\.session.needsLogin).forEach { $0.session.loggedIn(as: new?.email) }
        }
        NotificationCenter.default.post(name: .nookAuthChanged, object: self)
    }

    /// Opens Terminal on `claude auth login` and watches for it to finish. A `.command` file
    /// rather than AppleScript, so Terminal needs no Automation permission to run it.
    @objc func login() {
        guard let claude = ClaudeLocator.path else {
            NSSound.beep()
            return
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("nook-login.command")
        let body = """
        #!/bin/zsh
        clear
        echo "Logging Claude Code in for Nook. Finish in the browser, then come back to Nook."
        echo
        \(Self.quoted(claude)) auth login
        echo
        echo "You can close this window."

        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch {
            NSSound.beep()
            return
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", "Terminal", script.path]
        try? open.run()
        startPolling()
    }

    private func startPolling() {
        stopPolling()
        pollStarted = Date()
        poll = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let started = self.pollStarted, Date().timeIntervalSince(started) > Self.pollLimit { return self.stopPolling() }
            self.refresh()
        }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
        pollStarted = nil
    }

    /// Single-quoted for zsh: the path may hold spaces.
    static func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
