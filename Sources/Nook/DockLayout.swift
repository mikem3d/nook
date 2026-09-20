import CoreGraphics

/// The docking maths for one screen: corner stacks in, window frames out. No windows, no screens,
/// only rectangles, so it can be unit tested.
///
/// Windows in one stack abut with no gap, so their chambers read as one cutaway mountain joined
/// by ladders and tunnels; separate stacks keep `gap` between them. Minimised windows are small
/// square orbs. Orbs between chambers would break the mountain, so whatever the window order,
/// a stack lays out its chambers first and gathers its orbs at the far end, away from the corner.
/// In a column the orbs hug the screen edge; in a row they stand on the floor of their line.
///
/// Every stack starts as one line at the largest scale. When stacks collide with each other or
/// with a reserved rectangle (the chat panel), the longest offender first shrinks, then wraps
/// into more lines, and only a bottom stack that still hits the reserved rectangle is lifted
/// above it. Frames never overlap unless the screen is simply too small for the windows.
struct DockLayout {
    enum Axis: String, Codable { case vertical, horizontal }

    struct Stack {
        let corner: Corner
        let axis: Axis
        /// One entry per window, from the corner inward: is it minimised to an orb?
        let minimised: [Bool]
    }

    struct Placement: Equatable {
        let scale: CGFloat
        let lines: Int
        let frames: [CGRect]
    }

    var canvas = CGSize(width: 192, height: 108)
    /// Side of a minimised window's square, in art pixels.
    var orb: CGFloat = 28
    var margin: CGFloat = 12
    /// Kept clear between separate stacks. Inside a stack chambers touch.
    var gap: CGFloat = 8
    /// Between orbs, and between the last chamber and the first orb.
    var orbGap: CGFloat = 4
    /// Scales to try, preferred first.
    var scales: [CGFloat] = [2, 1.5, 1]
    /// Scales used only when nothing in `scales` works at any line count (a fixed user scale on a small screen).
    var fallbackScales: [CGFloat] = []
    var maxLines = 3

    private struct Option {
        let scale: CGFloat
        let lines: Int
    }

    private func size(_ minimised: Bool, _ s: CGFloat) -> CGSize {
        minimised ? CGSize(width: orb * s, height: orb * s) : CGSize(width: canvas.width * s, height: canvas.height * s)
    }

    /// Frames for one stack, in window order. Chambers wrap evenly into `lines` lines that grow
    /// away from the screen edge; orbs follow the last chamber and wrap only when they run out of screen.
    func frames(for stack: Stack, in area: CGRect, scale s: CGFloat, lines: Int) -> [CGRect] {
        let count = stack.minimised.count
        guard count > 0 else { return [] }
        let corner = stack.corner
        let vertical = stack.axis == .vertical
        let chambers = (0..<count).filter { !stack.minimised[$0] }
        let orbs = (0..<count).filter { stack.minimised[$0] }
        var result = [CGRect](repeating: .zero, count: count)
        var across = margin
        var along = margin
        var thickness: CGFloat = 0

        func put(_ index: Int, _ sz: CGSize) {
            thickness = max(thickness, vertical ? sz.width : sz.height)
            let (dx, dy) = vertical ? (across, along) : (along, across)
            let x = corner.isRight ? area.maxX - dx - sz.width : area.minX + dx
            // A row hanging from the top edge still stands things on its floor, not its ceiling.
            let drop = vertical ? sz.height : thickness
            let y = corner.isBottom ? area.minY + dy : area.maxY - dy - drop
            result[index] = CGRect(x: x, y: y, width: sz.width, height: sz.height)
            along += vertical ? sz.height : sz.width
        }

        let room = size(false, s)
        let perLine = Int((Double(chambers.count) / Double(max(lines, 1))).rounded(.up))
        for (n, index) in chambers.enumerated() {
            if n > 0, n % perLine == 0 {
                across += thickness
                along = margin
                thickness = 0
            }
            put(index, room)
        }

        let disc = size(true, s)
        let limit = (vertical ? area.height : area.width) - margin
        if !chambers.isEmpty { along += orbGap }
        for index in orbs {
            if along > margin, along + disc.width > limit + 0.5 {
                across += thickness + orbGap
                along = margin
                thickness = 0
            }
            put(index, disc)
            along += orbGap
        }
        return result
    }

    private func fits(_ frames: [CGRect], in area: CGRect) -> Bool {
        let inner = area.insetBy(dx: margin - 0.5, dy: margin - 0.5)
        return frames.allSatisfy { inner.contains($0) }
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX - 0.5 && b.minX < a.maxX - 0.5 && a.minY < b.maxY - 0.5 && b.minY < a.maxY - 0.5
    }

    private static func overlap(_ a: [CGRect], _ b: [CGRect]) -> Bool {
        a.contains { r in b.contains { overlap(r, $0) } }
    }

    /// Solves every stack on one screen. `area` is the screen's visible frame in global coordinates
    /// (any origin, negative included). `reserved` is kept clear if at all possible.
    func solve(area: CGRect, stacks: [Stack], reserved: CGRect? = nil) -> [Corner: Placement] {
        let stacks = stacks.filter { !$0.minimised.isEmpty }.sorted { $0.corner.rawValue < $1.corner.rawValue }
        guard !stacks.isEmpty else { return [:] }

        // Per stack: the area it lays out in (shrunk from the bottom once lifted) and its options in order.
        var areas = stacks.map { _ in area }
        func options(_ i: Int) -> [Option] {
            let lineCounts = 1...max(1, min(maxLines, stacks[i].minimised.filter { !$0 }.count))
            let all = [scales, fallbackScales].flatMap { group in lineCounts.flatMap { n in group.map { Option(scale: $0, lines: n) } } }
            let fitting = all.filter { fits(frames(for: stacks[i], in: areas[i], scale: $0.scale, lines: $0.lines), in: areas[i]) }
            // Nothing fits: the smallest single line is the least bad.
            return fitting.isEmpty ? [Option(scale: (scales + fallbackScales).min() ?? 1, lines: 1)] : fitting
        }
        var choices = stacks.indices.map { options($0) }
        var picked = stacks.map { _ in 0 }
        var lifted = stacks.map { _ in false }

        func current(_ i: Int) -> [CGRect] {
            let o = choices[i][picked[i]]
            return frames(for: stacks[i], in: areas[i], scale: o.scale, lines: o.lines)
        }

        for _ in 0..<64 {
            let now = stacks.indices.map(current)
            var offenders = Set<Int>()
            var blocked = Set<Int>() // colliding with the reserved rectangle
            for i in stacks.indices {
                if let reserved, now[i].contains(where: { Self.overlap($0, reserved) }) {
                    offenders.insert(i)
                    blocked.insert(i)
                }
                // Separate stacks keep a gap, so only windows of one stack ever connect.
                let kept = now[i].map { $0.insetBy(dx: -gap, dy: -gap) }
                for j in stacks.indices where j > i && Self.overlap(kept, now[j]) {
                    offenders.insert(i)
                    offenders.insert(j)
                }
            }
            if offenders.isEmpty { break }

            // The longest stack that can still give way does so.
            let movable = offenders.filter { picked[$0] + 1 < choices[$0].count }
            if let i = movable.max(by: { (stacks[$0].minimised.count, -$0) < (stacks[$1].minimised.count, -$1) }) {
                picked[i] += 1
                continue
            }
            // Out of options: a bottom stack under the chat panel moves above it and starts again.
            if let reserved, let i = blocked.first(where: { stacks[$0].corner.isBottom && !lifted[$0] }) {
                lifted[i] = true
                let bottom = min(reserved.maxY, area.maxY)
                areas[i] = CGRect(x: area.minX, y: bottom, width: area.width, height: area.maxY - bottom)
                choices[i] = options(i)
                picked[i] = 0
                continue
            }
            break
        }

        var result: [Corner: Placement] = [:]
        for i in stacks.indices {
            let o = choices[i][picked[i]]
            result[stacks[i].corner] = Placement(scale: o.scale, lines: o.lines, frames: current(i))
        }
        return result
    }
}
