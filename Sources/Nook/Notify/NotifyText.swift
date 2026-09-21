import Foundation

/// The words in a notification, as pure functions.
enum NotifyText {
    /// About what a macOS banner shows once expanded. A request longer than this cannot be shown
    /// whole, so it cannot be allowed from the notification either: you only approve what you can read.
    static let bodyLimit = 180

    /// Cuts the middle out, keeping the start (the command and its first arguments) and the end
    /// (the file name of a long path, the last command of a chain).
    static func middleTruncated(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 8 else { return text }
        let head = (limit - 3) * 2 / 3
        let tail = limit - 3 - head
        return "\(text.prefix(head)) … \(text.suffix(tail))"
    }

    /// The exact command or path being asked about. `complete` is false when part of it is not shown.
    /// `fallback` is the engine's own one-line summary, which is already cut at 80 characters.
    static func permissionBody(input: [String: Any], fallback: String) -> (text: String, complete: Bool) {
        let keys = ["command", "file_path", "notebook_path", "path", "url", "pattern", "query"]
        let exact = keys.lazy.compactMap { input[$0] as? String }.first
        let flat = (exact ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ") // a banner has room for a few lines only
        let shown = middleTruncated(flat, limit: bodyLimit)
        return (shown, shown == flat && (exact != nil || fallback.count < 80))
    }

    static func reviewLine(_ reason: String) -> String { "Needs a closer look (\(reason)). Open Nook to allow it." }

    /// The menu bar menu's first line; nil when nobody is waiting. Approvals come first.
    static func needsYou(pending: [String], finished: [String]) -> String? {
        switch (pending.count, finished.count) {
        case (0, 0): return nil
        case (1, 0): return "\(pending[0]) needs approval"
        case (0, 1): return "\(finished[0]) has finished"
        case (let waiting, 0): return "\(waiting) agents need approval"
        case (0, let done): return "\(done) agents have finished"
        case (let waiting, let done): return "\(waiting) need approval, \(done) finished"
        }
    }
}
