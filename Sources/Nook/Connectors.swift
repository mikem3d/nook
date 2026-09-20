import CoreGraphics

/// Which chambers touch. The scene opens a ladder or a tunnel on every edge listed here, so two
/// frames only count as neighbours when they meet exactly and line up: same size along the shared
/// edge and no offset, which is what makes the art on both sides of the joint meet.
///
/// Purely geometric: windows of one stack always qualify, and so do windows of different stacks
/// (or displays) that happen to abut exactly.
enum Connectors {
    private static let slack: CGFloat = 0.5

    /// One set per frame, in the same order. Pass chambers only: orbs and a dragged window connect to nothing.
    static func edges(_ frames: [CGRect]) -> [Set<RoomScene.Edge>] {
        frames.map { a in
            var edges = Set<RoomScene.Edge>()
            for b in frames {
                let column = abs(a.minX - b.minX) < slack && abs(a.width - b.width) < slack
                let row = abs(a.minY - b.minY) < slack && abs(a.height - b.height) < slack
                if column, abs(a.maxY - b.minY) < slack { edges.insert(.top) }
                if column, abs(a.minY - b.maxY) < slack { edges.insert(.bottom) }
                if row, abs(a.maxX - b.minX) < slack { edges.insert(.right) }
                if row, abs(a.minX - b.maxX) < slack { edges.insert(.left) }
            }
            return edges
        }
    }
}
