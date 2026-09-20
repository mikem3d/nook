import AppKit
import Carbon.HIToolbox

/// Push-to-talk, transcribed on device, routed by agent name.
///
/// Hold the key, speak, release. "sternfall, run the tests" goes to sternfall; "everyone, …" goes
/// to all; anything else goes to the active agent, else the last one used. "allow" and "deny"
/// answer a pending permission. The pieces live in Voice/: the key, the recogniser, the HUD and
/// the (pure, unit-tested) router. Nothing here runs until the key is pressed.
final class Voice: Feature {
    /// Id in the shared HotkeyCenter; the chosen combo persists under `nook.hotkey.voice`.
    static let hotkeyID = "voice"
    /// Extra spoken names per agent label, for labels the recogniser mangles:
    /// `defaults write dev.nook.app nook.voice.aliases -dict asche-kron '("ash crown")'`
    static let aliasesKey = "nook.voice.aliases"

    private weak var app: AppController?
    private let capture = VoiceCapture()
    private lazy var hud = VoiceHUD()

    private var holding = false
    private var pressedAt = Date.distantPast
    private var partial = ""
    /// The agent last activated or last spoken to by name.
    private weak var recent: AgentWindow?

    func install(in app: AppController) {
        self.app = app
        HotkeyCenter.shared.register(id: Self.hotkeyID, title: "Hold to talk",
                                     defaultCombo: KeyCombo(kVK_ANSI_V, [.control, .option]),
                                     onPress: { [weak self] in self?.pressed() },
                                     onRelease: { [weak self] in self?.released() })
        let item = NSMenuItem(title: "Hold \(shownKey) to Talk", action: nil, keyEquivalent: "")
        item.isEnabled = false
        app.addMenuItem(item)
        capture.onLevel = { [weak self] in self?.hud.level($0) }
        capture.onPartial = { [weak self] in self?.heard($0) }
        capture.onFinish = { [weak self] in self?.finished($0) }
        recent = app.active
        NotificationCenter.default.addObserver(forName: .nookActiveChanged, object: app, queue: .main) { [weak self] _ in
            if let active = self?.app?.active { self?.recent = active }
        }
    }

    private var shownKey: String {
        HotkeyCenter.shared.info(for: Self.hotkeyID)?.combo?.description ?? "the talk key"
    }

    // MARK: key

    private func pressed() {
        guard !holding, !capture.isBusy else { return }
        holding = true
        pressedAt = Date()
        partial = ""
        capture.requestAccess { [weak self] access in
            guard let self else { return }
            switch access {
            case .blocked(let problem):
                self.holding = false
                self.hud.notice("Voice", detail: problem.message, link: problem.settingsURL)
            case .readyAfterPrompt:
                self.holding = false
                self.hud.notice("Voice is ready", detail: "Hold \(self.shownKey) and speak.")
            case .ready:
                guard self.holding else { return } // released before we got here
                self.listen()
            }
        }
    }

    private func listen() {
        let agents = snapshot().agents
        if let problem = capture.start(vocabulary: agents.flatMap { [$0.label] + $0.aliases }) {
            holding = false
            hud.notice("Voice", detail: problem.message, link: problem.settingsURL)
            return
        }
        heard("")
    }

    private func released() {
        guard holding else { return }
        holding = false
        capture.finish()
    }

    // MARK: transcript

    private func heard(_ text: String) {
        partial = text
        hud.listen(to: destination(for: text), transcript: text)
    }

    /// Who the words so far would go to, for the HUD.
    private func destination(for text: String) -> String {
        let (windows, agents, active, recent) = snapshot()
        guard !text.isEmpty else {
            // Nothing said yet: show where an unaddressed message would land.
            guard let index = active ?? recent else { return "Start with an agent's name" }
            return "To " + windows[index].session.label
        }
        switch VoiceRouter.route(text, agents: agents, active: active, recent: recent) {
        case .send(let to, _): return "To " + name(of: to, in: windows)
        case .permission(let index, let allow): return "\(allow ? "Allow" : "Deny") for \(windows[index].session.label)"
        case .hint: return "Listening"
        }
    }

    private func finished(_ text: String) {
        // A tap on the key with nothing said is not worth a message.
        if text.isEmpty, Date().timeIntervalSince(pressedAt) < 0.6 { return hud.dismiss() }
        guard let app else { return hud.dismiss() }
        let (windows, agents, active, recent) = snapshot()
        switch VoiceRouter.route(text, agents: agents, active: active, recent: recent) {
        case .send(let to, let message):
            for index in to {
                // Never `activate`: speaking to an agent must not pull focus to it.
                if windows[index] === app.active { app.send(message) } else { windows[index].session.send(message) }
            }
            if to.count == 1 { self.recent = windows[to[0]] }
            hud.notice("Sent to " + name(of: to, in: windows), detail: message)
        case .permission(let index, let allow):
            let session = windows[index].session
            guard let request = session.pending else { return hud.dismiss() }
            app.answer(windows[index], allow: allow)
            hud.notice("\(allow ? "Allowed" : "Denied") for \(session.label)",
                       detail: [request.tool, request.summary].filter { !$0.isEmpty }.joined(separator: ": "))
        case .hint(let hint):
            hud.notice("Not sent", detail: hint)
        }
    }

    // MARK: state

    private func snapshot() -> (windows: [AgentWindow], agents: [VoiceRouter.Agent], active: Int?, recent: Int?) {
        let windows = app?.windows ?? []
        let aliases = UserDefaults.standard.dictionary(forKey: Self.aliasesKey) as? [String: [String]] ?? [:]
        let agents = windows.map {
            VoiceRouter.Agent(label: $0.session.label, aliases: aliases[$0.session.label] ?? [], hasPending: $0.session.pending != nil)
        }
        return (windows, agents,
                windows.firstIndex { $0 === app?.active },
                windows.firstIndex { $0 === recent })
    }

    private func name(of indices: [Int], in windows: [AgentWindow]) -> String {
        indices.count == 1 ? windows[indices[0]].session.label : "everyone (\(indices.count))"
    }
}
