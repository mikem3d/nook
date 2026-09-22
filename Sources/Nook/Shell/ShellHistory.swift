import Foundation

/// The commands typed at each agent's folder, newest last, so Up-arrow brings them back after a
/// restart. Stored verbatim: no attempt is made to scrub secrets, exactly as a shell's own
/// history file keeps whatever was typed.
enum ShellHistory {
    static let key = "nook.shell.history"
    static let limit = 100

    static func commands(for folder: URL, defaults: UserDefaults = .standard) -> [String] {
        let all = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        return all[slot(folder)] ?? []
    }

    static func add(_ command: String, for folder: URL, defaults: UserDefaults = .standard) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        var list = all[slot(folder)] ?? []
        if list.last != trimmed { list.append(trimmed) } // a command repeated in a row is one entry
        all[slot(folder)] = Array(list.suffix(limit))
        defaults.set(all, forKey: key)
    }

    private static func slot(_ folder: URL) -> String { folder.standardizedFileURL.path }
}

/// What Up-arrow in an empty input brings back: the last thing the user sent in this conversation,
/// whether that was a message to the agent or a shell command, and failing that the newest
/// command remembered for the folder from an earlier run.
enum ShellRecall {
    static func last(transcript: [TranscriptEntry], history: [String]) -> String? {
        for entry in transcript.reversed() {
            switch entry.kind {
            case .user: return entry.text
            case let .shell(run): return "!" + run.command
            default: continue
            }
        }
        return history.last.map { "!" + $0 }
    }
}
