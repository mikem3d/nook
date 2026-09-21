import Foundation

/// A folder the new-agent panel can offer.
struct FolderChoice: Equatable {
    enum Source: Equatable { case recent, suggested }

    let path: String
    let source: Source
    /// A Claude Code session that can be resumed in this folder, if one is known.
    var sessionID: String?

    var name: String { (path as NSString).lastPathComponent }
    var shortPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

/// Claude Code keeps one directory per project under `~/.claude/projects/`, named after the
/// project's absolute path with every character that is not a letter or digit turned into a dash.
/// That loses information ("/a/b-c" and "/a/b/c" look the same), so decoding walks the name one
/// dash at a time and lets the disk decide: a dash is a slash only where the path so far exists.
enum ProjectPaths {
    /// What a dash may have been, besides a slash. Slash is tried first, so when both "/a/b/c"
    /// and "/a/b-c" exist the deeper folder wins.
    private static let joiners = ["-", ".", "_", " "]
    /// Existence checks allowed for one name. A name with many dashes and no match on disk would
    /// otherwise try every combination.
    private static let budget = 2000

    static func encode(_ path: String) -> String {
        String(path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    /// The existing directory `name` stands for, or nil. `isDirectory` is the only contact with the disk.
    static func decode(_ name: String, isDirectory: (String) -> Bool) -> String? {
        guard name.hasPrefix("-") else { return nil }
        let tokens = name.dropFirst().split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var checks = 0

        func walk(_ base: String, _ segment: String, _ next: Int) -> String? {
            if next == tokens.count {
                guard !segment.isEmpty, checks < budget else { return nil }
                checks += 1
                let path = base + "/" + segment
                return isDirectory(path) ? path : nil
            }
            if !segment.isEmpty, checks < budget {
                checks += 1
                let path = base + "/" + segment
                if isDirectory(path), let found = walk(path, tokens[next], next + 1) { return found }
            }
            for joiner in joiners {
                guard checks < budget else { return nil }
                if let found = walk(base, segment + joiner + tokens[next], next + 1) { return found }
            }
            return nil
        }
        return tokens.isEmpty ? nil : walk("", tokens[0], 1)
    }
}

/// Folders agents were started in, most recent first. Persisted as JSON under `nook.recentFolders`.
struct RecentFolders: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let path: String
        var sessionID: String?
    }

    static let limit = 30
    private(set) var entries: [Entry] = []

    /// Moves the folder to the front. A nil `sessionID` keeps the one already known.
    mutating func touch(_ path: String, sessionID: String? = nil) {
        let path = NewAgentRules.canonical(path)
        let known = entries.first { $0.path == path }?.sessionID
        entries.removeAll { $0.path == path }
        entries.insert(Entry(path: path, sessionID: sessionID ?? known), at: 0)
        entries = Array(entries.prefix(Self.limit))
    }

    /// Records a session without changing the order. True if anything changed (and so needs saving).
    mutating func note(sessionID: String, for path: String) -> Bool {
        let path = NewAgentRules.canonical(path)
        guard let index = entries.firstIndex(where: { $0.path == path }), entries[index].sessionID != sessionID else { return false }
        entries[index].sessionID = sessionID
        return true
    }

    mutating func remove(_ path: String) {
        let path = NewAgentRules.canonical(path)
        entries.removeAll { $0.path == path }
    }
}

enum FolderSearch {
    /// 0 means no match. A name that starts with the query beats a word inside the name, which
    /// beats the letters in order, which beats a hit somewhere in the path.
    static func score(_ query: String, name: String, path: String) -> Int {
        let q = query.lowercased()
        let name = name.lowercased()
        if name.hasPrefix(q) { return 5 }
        if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 4 }
        if name.contains(q) { return 3 }
        var rest = Substring(q)
        for c in name where c == rest.first { rest = rest.dropFirst() }
        if rest.isEmpty { return 2 }
        return path.lowercased().contains(q) ? 1 : 0
    }

    /// The matches, best first. Equal scores keep their order, which is recents before suggestions
    /// and newest first. An empty query keeps everything.
    static func rank(_ query: String, in choices: [FolderChoice]) -> [FolderChoice] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return choices }
        return choices.enumerated()
            .map { (score: score(query, name: $0.element.name, path: $0.element.path), index: $0.offset, choice: $0.element) }
            .filter { $0.score > 0 }
            .sorted { ($1.score, $0.index) < ($0.score, $1.index) }
            .map(\.choice)
    }
}

enum NewAgentRules {
    /// Past this many open agents, starting one more gets a gentle word about usage. Never a block.
    static let manyAgents = 8

    /// One spelling per folder: no trailing slash, no "..", symlinks resolved.
    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The first open agent already working in `folder`. `open` holds each agent's folder, nil for demo agents.
    static func existing(_ folder: String, among open: [String?]) -> Int? {
        let wanted = canonical(folder)
        return open.firstIndex { $0.map(canonical) == wanted }
    }

    /// `count` is how many agents are open once the new one has started.
    static func usageNote(count: Int) -> String? {
        count >= manyAgents ? "\(count) agents are open. Each one that works spends your Claude usage." : nil
    }

    /// Recents first, then suggestions that are not already recent.
    static func choices(recents: RecentFolders, suggested: [FolderChoice]) -> [FolderChoice] {
        let recent = recents.entries.map { entry in
            FolderChoice(path: entry.path, source: .recent,
                         sessionID: entry.sessionID ?? suggested.first { $0.path == entry.path }?.sessionID)
        }
        let known = Set(recent.map(\.path))
        return recent + suggested.filter { !known.contains($0.path) }
    }
}
