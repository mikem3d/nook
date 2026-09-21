import Foundation

/// Which of the CLI's tools can read and write a calendar, found by name in the `system/init`
/// event. No vendor is hard-coded: any MCP tool whose name speaks of a calendar, or of events on a
/// server that does, qualifies, and only verbs that cannot change anything count as reading.
struct CalendarTools: Codable, Equatable {
    static let key = "nook.calendar.tools"

    /// Read-only tools the sync job may call. Usable only if one of them lists or searches events.
    var read: [String] = []
    /// The one tool a write-back job may call.
    var create: String?
    /// Everything else the CLI offered; denied by name, which also keeps it out of the job's context.
    var others: [String] = []

    var canRead: Bool { read.contains { Self.listsEvents(Self.parts($0).tool) } }

    private static let readVerbs = ["list", "search", "get", "find", "read", "query", "fetch"]
    private static let createVerbs = ["create", "add", "insert", "new"]

    static func discover(in tools: [String]) -> CalendarTools {
        var found = CalendarTools()
        for name in tools {
            let (server, tool) = parts(name)
            let onCalendar = server.contains("calendar") || tool.contains("calendar")
            if onCalendar, readVerbs.contains(where: tool.hasPrefix), tool.contains("event") || tool.contains("calendar") {
                found.read.append(name)
            } else {
                if onCalendar, found.create == nil, createVerbs.contains(where: tool.hasPrefix), tool.contains("event") {
                    found.create = name
                }
                found.others.append(name)
            }
        }
        return found
    }

    private static func listsEvents(_ tool: String) -> Bool {
        tool.contains("event") && ["list", "search", "find", "query"].contains(where: tool.hasPrefix)
    }

    /// "mcp__Some_Server__list_events" is server "some_server", tool "list_events". A built-in tool has no server.
    private static func parts(_ name: String) -> (server: String, tool: String) {
        let lower = name.lowercased()
        guard lower.hasPrefix("mcp__"), let split = lower.range(of: "__", options: .backwards), split.lowerBound > lower.index(lower.startIndex, offsetBy: 4) else {
            return ("", lower)
        }
        return (String(lower[lower.index(lower.startIndex, offsetBy: 5)..<split.lowerBound]), String(lower[split.upperBound...]))
    }

    // MARK: remembered between runs

    static var stored: CalendarTools? {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(CalendarTools.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key) }
    }
}
