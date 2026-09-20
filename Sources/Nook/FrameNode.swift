import AppKit
import SpriteKit

/// The theme's border around a chamber (rock, for the dwarf mine) and the connector pieces that open
/// it toward a neighbouring window: a ladder up or down, a tunnel left or right.
final class FrameNode: SKNode {
    private var open: [RoomScene.Edge: SKSpriteNode] = [:]
    private var sealed: [RoomScene.Edge: SKSpriteNode] = [:]

    init(art: Art) {
        super.init()
        if let path = art.theme.frame?.overlay, let texture = try? art.texture(path) {
            let overlay = SKSpriteNode(texture: texture, size: CGSize(width: RoomScene.W, height: RoomScene.H))
            overlay.anchorPoint = .zero
            addChild(overlay)
        } else {
            // No frame art: the plain translucent header bar, so the title still reads.
            let bar = SKSpriteNode(color: NSColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 0.80), size: CGSize(width: RoomScene.W, height: RoomScene.bar))
            bar.anchorPoint = .zero
            bar.position = CGPoint(x: 0, y: RoomScene.H - RoomScene.bar)
            addChild(bar)
        }
        for edge in RoomScene.Edge.allCases {
            let connector = art.theme.frame?.connectors?[edge.key]
            open[edge] = piece(connector?.open, art)
            sealed[edge] = piece(connector?.sealed, art)
        }
        show([])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ edges: Set<RoomScene.Edge>) {
        for edge in RoomScene.Edge.allCases {
            open[edge]?.isHidden = !edges.contains(edge)
            sealed[edge]?.isHidden = edges.contains(edge)
        }
    }

    private func piece(_ piece: Theme.Piece?, _ art: Art) -> SKSpriteNode? {
        guard let piece, piece.position.count == 2, let texture = try? art.texture(piece.sprite) else { return nil }
        let sprite = SKSpriteNode(texture: texture, size: texture.size())
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: piece.position[0], y: piece.position[1])
        sprite.zPosition = 1
        addChild(sprite)
        return sprite
    }
}

extension RoomScene.Edge {
    /// The edge's name in theme.json.
    var key: String {
        switch self {
        case .top: return "top"
        case .bottom: return "bottom"
        case .left: return "left"
        case .right: return "right"
        }
    }
}
