import Foundation

/// Decides where a spoken sentence goes. Pure: no app state, no side effects, unit tested.
///
/// A wrong route is worse than a fallback, so a name only counts when it opens the sentence,
/// matches one agent clearly better than any other, and leaves something to send.
enum VoiceRouter {
    struct Agent: Equatable {
        let label: String
        /// Extra spoken names for labels the recogniser mangles ("ash crown" for asche-kron).
        var aliases: [String] = []
        var hasPending = false
    }

    enum Decision: Equatable {
        /// Send `text` to these agents (indices into the input array).
        case send(to: [Int], text: String)
        /// Answer this agent's pending permission.
        case permission(agent: Int, allow: Bool)
        /// Nothing sensible to do; tell the user why.
        case hint(String)
    }

    static func route(_ transcript: String, agents: [Agent], active: Int?, recent: Int?) -> Decision {
        var words = tokens(in: transcript)
        guard !words.isEmpty else { return .hint("Didn't catch that") }
        guard !agents.isEmpty else { return .hint("No agents yet. Add one from the menu bar.") }
        if words.count > 1, ["hey", "ok", "okay"].contains(words[0].text) { words.removeFirst() }

        // "allow" / "approve" / "deny" on their own, optionally with a name on either side.
        if let verdict = verdict(words.last!.text), let name = name(in: Array(words.dropLast()), agents: agents, whole: true) {
            return permission(name, verdict, agents, active)
        }
        if let verdict = verdict(words[0].text), let name = name(in: Array(words.dropFirst()), agents: agents, whole: true) {
            return permission(name, verdict, agents, active)
        }

        let fallback = [active, recent].compactMap { $0 }.first { agents.indices.contains($0) }

        let squashed = words.prefix(2).map(\.text).joined()
        let everyone = ["everyone", "everybody"].contains(words[0].text) ? 1 : (squashed == "allagents" ? 2 : 0)
        if everyone > 0, words.count > everyone {
            return .send(to: Array(agents.indices), text: rest(of: transcript, from: words[everyone]))
        }

        if case .agent(let index, let used) = name(in: words, agents: agents, whole: false) {
            guard used < words.count else { return .hint("Say what to tell \(agents[index].label)") }
            return .send(to: [index], text: rest(of: transcript, from: words[used]))
        }
        guard let fallback else { return .hint("Say an agent's name first, like \"\(agents[0].label), …\"") }
        return .send(to: [fallback], text: rest(of: transcript, from: words[0]))
    }

    // MARK: permissions

    private static func verdict(_ word: String) -> Bool? {
        switch word {
        case "allow", "approve": return true
        case "deny": return false
        default: return nil
        }
    }

    private static func permission(_ name: Name, _ allow: Bool, _ agents: [Agent], _ active: Int?) -> Decision {
        let target: Int
        switch name {
        case .agent(let index, _): target = index
        case .none:
            guard let active, agents.indices.contains(active) else {
                return .hint("Say which agent, like \"\(agents[0].label), \(allow ? "allow" : "deny")\"")
            }
            target = active
        }
        guard agents[target].hasPending else { return .hint("\(agents[target].label) isn't waiting for permission") }
        return .permission(agent: target, allow: allow)
    }

    // MARK: names

    private enum Name {
        case none
        case agent(Int, words: Int)
    }

    /// Finds an agent name at the start of `words`. With `whole`, the name must be all of them
    /// (and no words at all means "no name", which is a valid answer); an ambiguous or
    /// unrecognised name returns nil there so the sentence is not mistaken for a command.
    private static func name(in words: [Token], agents: [Agent], whole: Bool) -> Name? {
        if words.isEmpty { return Name.none }
        var best: (index: Int, words: Int, distance: Int)?
        var tied = false
        let spans = whole ? [words.count] : Array(1...min(4, words.count))
        for (index, agent) in agents.enumerated() {
            for spoken in [agent.label] + agent.aliases {
                let target = squash(spoken)
                guard !target.isEmpty else { continue }
                for span in spans {
                    let heard = words.prefix(span).map(\.text).joined()
                    guard let d = distance(heard, target) else { continue }
                    if let b = best {
                        // Exact beats fuzzy; then the longer span ("zip demand" over "zip").
                        if (d, -span) < (b.distance, -b.words) {
                            best = (index, span, d); tied = false
                        } else if (d, -span) == (b.distance, -b.words), b.index != index {
                            tied = true
                        }
                    } else {
                        best = (index, span, d)
                    }
                }
            }
        }
        guard let best, !tied else { return whole ? nil : Name.none }
        return .agent(best.index, words: best.words)
    }

    /// Edit distance if `heard` is close enough to `target` to count, else nil. Short names must
    /// match exactly: one slip in "api" or "tests" is a different word, not a misheard one.
    private static func distance(_ heard: String, _ target: String) -> Int? {
        if heard == target { return 0 }
        let allowed = target.count >= 12 ? 2 : (target.count >= 7 ? 1 : 0)
        guard allowed > 0, heard.first == target.first, abs(heard.count - target.count) <= allowed else { return nil }
        let d = levenshtein(Array(heard), Array(target))
        return d <= allowed ? d : nil
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }

    // MARK: text

    private struct Token {
        let text: String // lowercased, unaccented, letters and digits only
        let start: String.Index
    }

    private static func squash(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func tokens(in s: String) -> [Token] {
        var result: [Token] = []
        var start: String.Index?
        for i in s.indices {
            // An apostrophe stays inside a word, so "don't" is one token.
            let inside = s[i].isLetter || s[i].isNumber || ((s[i] == "'" || s[i] == "’") && start != nil)
            if inside, start == nil { start = i }
            if !inside, let from = start {
                result.append(Token(text: squash(String(s[from..<i])), start: from))
                start = nil
            }
        }
        if let from = start { result.append(Token(text: squash(String(s[from...])), start: from)) }
        return result.filter { !$0.text.isEmpty }
    }

    /// The original wording from `token` on, so the message's own punctuation and capitals survive.
    private static func rest(of s: String, from token: Token) -> String {
        s[token.start...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
