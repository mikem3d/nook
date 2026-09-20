import AppKit
import ServiceManagement
import SwiftUI

/// Preference keys the settings window writes. Read them with `UserDefaults.standard`.
enum SettingsKeys {
    /// Passed to `claude --model` for new agents; empty means Claude Code's own default.
    static let model = "nook.model"
    /// `Corner.rawValue` for new agents.
    static let defaultCorner = "nook.defaultCorner"
    /// "auto", "1", "1.5" or "2".
    static let scale = "nook.scale"
    static let voiceEnabled = "nook.voice.enabled"
    /// A locale identifier such as "en-GB"; empty follows the system.
    static let voiceLocale = "nook.voice.locale"
}

private let paneWidth: CGFloat = 520

// MARK: General

struct GeneralSettings: View {
    @AppStorage(SettingsKeys.model) private var model = ""
    @AppStorage(SettingsKeys.defaultCorner) private var corner = Corner.bottomRight.rawValue
    @AppStorage(SettingsKeys.scale) private var scale = "auto"
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError = ""

    private static let models = ["opus", "sonnet", "haiku"]

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Default model", text: $model, prompt: Text("Claude Code default"))
                    Menu("Suggestions") {
                        Button("Claude Code default") { model = "" }
                        ForEach(Self.models, id: \.self) { name in Button(name) { model = name } }
                    }
                    .fixedSize()
                }
                Picker("New agents appear", selection: $corner) {
                    Text("Bottom right").tag(Corner.bottomRight.rawValue)
                    Text("Bottom left").tag(Corner.bottomLeft.rawValue)
                    Text("Top right").tag(Corner.topRight.rawValue)
                    Text("Top left").tag(Corner.topLeft.rawValue)
                }
                Picker("Window size", selection: $scale) {
                    Text("Automatic").tag("auto")
                    Text("1×").tag("1")
                    Text("1.5×").tag("1.5")
                    Text("2×").tag("2")
                }
            } footer: {
                Text("Model and corner apply to agents you start from now on.").settingsNote()
            }
            Section {
                Toggle("Launch Nook at login", isOn: $launchAtLogin)
                    .disabled(!LoginItem.isAvailable)
                    .onChange(of: launchAtLogin) { _, wanted in
                        guard wanted != LoginItem.isEnabled else { return }
                        do {
                            try LoginItem.set(wanted)
                            loginError = ""
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
            } footer: {
                if !LoginItem.isAvailable {
                    Text("Available when Nook runs as an app bundle (Nook.app), not from the command line.").settingsNote()
                } else if !loginError.isEmpty {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 330)
    }
}

/// Launch at login through SMAppService. That only works for a real .app bundle, so everything
/// here is a harmless no-op when Nook runs as a bare SwiftPM executable.
enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    static var isEnabled: Bool { isAvailable && SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        guard isAvailable else { return }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

// MARK: Hotkeys

final class HotkeyListModel: ObservableObject {
    @Published var hotkeys = HotkeyCenter.shared.all
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: HotkeyCenter.changed, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeys = HotkeyCenter.shared.all
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

struct HotkeySettings: View {
    @StateObject private var model = HotkeyListModel()
    @AppStorage(Hotkeys.guardKey) private var approvalGuard = true

    var body: some View {
        Form {
            Section {
                ForEach(model.hotkeys) { hotkey in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(hotkey.title)
                            Spacer()
                            ShortcutRecorder(combo: hotkey.combo) { HotkeyCenter.shared.setCombo($0, for: hotkey.id) }
                                .frame(width: 130)
                            Button("Reset") { HotkeyCenter.shared.resetToDefault(id: hotkey.id) }
                                .disabled(hotkey.combo == hotkey.defaultCombo)
                        }
                        if let problem = hotkey.problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } footer: {
                Text("Click a shortcut, then type the new one. Esc cancels, Delete switches it off. Shortcuts work in every app and need no extra permission.").settingsNote()
            }
            Section {
                Toggle("Pause briefly between hotkey approvals", isOn: $approvalGuard)
            } footer: {
                Text("Each answer shows what was allowed or denied. With this on, the next answer is ignored until that confirmation has been visible for 0.3 seconds, so a held key cannot approve a queue unseen.").settingsNote()
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 480)
    }
}

// MARK: Quiet mode

struct QuietSettings: View {
    @AppStorage(QuietMode.autoKey) private var auto = true
    @State private var apps = UserDefaults.standard.stringArray(forKey: QuietMode.appsKey) ?? QuietMode.defaultApps
    @State private var entry = ""

    var body: some View {
        Form {
            Section {
                Toggle("Turn on automatically", isOn: $auto)
            } footer: {
                Text("Quiet mode hides speech bubbles and notices; state dots, badges and approval confirmations stay. It turns on while a display is mirrored or one of the apps below is in front. If you switch quiet mode by hand, Nook leaves it alone until it is relaunched. macOS Focus is not used: reading it needs an extra permission.").settingsNote()
            }
            Section("Meeting apps") {
                ForEach(apps, id: \.self) { app in
                    HStack {
                        Text(app)
                        Spacer()
                        Button { save(apps.filter { $0 != app }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(app)")
                    }
                }
                HStack {
                    TextField("Add", text: $entry, prompt: Text("App name or bundle id"))
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add).disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
                    Menu("Running") {
                        ForEach(Self.runningApps, id: \.id) { app in
                            Button(app.name) { entry = app.id; add() }
                        }
                    }
                    .fixedSize()
                }
                Button("Restore Defaults") { save(QuietMode.defaultApps) }
            }
            .disabled(!auto)
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 520)
    }

    private func add() {
        let value = entry.trimmingCharacters(in: .whitespaces)
        entry = ""
        guard !value.isEmpty, !apps.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        save(apps + [value])
    }

    private func save(_ list: [String]) {
        apps = list
        UserDefaults.standard.set(list, forKey: QuietMode.appsKey)
    }

    private static var runningApps: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: Voice

struct VoiceSettings: View {
    @AppStorage(SettingsKeys.voiceEnabled) private var enabled = false
    @AppStorage(SettingsKeys.voiceLocale) private var locale = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable voice", isOn: $enabled)
                TextField("Language", text: $locale, prompt: Text("System language (\(Locale.current.identifier(.bcp47)))"))
                    .disabled(!enabled)
            } footer: {
                Text("Hold-to-talk uses the shortcut listed under Hotkeys once the voice feature registers one. Language is a locale identifier such as en-GB.").settingsNote()
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 200)
    }
}

// MARK: About

struct AboutSettings: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "Version \($0)" } ?? "Development build"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.person.crop")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Nook").font(.title2.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Pixel desktop windows, one per live Claude Code agent.\nNook runs your own, unmodified Claude Code and makes no network calls itself.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .padding(.top, 6)
        }
        .padding(24)
        .frame(width: paneWidth, height: 230)
    }
}

private extension Text {
    func settingsNote() -> some View {
        font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}
