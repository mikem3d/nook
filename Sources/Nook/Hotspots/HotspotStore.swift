import Foundation

/// A small JSON file in Application Support/Nook holding one value per agent folder. Read once,
/// written only when something changed.
final class HotspotStore<Value: Codable & Equatable> {
    private struct File: Codable {
        var version = 1
        var agents: [String: Value]
    }

    private let file: URL
    private let empty: () -> Value
    private var agents: [String: Value]

    init(name: String, folder: URL? = nil, empty: @escaping () -> Value) {
        let folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nook")
        file = folder.appendingPathComponent(name)
        self.empty = empty
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        agents = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(File.self, from: $0) }?.agents ?? [:]
    }

    var keys: [String] { Array(agents.keys) }

    subscript(key: String) -> Value { agents[key] ?? empty() }

    /// Changes one agent's value and saves if that changed anything. Returns true if it did.
    @discardableResult
    func update(_ key: String, _ change: (inout Value) -> Void) -> Bool {
        var value = self[key]
        change(&value)
        guard value != self[key] else { return false }
        agents[key] = value == empty() ? nil : value
        save()
        return true
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(File(agents: agents)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
