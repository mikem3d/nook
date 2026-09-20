import AppKit
import SpriteKit

/// One scene of the theme: background, foreground, the vitals props where this scene places them,
/// and its ambient animations. The character is not part of it, so chambers can be swapped under him.
final class ChamberNode: SKNode {
    /// What the chamber shows when a layer will not load, so the window is never see-through.
    private static let bare = NSColor(red: 0.17, green: 0.16, blue: 0.23, alpha: 1)

    private struct PropNode {
        let sprite: SKSpriteNode
        let textures: [SKTexture]
        var shown = -1
    }

    private struct AmbientNode {
        let sprite: SKSpriteNode
        let textures: [SKTexture]
        let spec: Theme.Ambient
        var clock = 0.0
        var frame = 0
        var travel = 0.0
    }

    let spec: Theme.Scene
    private var props: [String: PropNode] = [:]
    private var ambient: [AmbientNode] = []

    init(art: Art, scene: Theme.Scene) {
        spec = scene
        super.init()
        let canvas = CGSize(width: RoomScene.W, height: RoomScene.H)
        for (path, z) in [(scene.bg, CGFloat(0)), (scene.fg, CGFloat(2))] {
            let texture = try? art.texture(path)
            guard texture != nil || z == 0 else { continue }
            let node = texture.map { SKSpriteNode(texture: $0, size: canvas) } ?? SKSpriteNode(color: Self.bare, size: canvas)
            node.anchorPoint = .zero
            node.zPosition = z
            addChild(node)
        }

        // Vital-sign props. Any that the theme does not declare are simply absent.
        let placements = scene.props ?? art.theme.props?.map { Theme.Placement(name: $0.name, position: $0.position, z: $0.z) } ?? []
        for place in placements where place.position.count == 2 {
            guard let (prop, textures) = art.states(forProp: place.name) else { continue }
            let sprite = SKSpriteNode(texture: textures[0], size: CGSize(width: prop.frame[0], height: prop.frame[1]))
            sprite.anchorPoint = .zero
            sprite.position = CGPoint(x: place.position[0], y: place.position[1])
            sprite.zPosition = place.z ?? prop.z
            addChild(sprite)
            props[place.name] = PropNode(sprite: sprite, textures: textures)
        }

        for spec in scene.ambient ?? [] where spec.frame.count == 2 && spec.position.count == 2 && spec.frames > 0 {
            guard let sheet = try? art.texture(spec.sheet) else { continue }
            let textures = art.strip(sheet, count: spec.frames)
            let sprite = SKSpriteNode(texture: textures[0], size: CGSize(width: spec.frame[0], height: spec.frame[1]))
            sprite.anchorPoint = .zero
            sprite.position = CGPoint(x: spec.position[0], y: spec.position[1])
            sprite.zPosition = spec.z
            sprite.isHidden = spec.path != nil
            addChild(sprite)
            ambient.append(AmbientNode(sprite: sprite, textures: textures, spec: spec))
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: vitals

    func states(_ name: String) -> Int { props[name]?.textures.count ?? 1 }

    /// Shows one state of a prop, or hides it (nil). Returns true if that changed anything.
    @discardableResult
    func set(_ name: String, _ state: Int?) -> Bool {
        guard var prop = props[name] else { return false }
        let index = state.map { min(max($0, 0), prop.textures.count - 1) } ?? -2
        guard index != prop.shown else { return false }
        prop.shown = index
        props[name] = prop
        prop.sprite.isHidden = state == nil
        if index >= 0 { prop.sprite.texture = prop.textures[index] }
        return true
    }

    func tint(_ name: String, _ color: NSColor, _ amount: CGFloat) {
        guard let sprite = props[name]?.sprite else { return }
        sprite.color = color
        sprite.colorBlendFactor = amount
    }

    // MARK: ambient

    /// Steps the ambient loops. With Reduce Motion they hold their first frame and nothing travels.
    func advance(_ dt: Double, still: Bool) {
        guard !still else { return }
        for i in ambient.indices {
            var a = ambient[i]
            a.clock += dt
            let step = 1.0 / max(a.spec.fps, 0.1)
            if a.clock >= step {
                a.clock = a.clock.truncatingRemainder(dividingBy: step)
                a.frame = (a.frame + 1) % a.textures.count
                a.sprite.texture = a.textures[a.frame]
            }
            if let path = a.spec.path, path.to.count == 2, path.seconds > 0 {
                a.travel = (a.travel + dt).truncatingRemainder(dividingBy: max(path.every, path.seconds))
                let t = CGFloat(a.travel / path.seconds)
                a.sprite.isHidden = t > 1
                if t <= 1 {
                    // Whole art pixels only, so the sprite never shimmers between them.
                    a.sprite.position = CGPoint(x: (a.spec.position[0] + (path.to[0] - a.spec.position[0]) * t).rounded(),
                                                y: (a.spec.position[1] + (path.to[1] - a.spec.position[1]) * t).rounded())
                }
            }
            ambient[i] = a
        }
    }
}
