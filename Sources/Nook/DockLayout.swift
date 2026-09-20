import CoreGraphics

/// The docking maths for one screen: corner stacks in, window frames out. No windows, no screens,
/// only rectangles, so it can be unit tested.
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
        /// One entry per window, from the corner inward: is it minimised to its header strip?
        let minimised: [Bool]
    }

    struct Placement: Equatable {
        let scale: CGFloat
        let lines: Int
        let frames: [CGRect]
    }

    var canvas = CGSize(width: 192, height: 108)
    var bar: CGFloat = 11
    var margin: CGFloat = 12
    var gap: CGFloat = 8
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
        CGSize(width: canvas.width * s, height: (minimised ? bar : canvas.height) * s)
    }

    /// Frames for one stack, wrapped evenly into `lines` lines that grow away from the screen edge.
    func frames(for stack: Stack, in area: CGRect, scale s: CGFloat, lines: Int) -> [CGRect] {
        let count = stack.minimised.count
        guard count > 0 else { return [] }
        let perLine = Int((Double(count) / Double(max(lines, 1))).rounded(.up))
        let corner = stack.corner
        var result: [CGRect] = []
        var across = margin
        var start = 0
        while start < count {
            let line = Array(stack.minimised[start..<min(start + perLine, count)])
            var along = margin
            var thickness: CGFloat = 0
            for minimised in line {
                let sz = size(minimised, s)
                let (dx, dy) = stack.axis == .vertical ? (across, along) : (along, across)
                let x = corner.isRight ? area.maxX - dx - sz.width : area.minX + dx
                let y = corner.isBottom ? area.minY + dy : area.maxY - dy - sz.height
                result.append(CGRect(x: x, y: y, width: sz.width, height: sz.height))
                along += (stack.axis == .vertical ? sz.height : sz.width) + gap
                thickness = max(thickness, stack.axis == .vertical ? sz.width : sz.height)
            }
            across += thickness + gap
            start += perLine
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
            let lineCounts = 1...max(1, min(maxLines, stacks[i].minimised.count))
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
                for j in stacks.indices where j > i && Self.overlap(now[i], now[j]) {
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
