// HotkeyCenter: global hotkeys for every feature, with press AND release callbacks.
//
// Built on Carbon `RegisterEventHotKey`, so it needs no Accessibility or Input Monitoring
// permission. Nothing runs while idle: Carbon calls back on the main thread.
//
// Adopting it from a feature:
//
//     HotkeyCenter.shared.register(id: "voice.talk", title: "Hold to talk",
//                                  defaultCombo: KeyCombo(kVK_ANSI_V, [.control, .option]),
//                                  onPress: { startListening() },
//                                  onRelease: { stopListening() })
//
// - `id` is stable: the user's choice persists in UserDefaults under `nook.hotkey.<id>`
//   (an empty string means the user switched the shortcut off).
// - Every registered id appears in Settings > Hotkeys with a recorder; you add no UI.
// - `onRelease` fires when the key goes up, which is all hold-to-talk needs. `onPress` fires
//   once per physical press (Carbon hotkeys do not auto-repeat).
// - If the combo cannot be registered (another shortcut in Nook has it, or the system refuses),
//   `info(for:)?.problem` says why and settings shows it. Observe `HotkeyCenter.changed` to refresh.

import AppKit
import Carbon.HIToolbox

final class HotkeyCenter {
    static let shared = HotkeyCenter()
    /// Posted whenever a combo, registration or problem changes. Object: HotkeyCenter.
    static let changed = Notification.Name("nookHotkeysChanged")
    static let keyPrefix = "nook.hotkey."

    /// What settings shows for one shortcut.
    struct Info: Identifiable {
        let id: String
        let title: String
        let combo: KeyCombo?
        let defaultCombo: KeyCombo
        /// Why the shortcut is not live, or nil when it is (or is deliberately off).
        let problem: String?
    }

    private struct Entry {
        let id: String
        let title: String
        let defaultCombo: KeyCombo
        var combo: KeyCombo?
        let onPress: () -> Void
        let onRelease: (() -> Void)?
        let number: UInt32
        var ref: EventHotKeyRef?
        var problem: String?
    }

    private static let signature: OSType = 0x4E4F_4F4B // 'NOOK'
    private var entries: [Entry] = []
    private var handler: EventHandlerRef?

    /// The settings recorder pauses every shortcut while it listens, so the keys reach it.
    var isPaused = false {
        didSet { if isPaused != oldValue { reload() } }
    }

    var all: [Info] {
        entries.map { Info(id: $0.id, title: $0.title, combo: $0.combo, defaultCombo: $0.defaultCombo, problem: $0.problem) }
    }

    func info(for id: String) -> Info? { all.first { $0.id == id } }

    /// Registering an id again replaces its callbacks (the stored combo is kept).
    func register(id: String, title: String? = nil, defaultCombo: KeyCombo,
                  onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) {
        installHandlerIfNeeded()
        let entry = Entry(id: id, title: title ?? id, defaultCombo: defaultCombo,
                          combo: Self.stored(id: id, fallback: defaultCombo),
                          onPress: onPress, onRelease: onRelease,
                          number: (entries.map(\.number).max() ?? 0) + 1)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            release(&entries[index])
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        reload()
    }

    func unregister(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        release(&entries[index])
        entries.remove(at: index)
        reload()
    }

    /// nil switches the shortcut off. Persists, then re-registers everything.
    func setCombo(_ combo: KeyCombo?, for id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].combo = combo
        UserDefaults.standard.set(combo?.encoded ?? "", forKey: Self.keyPrefix + id)
        reload()
    }

    func resetToDefault(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].combo = entries[index].defaultCombo
        UserDefaults.standard.removeObject(forKey: Self.keyPrefix + id)
        reload()
    }

    /// The stored choice for an id: absent means the default, "" means off.
    static func stored(id: String, fallback: KeyCombo, defaults: UserDefaults = .standard) -> KeyCombo? {
        guard let raw = defaults.string(forKey: keyPrefix + id) else { return fallback }
        if raw.isEmpty { return nil }
        return KeyCombo(encoded: raw) ?? fallback
    }

    // MARK: Carbon

    /// Registration order decides who wins a clash, so a change re-registers the whole (tiny) table.
    private func reload() {
        for index in entries.indices { release(&entries[index]) }
        var taken: [KeyCombo: String] = [:]
        for index in entries.indices {
            entries[index].problem = nil
            guard let combo = entries[index].combo else { continue }
            if let owner = taken[combo] {
                entries[index].problem = "Already used by “\(owner)”"
                continue
            }
            taken[combo] = entries[index].title
            guard !isPaused else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: entries[index].number),
                                             GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                entries[index].ref = ref
            } else if status == OSStatus(eventHotKeyExistsErr) {
                entries[index].problem = "In use by another app or the system"
            } else {
                entries[index].problem = "Could not be registered (error \(status))"
            }
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    private func release(_ entry: inout Entry) {
        if let ref = entry.ref { UnregisterEventHotKey(ref) }
        entry.ref = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            HotkeyCenter.shared.fire(key.id, pressed: GetEventKind(event) == UInt32(kEventHotKeyPressed))
            return noErr
        }, specs.count, &specs, nil, &handler)
    }

    private func fire(_ number: UInt32, pressed: Bool) {
        guard let entry = entries.first(where: { $0.number == number }) else { return }
        if pressed { entry.onPress() } else { entry.onRelease?() }
    }
}
