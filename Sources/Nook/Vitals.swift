import Foundation

/// How raw numbers map to prop states. Pure, so it is unit tested; works for any number of states.
enum Vitals {
    /// Above this share of the context window the bookshelf turns red.
    static let contextWarning = 0.85
    /// A turn longer than this brings out the hourglass.
    static let longTurn: TimeInterval = 300

    /// Even steps from empty to full. Any use at all shows the first step.
    static func level(fraction: Double, states: Int) -> Int {
        guard states > 1, fraction > 0 else { return 0 }
        return min(Int((fraction * Double(states - 1)).rounded(.up)), states - 1)
    }

    /// Log scale: empty below one cent, full at $20, so both a cheap chat and a long day read at a glance.
    static func coins(cost: Double, states: Int) -> Int {
        guard states > 1, cost >= 0.01 else { return 0 }
        let t = log(cost / 0.01) / log(20 / 0.01)
        return min(1 + Int(t * Double(states - 2)), states - 1)
    }

    /// Sky states in order: day, dusk (also dawn), night.
    static func sky(hour: Int, states: Int) -> Int {
        let sky: Int
        switch hour {
        case 8..<17: sky = 0
        case 6..<8, 17..<20: sky = 1
        default: sky = 2
        }
        return min(sky, states - 1)
    }
}
