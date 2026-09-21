import Foundation

/// Finds the folders the user has worked in with Claude Code. Strictly read-only, and it reads
/// names and dates only: directory names under `~/.claude/projects/` and the names of the session
/// files inside them. No transcript is ever opened.
enum ProjectScan {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    /// Scratch folders that tools ran Claude in are not projects anyone wants to reopen.
    private static let temporary = ["/tmp/", "/private/", "/var/"]

    /// Most recently used first. Slow enough (one directory listing per project) to keep off the main thread.
    static func suggestions(limit: Int = 40, fileManager: FileManager = .default) -> [FolderChoice] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        func listing(_ url: URL) -> [(url: URL, modified: Date)] {
            let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
            return items.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast) }
        }
        func isDirectory(_ path: String) -> Bool {
            var directory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }

        // A project directory's own date moves when a session starts; that is close enough to pick
        // the candidates, and the newest session file then gives the real order.
        let projects = listing(root).filter { $0.url.hasDirectoryPath }.sorted { $0.modified > $1.modified }.prefix(limit)
        let found = projects.compactMap { project -> (choice: FolderChoice, used: Date)? in
            guard let path = ProjectPaths.decode(project.url.lastPathComponent, isDirectory: isDirectory),
                  !temporary.contains(where: path.hasPrefix) else { return nil }
            let newest = listing(project.url).filter { $0.url.pathExtension == "jsonl" }.max { $0.modified < $1.modified }
            let choice = FolderChoice(path: NewAgentRules.canonical(path), source: .suggested,
                                      sessionID: newest?.url.deletingPathExtension().lastPathComponent)
            return (choice, newest?.modified ?? project.modified)
        }
        return found.sorted { $0.used > $1.used }.map(\.choice)
    }
}
