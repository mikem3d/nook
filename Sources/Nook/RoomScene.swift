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
    private static let paper = NSColor.white
    /// Typewriter speed, and how long a finished page stays up before the next one.
    private static let revealRate = 60.0
    private static func dwell(_ characters: Int) -> Double { 1.5 + 0.04 * Double(characters) }

    private let art: Art
    private let pixels = SKNode()
    private let ui = SKNode()

    private let actor = SKSpriteNode()
    private let dim = SKSpriteNode(color: .black, size: CGSize(width: W, height: H))
    private let border = SKShapeNode()
    private let stateDot = SKSpriteNode(color: .gray, size: CGSize(width: 5, height: 5))
    private let badgeBox = SKSpriteNode(color: NSColor(red: 0.92, green: 0.25, blue: 0.22, alpha: 1), size: .zero)
    private let titleText = SKSpriteNode()
    private let badgeText = SKSpriteNode()
    private let bubbleBox = SKSpriteNode()
    private let bubbleText = SKSpriteNode()
    /// Two paper-coloured covers hide the text the typewriter has not reached yet:
    /// the rest of the current line, and every line below it.
    private let coverLine = SKSpriteNode(color: paper, size: .zero)
    private let coverBelow = SKSpriteNode(color: paper, size: .zero)

    private struct PropNode {
        let sprite: SKSpriteNode
        let textures: [SKTexture]
        var shown = -1
    }
    private var props: [String: PropNode] = [:]

    private let label: String
    private var scale: CGFloat = 2
    private var minimised = false
    private var state: AgentState = .idle
    private var bubble = ""
    private var unread = 0

    private var titleKey = ""
    private var badgeKey = ""
    private var pages: [[String]] = []
    private var page = 0
    private var revealed = 0.0
    private var held = 0.0

    private var contextFraction = 0.0
    private var cost = 0.0
    private var changedFiles = 0
    private var turnStarted: Date?
    private var vitalsClock = 1.0

    private var animation = ""
    private var frameIndex = 0
    private var clock = 0.0
    private var lastUpdate = 0.0
    private var flourish: String?
    private var nextFlourish = Double.random(in: 4...10)

    /// A minimised or fully hidden window stops its SKView; `wake` frames are drawn after a change first.
    private var occluded = false
    private var wake = 8
    private var fps = 15

    init(art: Art, roomIndex: Int, title name: String) {
        self.art = art
        label = name
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

        // Vital-sign props. Any that the manifest does not declare are simply absent.
        for name in ["window", "bookshelf", "coinjar", "papers", "clock", "hourglass"] {
            guard let (prop, textures) = art.states(forProp: name) else { continue }
            let sprite = SKSpriteNode(texture: textures[0], size: CGSize(width: prop.frame[0], height: prop.frame[1]))
            sprite.anchorPoint = .zero
            sprite.position = CGPoint(x: prop.position[0], y: prop.position[1])
            sprite.zPosition = prop.z
            pixels.addChild(sprite)
            props[name] = PropNode(sprite: sprite, textures: textures)
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

        badgeBox.anchorPoint = CGPoint(x: 1, y: 0)
        badgeBox.position = CGPoint(x: Self.W - 13, y: Self.H - Self.bar + 1)
        badgeBox.zPosition = 21
        badgeBox.isHidden = true
        pixels.addChild(badgeBox)

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

        titleText.anchorPoint = .zero
        badgeText.anchorPoint = .zero
        badgeText.isHidden = true
        bubbleBox.anchorPoint = .zero
        for node in [bubbleText, coverLine, coverBelow] { node.anchorPoint = CGPoint(x: 0, y: 1) }
        bubbleText.zPosition = 1
        coverLine.zPosition = 2
        coverBelow.zPosition = 2
        for node in [titleText, badgeText, bubbleBox, bubbleText, coverLine, coverBelow] { ui.addChild(node) }

        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        relayout()
        refreshVitals()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: inputs

    func configure(scale: CGFloat, minimised: Bool) {
        guard scale != self.scale || minimised != self.minimised else { return }
        self.scale = scale
        self.minimised = minimised
        relayout()
        poke()
    }

    func show(state: AgentState, bubble: String, unread: Int) {
        let changed = state != self.state || bubble != self.bubble || unread != self.unread
        self.state = state
        self.unread = unread
        if bubble != self.bubble {
            self.bubble = bubble
            page = 0
            revealed = 0
            held = 0
            relayout()
        } else {
            refreshBadge()
        }
        stateDot.color = Self.color(for: state)
        if changed { poke() }
    }

    /// The agent's vital signs, shown as props in the room. Cheap to call on every refresh:
    /// a prop is only touched when the state it shows changes.
    func showVitals(contextFraction: Double, cost: Double, changedFiles: Int, turnStarted: Date?) {
        guard contextFraction != self.contextFraction || cost != self.cost
            || changedFiles != self.changedFiles || turnStarted != self.turnStarted else { return }
        self.contextFraction = contextFraction
        self.cost = cost
        self.changedFiles = changedFiles
        self.turnStarted = turnStarted
        if refreshVitals() { poke() }
    }

    func setDimmed(_ on: Bool) { dim.isHidden = !on; poke() }
    func setActive(_ on: Bool) { border.isHidden = !on; poke() }

    // MARK: idle cost

    private var resting: Bool { minimised || occluded }

    /// Something visible changed: make sure a resting window draws it.
    private func poke() {
        wake = 8
        view?.isPaused = false
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow, window === view?.window else { return }
        occluded = !window.occlusionState.contains(.visible)
        poke()
    }

    // MARK: vitals

    @discardableResult
    private func set(_ name: String, _ state: Int?) -> Bool {
        guard var prop = props[name] else { return false }
        let index = state.map { min(max($0, 0), prop.textures.count - 1) } ?? -2
        guard index != prop.shown else { return false }
        prop.shown = index
        props[name] = prop
        prop.sprite.isHidden = state == nil
        if index >= 0 { prop.sprite.texture = prop.textures[index] }
        return true
    }

    private func states(_ name: String) -> Int { props[name]?.textures.count ?? 1 }

    /// Returns true if any prop changed.
    @discardableResult
    private func refreshVitals() -> Bool {
        var changed = set("bookshelf", Vitals.level(fraction: contextFraction, states: states("bookshelf")))
        if let shelf = props["bookshelf"]?.sprite {
            shelf.color = .red
            shelf.colorBlendFactor = contextFraction > Vitals.contextWarning ? 0.45 : 0
        }
        changed = set("coinjar", Vitals.coins(cost: cost, states: states("coinjar"))) || changed
        changed = set("papers", min(changedFiles, states("papers") - 1)) || changed
        changed = set("window", Vitals.sky(hour: Calendar.current.component(.hour, from: Date()), states: states("window"))) || changed

        let elapsed = turnStarted.map { Date().timeIntervalSince($0) }
        // The clock hand sweeps one step a second during a turn and rests at twelve otherwise.
        changed = set("clock", elapsed.map { Int($0) % states("clock") } ?? 0) || changed
        // The hourglass only appears once a turn has run long, and keeps turning over.
        let long = elapsed.map { $0 >= Vitals.longTurn } ?? false
        changed = set("hourglass", long ? Int(elapsed ?? 0) % states("hourglass") : nil) || changed
        return changed
    }

    // MARK: layout

    /// Points per font pixel, and a helper to go from font pixels to points.
    private var fp: CGFloat { PixelFont.pixel(atScale: scale) }

    private func setText(_ node: SKSpriteNode, lines: [String], color: NSColor) {
        guard let (texture, size) = PixelFont.shared.texture(lines: lines, color: color) else {
            node.texture = nil
            node.size = .zero
            return
        }
        node.texture = texture
        node.size = CGSize(width: size.width * fp, height: size.height * fp)
    }

    private func relayout() {
        let s = scale
        // Minimised windows show only the header strip, so slide everything down.
        let shift = minimised ? -(Self.H - Self.bar) * s : 0
        pixels.setScale(s)
        pixels.position = CGPoint(x: 0, y: shift)
        ui.position = CGPoint(x: 0, y: shift)

        let visibleBottom = minimised ? Self.H - Self.bar : 0
        border.path = CGPath(rect: CGRect(x: 0.5, y: visibleBottom + 0.5, width: Self.W - 1, height: Self.H - visibleBottom - 1), transform: nil)

        // Header text sits on the font-pixel grid, centred in the bar as nearly as that grid allows.
        let cell = CGFloat(PixelFont.cellW) * fp
        let room = Int((Self.W - 12 - 30) * s / cell)
        let shown = label.count > room ? String(label.prefix(max(room - 1, 1))) + "…" : label
        let key = "\(shown)|\(fp)"
        if key != titleKey {
            titleKey = key
            setText(titleText, lines: [shown], color: .white)
        }
        titleText.position = CGPoint(x: 12 * s, y: (Self.H - Self.bar) * s + headerInset)

        badgeKey = ""
        refreshBadge()
        layoutBubble()
    }

    private var headerInset: CGFloat { ((Self.bar * scale / fp - CGFloat(PixelFont.cellH)) / 2).rounded(.down) * fp }

    private func refreshBadge() {
        badgeBox.isHidden = unread == 0
        badgeText.isHidden = unread == 0
        guard unread > 0 else { return }
        let label = unread > 99 ? "99+" : String(unread)
        let key = "\(label)|\(fp)"
        guard key != badgeKey else { return }
        badgeKey = key
        setText(badgeText, lines: [label], color: .white)
        // The box is whole art pixels; the text is centred in it on the font grid.
        let width = (badgeText.size.width / scale).rounded(.up) + 2
        badgeBox.size = CGSize(width: width, height: Self.bar - 2)
        let left = (badgeBox.position.x - width) * scale
        let slack = ((width * scale - badgeText.size.width) / 2 / fp).rounded(.down) * fp
        badgeText.position = CGPoint(x: left + slack + fp, y: (Self.H - Self.bar) * scale + headerInset)
    }

    /// Characters per line and lines per page. The bubble is at most 36 px of text tall so the
    /// tail can still reach the character's head.
    private var bubbleGrid: (columns: Int, rows: Int) {
        let width: CGFloat = fp < scale ? 112 : 140
        return (Int(width * scale / (CGFloat(PixelFont.cellW) * fp)), Int(33 * scale / (CGFloat(PixelFont.cellH) * fp)))
    }

    private func layoutBubble() {
        let grid = bubbleGrid
        pages = minimised ? [] : TextPager.pages(bubble, columns: grid.columns, rows: grid.rows)
        page = min(page, max(pages.count - 1, 0))
        let nodes = [bubbleBox, bubbleText, coverLine, coverBelow]
        guard !pages.isEmpty else {
            nodes.forEach { $0.isHidden = true }
            return
        }
        let s = scale
        let lines = pages[page]
        setText(bubbleText, lines: lines, color: Self.ink)

        let (padX, padY): (CGFloat, CGFloat) = (3, 2)
        let width = max((bubbleText.size.width / s).rounded(.up) + padX * 2, 16)
        let height = (bubbleText.size.height / s).rounded(.up) + padY * 2
        let left = Self.W - 4 - width
        let top = Self.H - Self.bar - 2
        // The tail's tip lands just beside the character's head.
        let tip = art.manifest.character.feet[0] + 8
        let tailX = Int(min(max(tip + 3 - left, 4), width - 7))
        if let image = BubbleArt.image(width: Int(width), height: Int(height), tailX: tailX, more: page + 1 < pages.count,
                                       ink: Self.ink, paper: Self.paper) {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            bubbleBox.texture = texture
            bubbleBox.size = CGSize(width: width * s, height: (height + CGFloat(BubbleArt.tail)) * s)
        }
        bubbleBox.position = CGPoint(x: left * s, y: (top - height - CGFloat(BubbleArt.tail)) * s)
        bubbleText.position = CGPoint(x: (left + padX) * s, y: (top - padY) * s)
        bubbleBox.isHidden = false
        bubbleText.isHidden = false

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { revealed = Double(lines.reduce(0) { $0 + $1.count }) }
        layoutReveal()
    }

    /// Positions the covers so exactly `revealed` characters of the page show.
    private func layoutReveal() {
        guard page < pages.count else { return }
        let lines = pages[page]
        var left = Int(revealed)
        var row = 0
        while row < lines.count, left >= lines[row].count {
            left -= lines[row].count
            row += 1
        }
        let done = row >= lines.count
        coverLine.isHidden = done
        coverBelow.isHidden = done || row + 1 >= lines.count
        guard !done else { return }
        let (cw, ch) = (CGFloat(PixelFont.cellW) * fp, CGFloat(PixelFont.cellH) * fp)
        let origin = bubbleText.position
        let size = bubbleText.size
        coverLine.position = CGPoint(x: origin.x + CGFloat(left) * cw, y: origin.y - CGFloat(row) * ch)
        coverLine.size = CGSize(width: size.width - CGFloat(left) * cw, height: ch)
        coverBelow.position = CGPoint(x: origin.x, y: origin.y - CGFloat(row + 1) * ch)
        coverBelow.size = CGSize(width: size.width, height: size.height - CGFloat(row + 1) * ch)
    }

    /// Typewriter, then a pause, then the next page. Returns true while the typewriter is running.
    private func advanceBubble(_ dt: Double) -> Bool {
        guard page < pages.count else { return false }
        let total = Double(pages[page].reduce(0) { $0 + $1.count })
        if revealed < total {
            revealed = min(revealed + dt * Self.revealRate, total)
            layoutReveal()
            return true
        }
        guard page + 1 < pages.count else { return false }
        held += dt
        if held >= Self.dwell(Int(total)) {
            held = 0
            revealed = 0
            page += 1
            layoutBubble()
        }
        return false
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
        let dt = lastUpdate == 0 ? 0 : min(max(currentTime - lastUpdate, 0), 0.5)
        lastUpdate = currentTime

        let typing = advanceBubble(dt)
        // Time-driven props (clock hand, hourglass, the sky) only need a look once a second.
        vitalsClock += dt
        if vitalsClock >= 1 {
            vitalsClock = 0
            refreshVitals()
        }
        defer {
            // Only draw as often as what is on screen needs: 8 fps typing and the typewriter get 15,
            // the 3 to 5 fps idle poses 10, sleep 4. A resting window stops once its changes are drawn.
            let speed = art.manifest.character.animations[animation]?.fps ?? 3
            let wanted = typing || speed > 6 ? 15 : (state == .sleeping ? 4 : 10)
            if wanted != fps {
                fps = wanted
                view?.preferredFramesPerSecond = wanted
            }
            if resting {
                if wake > 0 { wake -= 1 } else { view?.isPaused = true }
            }
        }

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
