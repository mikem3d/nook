import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then type a shortcut. Esc cancels, Delete switches the shortcut off.
/// All global hotkeys are paused while it listens, so an existing combo can be typed again.
final class ShortcutRecorderButton: NSButton {
    var combo: KeyCombo? { didSet { updateTitle() } }
    var onChange: ((KeyCombo?) -> Void)?

    private var recording = false { didSet { updateTitle() } }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(begin)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    private func updateTitle() {
        title = recording ? "Type shortcut…" : (combo?.description ?? "Off")
    }

    @objc private func begin() {
        guard !recording else { return end() }
        recording = true
        HotkeyCenter.shared.isPaused = true
        window?.makeFirstResponder(self)
    }

    private func end() {
        guard recording else { return }
        recording = false
        HotkeyCenter.shared.isPaused = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func resignFirstResponder() -> Bool {
        end()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { end() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// ⌘-combos arrive here before keyDown; take them while recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        let typed = KeyCombo(event: event)
        if typed.modifiers == 0, Int(typed.keyCode) == kVK_Escape { return end() }
        if typed.modifiers == 0, [kVK_Delete, kVK_ForwardDelete].contains(Int(typed.keyCode)) {
            end()
            onChange?(nil)
            return
        }
        guard typed.isSafeGlobally else { return NSSound.beep() } // needs ⌃, ⌥ or ⌘
        end()
        onChange?(typed)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.combo = combo
        button.onChange = onChange
    }
}
