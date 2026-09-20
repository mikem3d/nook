import AppKit

/// Look at this: hand a screen grab or dropped files to an agent.
/// Grabs happen only from a menu item, a context menu item or a hotkey, never on their own.
final class Capture: Feature {
    /// Agent windows reach the feature through here for their context menu.
    private(set) static weak var shared: Capture?

    private weak var app: AppController?
    private let store = IntakeStore.standard
    private var grabbing = false
    private var selectionItem: NSMenuItem?

    func install(in app: AppController) {
        self.app = app
        Self.shared = self
        store.cleanUp()

        let submenu = NSMenu(title: "Look at This")
        for mode in GrabMode.allCases {
            let key = HotkeySpec.preference(mode.hotkeyPreference, default: mode.defaultHotkey)
            let item = ClosureItem(mode.title) { [weak self] in self?.grab(mode) }
            key.decorate(item)
            submenu.addItem(item)
            GlobalHotkeys.shared.register("capture.\(mode.rawValue)", key) { [weak self] in self?.grab(mode) }
        }
        submenu.addItem(.separator())
        let selection = ClosureItem("Include Selected Text") { [weak self] in self?.toggleSelection() }
        selection.state = SelectedText.isOn ? .on : .off
        submenu.addItem(selection)
        selectionItem = selection

        let root = NSMenuItem(title: "Look at This", action: nil, keyEquivalent: "")
        root.submenu = submenu
        app.addMenuItem(root)
    }

    private func toggleSelection() {
        SelectedText.setOn(!SelectedText.isOn)
        selectionItem?.state = SelectedText.isOn ? .on : .off
    }

    /// `target` nil means the active agent, or ask.
    func grab(_ mode: GrabMode, for target: AgentWindow? = nil) {
        guard let app, !grabbing, !app.windows.isEmpty else { return }
        // Read the selection first: the region picker and our own alerts would disturb it.
        let selection = SelectedText.current()
        guard ScreenAccess.ensure(), let output = try? store.newURL(kind: mode.rawValue, ext: "png") else { return }

        let arguments: [String]
        switch mode {
        case .region:
            arguments = GrabPlan.arguments(region: output.path)
        case .window:
            guard let id = ScreenGrab.frontWindowID() else { return NSSound.beep() }
            arguments = GrabPlan.arguments(window: id, path: output.path)
        case .screen:
            guard let screen = ScreenGrab.screenUnderMouse(), let main = NSScreen.screens.first else { return }
            arguments = GrabPlan.arguments(rect: GrabPlan.captureRect(screenFrame: screen.frame, mainHeight: main.frame.height),
                                           path: output.path)
        }

        // Nook stays out of the picture. A single window grab cannot include us, so nothing blinks for it.
        grabbing = true
        let hidden = mode == .window ? [] : NSApp.windows.filter { $0 is NSPanel && $0.isVisible && $0.alphaValue > 0 }
        let alphas = hidden.map(\.alphaValue)
        hidden.forEach { $0.alphaValue = 0 }
        // One beat for the window server to drop us from the screen before the shutter.
        DispatchQueue.main.asyncAfter(deadline: .now() + (hidden.isEmpty ? 0 : 0.12)) {
            ScreenGrab.run(arguments, output: output) { [weak self] file in
                zip(hidden, alphas).forEach { $0.alphaValue = $1 }
                self?.grabbing = false
                guard let self, let app = self.app, let file else { return }
                let payload = IntakePayload(files: [file], text: selection.map { [$0] } ?? [])
                if let target, app.windows.contains(where: { $0 === target }) {
                    Intake.deliver(payload, to: target, in: app, store: self.store)
                } else {
                    Intake.chooseAgent(in: app, title: "Show it to…") { Intake.deliver(payload, to: $0, in: app, store: self.store) }
                }
            }
        }
    }
}
