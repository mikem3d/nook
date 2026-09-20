import AppKit
import Carbon.HIToolbox

/// REPLACE ME: the control engineer's shared `HotkeyCenter` should take over from `CarbonHotkeys`.
/// Capture and Handoff only ever talk to this protocol, through `GlobalHotkeys.shared`.
protocol HotkeyRegistering: AnyObject {
    /// Registers (or re-registers) the global hotkey called `name`. Returns false if the system refused it.
    @discardableResult
    func register(_ name: String, _ key: HotkeySpec, handler: @escaping () -> Void) -> Bool
}

enum GlobalHotkeys {
    /// The one line to change when HotkeyCenter lands.
    static let shared: HotkeyRegistering = CarbonHotkeys()
}

/// A key plus modifiers, stored in preferences as text such as "ctrl+opt+r".
struct HotkeySpec: Equatable {
    let key: String // a single lowercase letter or digit
    let modifiers: NSEvent.ModifierFlags

    private static let names: [(String, NSEvent.ModifierFlags)] = [
        ("ctrl", .control), ("opt", .option), ("shift", .shift), ("cmd", .command),
    ]
    private static let aliases: [String: String] = [
        "control": "ctrl", "⌃": "ctrl", "option": "opt", "alt": "opt", "⌥": "opt",
        "⇧": "shift", "command": "cmd", "⌘": "cmd",
    ]
    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    /// "ctrl+opt+r", "Control-Option-R" and "⌃+⌥+R" all parse. A global hotkey needs at least one modifier.
    init?(_ text: String) {
        let parts = text.lowercased().split(whereSeparator: { "+- ".contains($0) }).map(String.init)
        guard let last = parts.last, Self.keyCodes[last] != nil else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            let name = Self.aliases[part] ?? part
            guard let flag = Self.names.first(where: { $0.0 == name })?.1 else { return nil }
            flags.insert(flag)
        }
        guard !flags.isEmpty else { return nil }
        key = last
        modifiers = flags
    }

    /// The user's setting if it parses, otherwise the default.
    static func preference(_ defaultsKey: String, default fallback: String, in defaults: UserDefaults = .standard) -> HotkeySpec {
        defaults.string(forKey: defaultsKey).flatMap(HotkeySpec.init) ?? HotkeySpec(fallback)!
    }

    var text: String {
        (Self.names.filter { modifiers.contains($0.1) }.map(\.0) + [key]).joined(separator: "+")
    }

    var keyCode: UInt32 { UInt32(Self.keyCodes[key]!) }

    var carbonModifiers: UInt32 {
        var m = 0
        if modifiers.contains(.control) { m |= controlKey }
        if modifiers.contains(.option) { m |= optionKey }
        if modifiers.contains(.shift) { m |= shiftKey }
        if modifiers.contains(.command) { m |= cmdKey }
        return UInt32(m)
    }

    /// Shows the hotkey beside a menu item. The menu never fires it: the global registration does.
    func decorate(_ item: NSMenuItem) {
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifiers
    }
}

/// Minimal Carbon registration. Needs no permission and costs nothing while idle.
private final class CarbonHotkeys: HotkeyRegistering {
    private static let signature: OSType = 0x4E4F_4F4B // "NOOK"
    private static var handlers: [UInt32: () -> Void] = [:]

    private var refs: [String: (id: UInt32, ref: EventHotKeyRef)] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    func register(_ name: String, _ key: HotkeySpec, handler: @escaping () -> Void) -> Bool {
        installHandlerOnce()
        if let old = refs.removeValue(forKey: name) {
            UnregisterEventHotKey(old.ref)
            Self.handlers[old.id] = nil
        }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(key.keyCode, key.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[name] = (id, ref)
        Self.handlers[id] = handler
        return true
    }

    private func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if status == noErr, id.signature == CarbonHotkeys.signature {
                CarbonHotkeys.handlers[id.id]?()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
