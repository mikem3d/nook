import Foundation

/// What one agent passes to another. Plain values in, text out, so it can be checked headless.
struct HandoffMessage {
    static let defaultInstruction = "Read this for context and use whatever is relevant to your own work. Reply briefly with what you will do with it."
    static let replyLimit = 8000

    var sourceLabel: String
    var sourceFolder: String?
    var summary: String
    var lastReply: String?
    var instruction: String

    /// The prefix tells the receiver this did not come from the user's keyboard, and from whom.
    var text: String {
        var lines = ["[Handoff from another agent: \"\(sourceLabel)\"]"]
        lines.append("Its folder: \(sourceFolder ?? "none (demo agent)")")
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { lines.append("How its last turn ended: \(summary)") }
        let reply = lastReply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reply.isEmpty {
            lines.append("It has not replied with anything yet.")
        } else {
            lines.append("Its last reply:\n<<<\n\(Self.clip(reply))\n>>>")
        }
        let wish = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("What the user wants from you: \(wish.isEmpty ? Self.defaultInstruction : wish)")
        return lines.joined(separator: "\n")
    }

    /// Long replies keep their ending, where results usually are.
    static func clip(_ reply: String, limit: Int = replyLimit) -> String {
        guard reply.count > limit else { return reply }
        return "[…earlier part trimmed…]\n" + String(reply.suffix(limit))
    }
}
