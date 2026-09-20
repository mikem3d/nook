import AppKit

/// Reopens agents, their layout and their Claude sessions on launch.
///
/// Restoring costs nothing: `addAgent` only spawns the `claude` process with the saved session
/// id, and a process that has been sent no message makes no API calls.
final class Persistence: Feature {
    struct SavedAgent: Codable, Equatable {
        let folder: String
        let label: String
        let sessionID: String?
        let corner: Int
        let order: Int
        let minimised: Bool
        let display: UInt32?
    }

    struct SavedState: Codable, Equatable {
        var version = 1
        var agents: [SavedAgent]
        var axes: [AppController.StackAxis]
    }

    /// At most one write in this many seconds, however chatty the sessions are.
    private static let interval: TimeInterval = 2

    private weak var app: AppController?
    private let file: URL
    private var pending = false
    private var lastWrite = Date.distantPast
    private var lastSaved: SavedState?
    /// A run that skipped restoring (explicit folders, --no-restore) must not wipe the saved
    /// agents just because it has none of its own.
    private var mayWriteEmpty = false

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nook/state.json")
    }

    func install(in app: AppController) {
        self.app = app
        let args = CommandLine.arguments.dropFirst()
        let explicit = args.contains { !$0.hasPrefix("--") }
        if !args.contains("--no-restore"), !explicit {
            mayWriteEmpty = true
            restore(into: app)
        }

        let centre = NotificationCenter.default
        for name in [Notification.Name.nookAgentsChanged, .nookSessionChanged] {
            centre.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
        centre.addObserver(self, selector: #selector(saveNow), name: NSApplication.willTerminateNotification, object: nil)
    }

    // MARK: restore

    static func load(_ file: URL) -> SavedState? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    /// Saved agents whose folder still exists, in their saved order.
    static func restorable(_ state: SavedState, fileManager: FileManager = .default) -> [SavedAgent] {
        state.agents.sorted { $0.order < $1.order }.filter {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.folder, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private func restore(into app: AppController) {
        guard let state = Self.load(file) else { return }
        lastSaved = state
        app.stackAxes = state.axes
        for agent in Self.restorable(state) {
            let window = app.addAgent(folder: URL(fileURLWithPath: agent.folder), label: agent.label, resume: agent.sessionID,
                                      corner: Corner(rawValue: agent.corner) ?? .bottomRight, minimised: agent.minimised)
            if let display = agent.display { app.move(window, toDisplay: display) }
        }
    }

    // MARK: save

    static func snapshot(of app: AppController) -> SavedState {
        // Demo agents have no folder and are never saved.
        let real = app.windows.filter { $0.session.cwd != nil }
        let agents = real.enumerated().map { order, window in
            SavedAgent(folder: window.session.cwd?.path ?? "", label: window.session.label, sessionID: window.session.sessionID,
                       corner: window.corner.rawValue, order: order, minimised: window.minimised, display: app.display(of: window))
        }
        return SavedState(agents: agents, axes: app.stackAxes)
    }

    /// Session changes arrive in bursts while an agent streams; one timer collects them.
    @objc private func changed() {
        guard !pending else { return }
        pending = true
        let wait = max(0, Self.interval - Date().timeIntervalSince(lastWrite))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.saveNow() }
    }

    @objc private func saveNow() {
        pending = false
        lastWrite = Date() // counts even when nothing is written, so a busy stream is checked every 2 s, not every event
        guard let app else { return }
        let state = Self.snapshot(of: app)
        guard mayWriteEmpty || !state.agents.isEmpty else { return }
        guard state != lastSaved else { return } // most session changes do not touch what is saved
        lastSaved = state
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
