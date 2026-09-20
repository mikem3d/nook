import AppKit

/// The chat panel's attachment tray, as seen from here. The chat engineer builds the real thing
/// in parallel; once ChatPanel conforms (`extension ChatPanel: AttachmentStaging {}`), drops and
/// screen grabs are staged next to the input instead of being sent straight away.
protocol AttachmentStaging: AnyObject {
    func stage(_ urls: [URL])
}

/// The single path from "the user pointed at something" to "the agent has it".
enum Intake {
    /// AppController exposes no chat accessor, so the tray is found among the app's windows.
    static var staging: AttachmentStaging? {
        NSApp.windows.lazy.compactMap { $0 as? AttachmentStaging }.first
    }

    /// Activates the agent, then stages the items, or sends them with a default message if
    /// there is nowhere to stage. Never sends when staging is possible: the user adds the words.
    static func deliver(_ payload: IntakePayload, to window: AgentWindow, in app: AppController,
                        store: IntakeStore = .standard) {
        guard !payload.isEmpty else { return }
        app.activate(window)
        if let staging {
            var urls = payload.files
            if !payload.text.isEmpty,
               let snippet = try? store.write(Data(payload.text.joined(separator: "\n\n").utf8), kind: "text", ext: "txt") {
                urls.append(snippet)
            }
            staging.stage(urls)
        } else {
            window.session.send(payload.message, attachments: payload.files)
        }
    }

    /// The active agent, the only agent, or whichever one the user picks from a tiny menu at the pointer.
    static func chooseAgent(in app: AppController, title: String, then: @escaping (AgentWindow) -> Void) {
        if let active = app.active { return then(active) }
        if app.windows.count == 1 { return then(app.windows[0]) }
        guard !app.windows.isEmpty else { return NSSound.beep() }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for window in app.windows {
            menu.addItem(ClosureItem(window.session.label) { then(window) })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure, for menus built on the fly.
final class ClosureItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}
