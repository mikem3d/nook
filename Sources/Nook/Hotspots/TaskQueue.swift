import Foundation

/// The shape of tasks.json version 1: one queue per agent. Kept only so an old file can be read and
/// carried forward by `TaskStore.migrate`; nothing writes it any more.
struct TaskQueue: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String
    }

    struct Done: Codable, Equatable, Identifiable {
        var id = UUID()
        var text: String
        var finished: Date
        var summary: String
        var failed: Bool
        var automatic: Bool
    }

    var queued: [Item] = []
    var sending: Item?
    var sentAutomatically = false
    /// Newest first.
    var done: [Done] = []
    var unseen = false
}
