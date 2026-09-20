import AppKit
import Carbon.HIToolbox

/// A global shortcut: a virtual key code plus Carbon modifier bits (`cmdKey`, `optionKey`, ...).
/// Carbon values are used throughout because that is what `RegisterEventHotKey` takes.
struct KeyCombo: Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    /// Convenience for defaults: `KeyCombo(kVK_ANSI_A, [.control, .option])`.
    init(_ key: Int, _ flags: NSEvent.ModifierFlags) {
        self.init(keyCode: UInt32(key), modifiers: Self.carbon(flags))
    }

    /// From a key-down event, as the settings recorder sees it.
    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbon(event.modifierFlags))
    }

    // MARK: persistence ("<modifiers>:<keyCode>")

    var encoded: String { "\(modifiers):\(keyCode)" }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let m = UInt32(parts[0]), let k = UInt32(parts[1]), k < 0x80 else { return nil }
        guard m & ~Self.modifierMask == 0 else { return nil }
        self.init(keyCode: k, modifiers: m)
    }

    // MARK: description

    /// Human-readable, in the standard macOS modifier order: "⌃⌥A", "⌃⌥Space".
    var description: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.keyNames[Int(keyCode)] ?? "Key \(keyCode)")
    }

    /// A global shortcut made only of a plain key (or shift + key) would swallow ordinary typing.
    var isSafeGlobally: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 || Self.functionKeys.contains(Int(keyCode))
    }

    // MARK: tables

    static let modifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13,
    ]

    /// Names follow the ANSI (US) layout; key codes are positional, so on other layouts the letter
    /// shown may differ from the key cap while the shortcut itself still works.
    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Quote: "'", kVK_ANSI_Semicolon: ";", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
        kVK_ANSI_Slash: "/", kVK_ANSI_Period: ".", kVK_ANSI_Grave: "`",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
    ]
}
