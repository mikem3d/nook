import AppKit
import Carbon.HIToolbox

/// A global key that reports both press and release.
///
/// INTEGRATION: the control engineer's shared `HotkeyCenter` offers the same thing. Make it (or a
/// small adapter) conform to this protocol, hand it to `Voice`, and delete `CarbonPushToTalkKey`.
protocol PushToTalkKey: AnyObject {
    var onPress: (() -> Void)? { get set }
    var onRelease: (() -> Void)? { get set }
    /// False when the combination is malformed or already taken by another app.
    @discardableResult func register(_ combo: KeyCombo) -> Bool
    func unregister()
}

/// "control+option+v": modifier names and one key, joined by "+". Stored as a plain string so it
/// can be changed with `defaults write` until a settings pane exists.
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    /// For showing to the user: "⌃⌥V".
    let display: String

    init?(_ string: String) {
        var modifiers: UInt32 = 0
        var symbols = ""
        var key: (code: Int, name: String)?
        for part in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "control", "ctrl": modifiers |= UInt32(controlKey)
            case "option", "opt", "alt": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "command", "cmd": modifiers |= UInt32(cmdKey)
            default:
                guard key == nil, let code = Self.keyCodes[part] else { return nil }
                key = (code, part.uppercased())
            }
        }
        // A bare key would swallow ordinary typing system-wide.
        guard let key, modifiers != 0 else { return nil }
        for (flag, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        where modifiers & UInt32(flag) != 0 {
            symbols += symbol
        }
        keyCode = UInt32(key.code)
        carbonModifiers = modifiers
        display = symbols + (key.name == "SPACE" ? "Space" : key.name)
    }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "`": kVK_ANSI_Grave,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}

/// TEMPORARY (see `PushToTalkKey`). Carbon hot keys need no Accessibility or Input Monitoring
/// permission, and they are the only public API that delivers the release as well as the press.
final class CarbonPushToTalkKey: PushToTalkKey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4E4B5654 // "NKVT"

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetEventDispatcherTarget(), 0, &hotKey)
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        let types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Other hot keys in the process share the dispatcher; only ours is ours.
            guard id.signature == CarbonPushToTalkKey.signature else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<CarbonPushToTalkKey>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { me.onPress?() } else { me.onRelease?() }
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), callback, types.count, types,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
