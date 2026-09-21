import Foundation

/// Spots permission requests that should be read in full before anyone says yes. Such a request
/// gets no Allow button in its notification. Deliberately crude: a false alarm only costs a click
/// to open the agent, and classifying by the input's shape works whatever the tool is called.
/// Not covered: shell redirections to files outside the project.
enum Risk {
    private static let commands: Set<String> = ["rm", "sudo", "doas", "dd", "shred", "diskutil"]
    private static let separators = CharacterSet(charactersIn: " \t\n;|&()`$<>{}=")
    private static let quotes = CharacterSet(charactersIn: "\"'")
    private static let pathKeys = ["file_path", "notebook_path", "path"]

    /// A few words on what looks dangerous, or nil when nothing stands out.
    static func reason(input: [String: Any], projectFolder: String?) -> String? {
        if let command = input["command"] as? String { return shellReason(command) }
        for key in pathKeys {
            guard let path = input[key] as? String else { continue }
            return isOutside(path, of: projectFolder) ? "a path outside the project folder" : nil
        }
        return nil
    }

    static func shellReason(_ command: String) -> String? {
        let words = command.components(separatedBy: separators).compactMap { piece -> String? in
            let bare = piece.trimmingCharacters(in: quotes)
            return bare.isEmpty ? nil : (bare as NSString).lastPathComponent // /bin/rm is rm
        }
        if let hit = words.first(where: { commands.contains($0) || $0.hasPrefix("mkfs") }) { return hit }
        if words.contains("find"), words.contains("-delete") { return "find -delete" }
        if words.contains("git") {
            let forced = words.contains { $0 == "-f" || $0.hasPrefix("--force") || ($0.hasPrefix("+") && $0.count > 1) }
            if words.contains("push"), forced { return "git push --force" }
            if words.contains("reset"), words.contains("--hard") { return "git reset --hard" }
            if words.contains("clean") { return "git clean" }
        }
        if command.range(of: #"\|\s*(sudo\s+)?(ba|z|da|k)?sh\b"#, options: .regularExpression) != nil {
            return "a download or output piped into a shell"
        }
        return nil
    }

    /// Relative paths are the agent's, so they resolve against its folder. No folder means no way to tell.
    static func isOutside(_ path: String, of folder: String?) -> Bool {
        guard let folder, !folder.isEmpty else { return true }
        let root = (folder as NSString).standardizingPath
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : root + "/" + expanded
        let resolved = (absolute as NSString).standardizingPath
        return !(resolved == root || resolved.hasPrefix(root + "/"))
    }
}
