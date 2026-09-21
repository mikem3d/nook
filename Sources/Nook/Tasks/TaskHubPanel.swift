import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The hub's window. Like the hotspot panels it is non-activating but key-capable, and sits at
/// `NookLevel.prompt`, above the focus overlay. Unlike them it stays up when the user clicks
/// elsewhere, so a task can be written while looking at an agent; Esc, the hotkey or its close
/// button put it away, and it can be dragged by its background.
///
/// Keys: while a text field has the keyboard it keeps them, except ⌘Return (send the selected task),
/// up and down in a one-line field (move the selection) and Esc (leave the field). Otherwise arrows
/// move, Return edits, ⌘Return sends, Delete cancels and Esc closes.
final class TaskHubPanel: NSPanel {
    private weak var model: TaskHubModel?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NookLevel.prompt
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    func present(model: TaskHubModel) {
        self.model = model
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = CGSize(width: min(TextSize.metric(1040), area.width - 40), height: min(TextSize.metric(640), area.height - 40))
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 12
        glass.layer?.masksToBounds = true
        let host = NSHostingView(rootView: TaskHubView(model: model, close: { [weak self] in self?.close() }))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        glass.frame = host.frame
        glass.addSubview(host)
        contentView = glass
        setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
        makeKeyAndOrderFront(nil)
    }

    /// Nothing is kept alive while the hub is away.
    override func close() {
        super.close()
        contentView = nil
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handle(event) { return }
        super.sendEvent(event)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let text = firstResponder as? NSTextView
        if flags == .command, code == kVK_Return || code == kVK_ANSI_KeypadEnter { return model.handle(.send) }
        guard flags.isEmpty else { return false }
        if let text {
            switch code {
            case kVK_Escape:
                makeFirstResponder(nil)
                return true
            case kVK_UpArrow where text.isFieldEditor && model.editing == nil: return model.handle(.move(.up))
            case kVK_DownArrow where text.isFieldEditor && model.editing == nil: return model.handle(.move(.down))
            default: return false
            }
        }
        if code == kVK_Escape {
            if model.editing != nil { model.editing = nil } else { close() }
            return true
        }
        // The editor's pickers use the arrows and Return themselves.
        guard model.editing == nil else { return false }
        switch code {
        case kVK_UpArrow: return model.handle(.move(.up))
        case kVK_DownArrow: return model.handle(.move(.down))
        case kVK_LeftArrow: return model.handle(.move(.left))
        case kVK_RightArrow: return model.handle(.move(.right))
        case kVK_Return, kVK_ANSI_KeypadEnter: return model.handle(.edit)
        case kVK_Delete, kVK_ForwardDelete: return model.handle(.cancel)
        default: return false
        }
    }
}
