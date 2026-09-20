import AppKit
import SpriteKit

/// The pixel scene inside one agent window. Art lives in a scaled layer with
/// nearest-neighbour filtering; text lives in an unscaled layer so it stays crisp.
final class RoomScene: SKScene {
    static let W: CGFloat = 192
    static let H: CGFloat = 108
    static let bar: CGFloat = 11

    private static let flourishes = ["idle_sip", "idle_stretch", "idle_read", "idle_look"]
    private static let ink = NSColor(red: 0.10, green: 0.10, blue: 0.16, alpha: 1)

    private let art: Art
    private let pixels = SKNode()
    private let ui = SKNode()

    private let actor = SKSpriteNode()
    private let dim = SKSpriteNode(color: .black, size: CGSize(width: W, height: H))
    private let border = SKShapeNode()
    private let stateDot = SKSpriteNode(color: .gray, size: CGSize(width: 5, height: 5))
    private let title = SKLabelNode(fontNamed: "Menlo-Bold")
    private let badge = SKShapeNode()
    private let badgeText = SKLabelNode(fontNamed: "Menlo-Bold")
    private let bubbleBox = SKShapeNode()
    private let bubbleTail = SKShapeNode()
    private let bubbleText = SKLabelNode(fontNamed: "Menlo")

    private var scale: CGFloat = 2
    private var minimised = false
    private var state: AgentState = .idle
    private var bubble = ""
    private var unread = 0

    private var animation = ""
    private var frameIndex = 0
    private var clock = 0.0
    private var lastUpdate = 0.0
    private var flourish: String?
    private var nextFlourish = Double.random(in: 4...10)

    init(art: Art, roomIndex: Int, title name: String) {
        self.art = art
        super.init(size: CGSize(width: Self.W * 2, height: Self.H * 2))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear

        addChild(pixels)
        addChild(ui)
        ui.zPosition = 100

        let room = art.manifest.rooms[roomIndex % art.manifest.rooms.count]
        for (path, z) in [(room.bg, CGFloat(0)), (room.fg, CGFloat(2))] {
            guard let texture = try? art.texture(path) else { continue }
            let node = SKSpriteNode(texture: texture, size: CGSize(width: Self.W, height: Self.H))
            node.anchorPoint = .zero
            node.zPosition = z
            pixels.addChild(node)
        }

        let c = art.manifest.character
        actor.size = CGSize(width: c.frame[0], height: c.frame[1])
        actor.anchorPoint = CGPoint(x: 0.5, y: 0)
        actor.position = CGPoint(x: c.feet[0], y: c.feet[1])
        actor.zPosition = 1
        pixels.addChild(actor)

        let header = SKSpriteNode(color: NSColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 0.80), size: CGSize(width: Self.W, height: Self.bar))
        header.anchorPoint = .zero
        header.position = CGPoint(x: 0, y: Self.H - Self.bar)
        header.zPosition = 20
        pixels.addChild(header)

        stateDot.position = CGPoint(x: 6.5, y: Self.H - Self.bar / 2)
        stateDot.zPosition = 21
        pixels.addChild(stateDot)

        let minimise = SKSpriteNode(color: .white, size: CGSize(width: 5, height: 1))
        minimise.position = CGPoint(x: Self.W - 6.5, y: Self.H - Self.bar / 2)
        minimise.zPosition = 21
        pixels.addChild(minimise)

        dim.anchorPoint = .zero
        dim.alpha = 0.55
        dim.zPosition = 50
        dim.isHidden = true
        pixels.addChild(dim)

        border.strokeColor = NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1)
        border.fillColor = .clear
        border.lineWidth = 1
        border.isAntialiased = false
        border.zPosition = 60
        border.isHidden = true
        pixels.addChild(border)

        title.text = name
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.fontColor = .white
        ui.addChild(title)

        badge.fillColor = NSColor(red: 0.92, green: 0.25, blue: 0.22, alpha: 1)
        badge.strokeColor = .clear
        badge.isHidden = true
        badgeText.horizontalAlignmentMode = .center
        badgeText.verticalAlignmentMode = .center
        badgeText.fontColor = .white
        badge.addChild(badgeText)
        ui.addChild(badge)

        for shape in [bubbleBox, bubbleTail] {
            shape.fillColor = .white
            shape.strokeColor = Self.ink
            shape.isAntialiased = false
            shape.isHidden = true
            ui.addChild(shape)
        }
        bubbleTail.zPosition = 1
        bubbleText.fontColor = Self.ink
        bubbleText.horizontalAlignmentMode = .left
        bubbleText.verticalAlignmentMode = .top
        bubbleText.numberOfLines = 0
        bubbleText.lineBreakMode = .byWordWrapping
        bubbleText.zPosition = 2
        bubbleBox.addChild(bubbleText)

        relayout()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: inputs

    func configure(scale: CGFloat, minimised: Bool) {
        self.scale = scale
        self.minimised = minimised
        relayout()
    }

    func show(state: AgentState, bubble: String, unread: Int) {
        self.state = state
        self.unread = unread
        if bubble != self.bubble {
            self.bubble = bubble
            relayout()
        } else {
            refreshBadge()
        }
        stateDot.color = Self.color(for: state)
    }

    func setDimmed(_ on: Bool) { dim.isHidden = !on }
    func setActive(_ on: Bool) { border.isHidden = !on }

    // MARK: layout

    private func relayout() {
        let s = scale
        // Minimised windows show only the header strip, so slide everything down.
        let shift = minimised ? -(Self.H - Self.bar) * s : 0
        pixels.setScale(s)
        pixels.position = CGPoint(x: 0, y: shift)
        ui.position = CGPoint(x: 0, y: shift)

        let visibleBottom = minimised ? Self.H - Self.bar : 0
        border.path = CGPath(rect: CGRect(x: 0.5, y: visibleBottom + 0.5, width: Self.W - 1, height: Self.H - visibleBottom - 1), transform: nil)

        title.fontSize = 5.5 * s
        title.position = CGPoint(x: 12 * s, y: (Self.H - Self.bar / 2) * s)

        refreshBadge()

        let text = bubble.count > 110 ? String(bubble.prefix(110)) + "..." : bubble
        let show = !text.isEmpty && !minimised
        bubbleBox.isHidden = !show
        bubbleTail.isHidden = !show
        guard show else { return }

        let width = 118 * s
        let pad = 3 * s
        bubbleText.fontSize = 5 * s
        bubbleText.preferredMaxLayoutWidth = width - pad * 2
        bubbleText.text = text
        let height = bubbleText.frame.height + pad * 2
        let left = (Self.W - 4) * s - width
        let top = (Self.H - Self.bar - 2) * s
        bubbleBox.lineWidth = s / 2
        bubbleBox.path = CGPath(rect: CGRect(x: left, y: top - height, width: width, height: height), transform: nil)
        bubbleText.position = CGPoint(x: left + pad, y: top - pad)
        bubbleTail.lineWidth = s / 2
        bubbleTail.path = CGPath(rect: CGRect(x: left + 22 * s, y: top - height - 3 * s, width: 3 * s, height: 3 * s), transform: nil)
    }

    private func refreshBadge() {
        badge.isHidden = unread == 0
        guard unread > 0 else { return }
        let s = scale
        let label = unread > 99 ? "99+" : String(unread)
        let width = max(9, CGFloat(label.count) * 4 + 5) * s
        let rect = CGRect(x: -width / 2, y: -4 * s, width: width, height: 8 * s)
        badge.path = CGPath(roundedRect: rect, cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil)
        badge.position = CGPoint(x: (Self.W - 14) * s - width / 2, y: (Self.H - Self.bar / 2) * s)
        badgeText.fontSize = 5.5 * s
        badgeText.text = label
    }

    private static func color(for state: AgentState) -> NSColor {
        switch state {
        case .idle: return NSColor(white: 0.65, alpha: 1)
        case .thinking: return NSColor(red: 0.98, green: 0.80, blue: 0.30, alpha: 1)
        case .working: return NSColor(red: 0.40, green: 0.85, blue: 0.50, alpha: 1)
        case .talking: return NSColor(red: 0.45, green: 0.70, blue: 1.00, alpha: 1)
        case .alert: return NSColor(red: 1.00, green: 0.35, blue: 0.30, alpha: 1)
        case .done: return NSColor(red: 0.60, green: 1.00, blue: 0.70, alpha: 1)
        case .sleeping: return NSColor(white: 0.35, alpha: 1)
        }
    }

    // MARK: animation

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 0.5)
        lastUpdate = currentTime

        if state == .idle {
            nextFlourish -= dt
            if flourish == nil, nextFlourish <= 0 {
                flourish = Self.flourishes.filter { art.manifest.character.animations[$0] != nil }.randomElement()
                nextFlourish = Double.random(in: 6...14)
            }
        } else {
            flourish = nil
        }

        let wanted: String
        switch state {
        case .idle: wanted = flourish ?? "idle_breathe"
        case .thinking: wanted = "think"
        case .working: wanted = "type"
        case .talking: wanted = "talk"
        case .alert: wanted = "alert"
        case .done: wanted = "celebrate"
        case .sleeping: wanted = "sleep"
        }
        if wanted != animation {
            animation = wanted
            frameIndex = 0
            clock = 0
        }
        guard let def = art.manifest.character.animations[animation] else { return }

        clock += dt
        let step = 1.0 / max(def.fps, 0.1)
        while clock >= step {
            clock -= step
            frameIndex += 1
            if frameIndex >= def.frames {
                if def.looping {
                    frameIndex = 0
                } else {
                    frameIndex = def.frames - 1
                    flourish = nil
                }
            }
        }
        let textures = art.frames(for: animation)
        if frameIndex < textures.count, actor.texture !== textures[frameIndex] {
            actor.texture = textures[frameIndex]
        }
    }
}
