import AppKit
import SpriteKit

/// What a minimised window shows: the theme's round border with the agent's head inside and a gem in
/// the state's colour. Drawn from its bottom-left in art pixels, `RoomScene.orb` across; nothing is
/// drawn outside the circle, because the window behind it is square and has no shadow.
final class OrbNode: SKNode {
    private let art: Art
    private let avatar: Int
    private let portrait = SKSpriteNode()
    private let gem: SKSpriteNode
    private let alert = SKSpriteNode()
    private let work = SKSpriteNode()
    private let shade = SKShapeNode(circleOfRadius: RoomScene.orb / 2)
    private var workFrames: [SKTexture] = []
    private var workFPS = 4.0
    private var state: AgentState = .idle
    private var clock = 0.0
    private var workFrame = 0

    init(art: Art, avatar: Int) {
        self.art = art
        self.avatar = avatar
        let spec = art.theme.orb
        let size = CGSize(width: RoomScene.orb, height: RoomScene.orb)
        let centre = CGPoint(x: RoomScene.orb / 2, y: RoomScene.orb / 2)
        gem = SKSpriteNode(color: .white, size: CGSize(width: 4, height: 4))
        super.init()

        func layer(_ path: String?, z: CGFloat) -> Bool {
            guard let path, let texture = try? art.texture(path) else { return false }
            let sprite = SKSpriteNode(texture: texture, size: size)
            sprite.anchorPoint = .zero
            sprite.zPosition = z
            addChild(sprite)
            return true
        }
        let hasBack = layer(spec?.back, z: 0)
        if !layer(spec?.ring, z: 3) || !hasBack {
            // No orb art: a plain dark disc with a grey rim.
            let plain = SKShapeNode(circleOfRadius: RoomScene.orb / 2 - 1)
            plain.position = centre
            plain.fillColor = hasBack ? .clear : NSColor(red: 0.17, green: 0.16, blue: 0.23, alpha: 1)
            plain.strokeColor = NSColor(white: 0.55, alpha: 1)
            plain.lineWidth = 2
            plain.isAntialiased = false
            plain.zPosition = hasBack ? 3 : 0
            addChild(plain)
        }

        let inset = spec?.portraitPosition ?? [4, 4]
        portrait.anchorPoint = .zero
        portrait.position = CGPoint(x: inset.first ?? 4, y: inset.last ?? 4)
        portrait.zPosition = 1
        addChild(portrait)

        if let strip = spec?.work, strip.frame.count == 2, strip.position.count == 2, let sheet = try? art.texture(strip.sheet) {
            workFrames = art.strip(sheet, count: strip.frames)
            workFPS = strip.fps
            work.size = CGSize(width: strip.frame[0], height: strip.frame[1])
            work.anchorPoint = .zero
            work.position = CGPoint(x: strip.position[0], y: strip.position[1])
            work.zPosition = 3.5 // over the ring, like a badge at the lower right
            work.isHidden = true
            addChild(work)
        }

        if let path = spec?.alert, let texture = try? art.texture(path) {
            alert.texture = texture
            alert.size = size
            alert.anchorPoint = .zero
            alert.zPosition = 4
            alert.isHidden = true
            addChild(alert)
        }

        if let piece = spec?.gem, piece.position.count == 2, let texture = try? art.texture(piece.sprite) {
            gem.texture = texture
            gem.size = texture.size()
            gem.anchorPoint = .zero
            gem.position = CGPoint(x: piece.position[0], y: piece.position[1])
        } else {
            gem.position = CGPoint(x: RoomScene.orb / 2, y: 3)
        }
        gem.colorBlendFactor = 1
        gem.zPosition = 5
        addChild(gem)

        shade.position = centre
        shade.fillColor = NSColor.black.withAlphaComponent(0.55)
        shade.strokeColor = .clear
        shade.isAntialiased = false
        shade.zPosition = 6
        shade.isHidden = true
        addChild(shade)
        show(state: .idle, color: .gray)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// True while the orb has something moving: the alert pulse or the working pick.
    var animates: Bool { state == .alert || (state == .working && !workFrames.isEmpty) }

    func show(state: AgentState, color: NSColor) {
        guard state != self.state || portrait.texture == nil else { return }
        self.state = state
        gem.color = color
        if let head = art.portrait(state: state, avatar: avatar) {
            portrait.texture = head
            portrait.size = head.size()
        }
        work.isHidden = state != .working || workFrames.isEmpty
        if !work.isHidden { work.texture = workFrames[workFrame % workFrames.count] }
        alert.isHidden = state != .alert
        clock = 0
    }

    func setDimmed(_ on: Bool) { shade.isHidden = !on }

    /// The alert rim blinks twice a second and the pick swings at its own rate; with Reduce Motion
    /// both simply stay shown.
    func advance(_ dt: Double, still: Bool) {
        guard animates, !still else { return }
        clock += dt
        if state == .alert {
            alert.isHidden = Int(clock * 4) % 2 == 1
        } else {
            let step = 1.0 / max(workFPS, 0.1)
            guard clock >= step else { return }
            clock = clock.truncatingRemainder(dividingBy: step)
            workFrame = (workFrame + 1) % workFrames.count
            work.texture = workFrames[workFrame]
        }
    }
}
