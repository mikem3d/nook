import Foundation

/// The quick-add line: plain words with a few marks anywhere among them.
///
///     fix the login bug @zipdemand !high due fri 3pm #auth
///
/// - `@name`   the agent, matched loosely against the open agents' labels
/// - `!low !medium !high !urgent`   priority (any prefix: `!h`, `!med`)
/// - `#tag`
/// - `due …`   today, tomorrow, a weekday (`fri`, `next fri`), `in 3d` / `in 2 weeks` / `in 4h`,
///             `2026-10-01`, `10/1`, `oct 1`, each optionally followed by a time (`3pm`, `15:00`)
///
/// A mark that makes no sense stays in the title as typed, so nothing the user wrote is lost.
struct QuickAdd: Equatable {
    var title = ""
    /// Key of the matched agent.
    var agent: String?
    var priority = NookTask.Priority.none
    var due: Date?
    var dueHasTime = false
    var tags: [String] = []

    struct AgentName: Equatable {
        var key: String
        var label: String
    }

    static func parse(_ line: String, agents: [AgentName], now: Date, calendar: Calendar = .current) -> QuickAdd {
        var result = QuickAdd()
        var words: [String] = []
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let lower = token.lowercased()
            index += 1
            if token.hasPrefix("@"), token.count > 1, let key = match(String(token.dropFirst()), in: agents) {
                result.agent = key
            } else if token.hasPrefix("!"), token.count > 1, let priority = priority(String(lower.dropFirst())) {
                result.priority = priority
            } else if token.hasPrefix("#"), token.count > 1 {
                let tag = String(lower.dropFirst())
                if !result.tags.contains(tag) { result.tags.append(tag) }
            } else if lower == "due" || lower == "due:" || lower.hasPrefix("due:") {
                var rest = Array(tokens[index...])
                if lower.hasPrefix("due:"), lower.count > 4 { rest.insert(String(lower.dropFirst(4)), at: 0) }
                if let (date, hasTime, used) = dueDate(rest.map { $0.lowercased() }, now: now, calendar: calendar) {
                    (result.due, result.dueHasTime) = (date, hasTime)
                    index += used - (lower.count > 4 ? 1 : 0)
                } else {
                    words.append(token)
                }
            } else {
                words.append(token)
            }
        }
        result.title = words.joined(separator: " ")
        return result
    }

    // MARK: agents

    /// Exact label, then a prefix, then a substring, then the letters in order ("zpd" finds
    /// "zipdemand"); among equals the shortest label, then the first listed.
    static func match(_ query: String, in agents: [AgentName]) -> String? {
        let query = query.lowercased()
        guard !query.isEmpty else { return nil }
        func rank(_ label: String) -> Int? {
            let label = label.lowercased()
            if label == query { return 0 }
            if label.hasPrefix(query) { return 1 }
            if label.contains(query) { return 2 }
            var rest = Substring(label)
            for letter in query {
                guard let at = rest.firstIndex(of: letter) else { return nil }
                rest = rest[rest.index(after: at)...]
            }
            return 3
        }
        return agents.enumerated().compactMap { offset, agent in rank(agent.label).map { (rank: $0, length: agent.label.count, offset: offset, key: agent.key) } }
            .min { ($0.rank, $0.length, $0.offset) < ($1.rank, $1.length, $1.offset) }?.key
    }

    private static func priority(_ word: String) -> NookTask.Priority? {
        [NookTask.Priority.low, .medium, .high, .urgent].first { $0.title.lowercased().hasPrefix(word) }
    }

    // MARK: dates

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// "fri", "friday", "thurs": at least three letters that begin one of the names.
    private static func index(of text: String?, in names: [String]) -> Int? {
        guard let text, text.count >= 3 else { return nil }
        return names.firstIndex { $0.hasPrefix(text) }
    }

    private static func unit(_ text: String) -> Calendar.Component? {
        switch text {
        case "h", "hr", "hrs", "hour", "hours": return .hour
        case "d", "day", "days": return .day
        case "w", "wk", "wks", "week", "weeks": return .weekOfYear
        case "mo", "month", "months": return .month
        default: return nil
        }
    }

    /// Reads a date from the front of `words`. Returns it, whether a time was given, and how many words it took.
    static func dueDate(_ words: [String], now: Date, calendar: Calendar) -> (Date, Bool, Int)? {
        guard let first = words.first else { return nil }
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date? { calendar.date(byAdding: .day, value: offset, to: today) }
        func word(_ n: Int) -> String? { n < words.count ? words[n] : nil }
        func number(_ text: String?) -> Int? { text.flatMap(Int.init) }
        /// Days until the coming such weekday: 1 to 7, never today.
        func ahead(_ weekday: Int) -> Int {
            let days = (weekday + 1 - calendar.component(.weekday, from: now) + 7) % 7
            return days == 0 ? 7 : days
        }
        /// The next such date, this year or next.
        func upcoming(month: Int, day: Int, year: Int? = nil) -> Date? {
            var parts = DateComponents(year: year ?? calendar.component(.year, from: now), month: month, day: day)
            guard (1...12).contains(month), (1...31).contains(day), var date = calendar.date(from: parts),
                  calendar.component(.day, from: date) == day else { return nil }
            if year == nil, date < today {
                parts.year = (parts.year ?? 0) + 1
                guard let next = calendar.date(from: parts) else { return nil }
                date = next
            }
            return date
        }
        /// "in 3 days", "in 4h": hours count from now and carry a time, the rest from today.
        func offset(_ count: Int, _ component: Calendar.Component, used: Int) -> (Date, Bool, Int)? {
            guard count > 0, let date = calendar.date(byAdding: component, value: count, to: component == .hour ? now : today) else { return nil }
            return (date, component == .hour, used)
        }

        var date: Date?
        var used = 1
        if first == "today" || first == "tonight" {
            date = today
        } else if first == "tomorrow" || first == "tmrw" || first == "tom" {
            date = day(1)
        } else if first == "in", let count = number(word(1)), let component = word(2).flatMap(unit) {
            return offset(count, component, used: 3)
        } else if first == "in", let text = word(1), let split = text.firstIndex(where: { !$0.isNumber }),
                  let count = Int(text[..<split]), let component = unit(String(text[split...])) {
            return offset(count, component, used: 2)
        } else if first == "next", let target = Self.index(of: word(1), in: weekdays) {
            // "next fri" is the Friday after the coming one.
            (date, used) = (day(ahead(target) + 7), 2)
        } else if let target = Self.index(of: first, in: weekdays) {
            date = day(ahead(target))
        } else if let m = Self.index(of: first, in: months), let d = number(word(1)) {
            (date, used) = (upcoming(month: m + 1, day: d), 2)
        } else if let d = number(first), let m = Self.index(of: word(1), in: months) {
            (date, used) = (upcoming(month: m + 1, day: d), 2)
        } else {
            let dash = first.split(separator: "-").map { Int($0) }
            let slash = first.split(separator: "/").map { Int($0) }
            if dash.count == 3, let y = dash[0], let m = dash[1], let d = dash[2] {
                date = upcoming(month: m, day: d, year: y)
            } else if slash.count == 2, let m = slash[0], let d = slash[1] {
                date = upcoming(month: m, day: d)
            } else if slash.count == 3, let m = slash[0], let d = slash[1], let y = slash[2] {
                date = upcoming(month: m, day: d, year: y < 100 ? 2000 + y : y)
            }
        }
        guard let date else { return nil }
        if let (hour, minute) = time(word(used)), let timed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) {
            return (timed, true, used + 1)
        }
        return (date, false, used)
    }

    /// "3pm", "9:30am", "15:00".
    static func time(_ text: String?) -> (Int, Int)? {
        guard var text, !text.isEmpty else { return nil }
        var half: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            half = suffix
            text.removeLast(2)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count <= 2, let first = parts.first, var hour = first else { return nil }
        let minute = parts.count == 2 ? parts[1] : 0
        guard let minute, (0..<60).contains(minute) else { return nil }
        if let half {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (half == "pm" ? 12 : 0)
        } else if parts.count == 1 {
            return nil // a bare number is not a time
        }
        return (0..<24).contains(hour) ? (hour, minute) : nil
    }
}
