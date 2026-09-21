import AppKit
import SpriteKit

/// The pixel scene inside one agent window: a chamber of the theme, framed by its border, with the
/// agent's character at work in it. Art lives in a scaled layer with nearest-neighbour filtering;
/// text lives in an unscaled layer so it stays crisp. Minimised, it shows only a round portrait.
final class RoomScene: SKScene {
    static let W: CGFloat = 192
    static let H: CGFloat = 108
    static let bar: CGFloat = 11
    /// Header layout in art pixels: [gem][ladder hatch][title ... badge][minimise][close].
    private static let titleX: CGFloat = 30
    private static let badgeRight = W - minimiseHit - 2

    private static let flourishes = ["idle_sip", "idle_stretch", "idle_read", "idle_look"]
    private static let ink = NSColor(red: 0.10, green: 0.10, blue: 0.16, alpha: 1)
    private static let paper = NSColor.white
    /// Typewriter speed, and how long a finished page stays up before the next one.
    private static let revealRate = 60.0
    private static func dwell(_ characters: Int) -> Double { 1.5 + 0.04 * Double(characters) }

    private let art: Art
    private let pixels = SKNode()
    private let ui = SKNode()

    /// Everything a full window shows and an orb does not.
    private let room = SKNode()
    private var chamber: ChamberNode
    private let surround: FrameNode
    private let orbNode: OrbNode
    private let avatar: Int
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

    private let label: String
    private var scale: CGFloat = 2
    private var minimised = false
    private var state: AgentState = .idle
    private var bubble = ""
    private var unread = 0
    private var edges = Set<Edge>()
    /// The orb's unread badge bobs one art pixel to catch the eye.
    private var badgeLift: CGFloat = 0
    private var orbClock = 0.0
    /// Reduce Motion: no typewriter, no ambient loops, no pulses, no crossfade.
    private var still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

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
    /// A resting window keeps drawing until this time, so a change is on screen before it pauses.
    private var awakeUntil = CACurrentMediaTime() + 1
    private var fps = 15

    /// `roomIndex` picks the first scene round-robin; `avatarSeed` (the agent's folder path, else the
    /// title) picks which of the theme's characters this agent is, the same one on every launch.
    init(art: Art, roomIndex: Int, title name: String, avatarSeed: String? = nil) {
        self.art = art
        label = name
        avatar = art.avatarIndex(for: avatarSeed ?? name)
        chamber = ChamberNode(art: art, scene: art.scene(at: roomIndex))
        surround = FrameNode(art: art)
        orbNode = OrbNode(art: art, avatar: avatar)
        super.init(size: CGSize(width: Self.W * 2, height: Self.H * 2))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear

        addChild(pixels)
        addChild(ui)
        ui.zPosition = 100
        pixels.addChild(room)
        pixels.addChild(orbNode)
        orbNode.isHidden = true

        room.addChild(chamber)
        surround.zPosition = 10
        room.addChild(surround)

        let c = art.theme.character
        actor.size = CGSize(width: c.frame[0], height: c.frame[1])
        actor.anchorPoint = CGPoint(x: 0.5, y: 0)
        actor.zPosition = 1
        room.addChild(actor)
        placeActor()

        stateDot.position = CGPoint(x: 6.5, y: Self.H - Self.bar / 2)
        stateDot.zPosition = 21
        room.addChild(stateDot)

        let minimise = SKSpriteNode(color: .white, size: CGSize(width: 5, height: 1))
        minimise.position = CGPoint(x: Self.W - (Self.closeHit + Self.minimiseHit) / 2 - 0.5, y: Self.H - Self.bar / 2 - 2)
        let close = PixelGlyph.sprite(PixelGlyph.close)
        close.position = CGPoint(x: Self.W - Self.closeHit / 2 - 0.5, y: Self.H - Self.bar / 2)
        for glyph in [minimise, close] {
            glyph.zPosition = 21
            room.addChild(glyph)
        }

        badgeBox.anchorPoint = CGPoint(x: 1, y: 0)
        badgeBox.zPosition = 21
        badgeBox.isHidden = true
        pixels.addChild(badgeBox)

        dim.anchorPoint = .zero
        dim.alpha = 0.55
        dim.zPosition = 50
        dim.isHidden = true
        room.addChild(dim)

        border.strokeColor = NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1)
        border.fillColor = .clear
        border.lineWidth = 1
        border.isAntialiased = false
        border.zPosition = 60
        border.isHidden = true
        border.path = CGPath(rect: CGRect(x: 0.5, y: 0.5, width: Self.W - 1, height: Self.H - 1), transform: nil)
        room.addChild(border)

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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        relayout()
        refreshVitals()
        for name in [TextSize.changed, NSWindow.didChangeBackingPropertiesNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(textMetricsChanged), name: name, object: nil)
        }
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
        orbNode.show(state: state, color: Self.color(for: state))
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

    func setDimmed(_ on: Bool) {
        dim.isHidden = !on
        orbNode.setDimmed(on)
        poke()
    }

    // --- Contract between the scene and the window chrome (themes work, 2026-09). ---

    /// A side of the window that touches another agent's window in the same stack.
    enum Edge: CaseIterable { case top, bottom, left, right }

    /// Diameter, in art pixels, of the circular portrait a minimised window shows.
    static let orb: CGFloat = 28
    /// Header hit areas in art pixels, measured from the window's right edge: [close][minimise].
    static let closeHit: CGFloat = 12
    static let minimiseHit: CGFloat = 24

    /// The chrome tells the scene which sides have a neighbour; the scene opens a ladder or
    /// tunnel there so chambers connect. Empty set: a sealed chamber.
    func setNeighbours(_ edges: Set<Edge>) {
        guard edges != self.edges else { return }
        self.edges = edges
        surround.show(edges)
        poke()
    }

    /// Switches this window to another scene of the current theme (see `Art.sceneChoices`).
    /// An unknown id is ignored. The old chamber fades into the new one, or is simply replaced
    /// when the window is an orb or Reduce Motion is on.
    func setScene(_ id: String) {
        guard id != sceneID, let scene = art.scene(id) else { return }
        let old = chamber
        chamber = ChamberNode(art: art, scene: scene)
        room.addChild(chamber)
        placeActor()
        animation = ""
        refreshVitals()
        layoutBubble()
        if minimised || still {
            old.removeFromParent()
        } else {
            // Slightly above the old chamber layer for layer, still under the character and the frame.
            chamber.zPosition = 0.05
            chamber.alpha = 0
            chamber.run(.fadeIn(withDuration: Self.sceneFade)) { [chamber] in chamber.zPosition = 0 }
            old.run(.sequence([.wait(forDuration: Self.sceneFade), .removeFromParent()]))
        }
        poke()
    }

    /// The scene this window shows now; one of `Art.sceneChoices`.
    var sceneID: String { chamber.spec.id }

    func setActive(_ on: Bool) { border.isHidden = !on; poke() }

    private static let sceneFade = 0.25

    private func placeActor() {
        let feet = chamber.spec.feet ?? art.theme.character.feet
        actor.position = CGPoint(x: feet.first ?? Self.W / 2, y: feet.last ?? 0)
    }

    /// The animation this scene wants in place of a default one: hammering instead of typing, say.
    private func staged(_ name: String) -> String {
        guard let other = chamber.spec.animations?[name], art.theme.character.animations[other] != nil else { return name }
        return other
    }

    // MARK: idle cost

    /// An orb only keeps drawing while it has something to say: the alert pulse, the working pick,
    /// or a bobbing unread badge. A hidden window never does.
    private var resting: Bool { occluded || (minimised && !orbNode.animates && unread == 0) }

    /// Something visible changed: make sure a resting window draws it.
    private func poke() {
        awakeUntil = CACurrentMediaTime() + 1
        view?.isPaused = false
    }

    @objc private func motionChanged() {
        still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        poke()
    }

    /// The window animates between chamber and orb sizes. A paused view would keep showing its
    /// last frame stretched to the new size, so every size step buys more drawing time.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        poke()
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow, window === view?.window else { return }
        occluded = !window.occlusionState.contains(.visible)
        poke()
    }

    // MARK: vitals

    /// Returns true if any prop changed.
    @discardableResult
    private func refreshVitals() -> Bool {
        let chamber = self.chamber
        let (set, states) = (chamber.set, chamber.states)
        var changed = set("bookshelf", Vitals.level(fraction: contextFraction, states: states("bookshelf")))
        chamber.tint("bookshelf", .red, contextFraction > Vitals.contextWarning ? 0.45 : 0)
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
    private var fp: CGFloat {
        PixelFont.pixel(atScale: scale, backing: (view?.window?.screen ?? NSScreen.main)?.backingScaleFactor ?? 2)
    }

    /// The text-size setting changed, or the window moved to a display with another density.
    @objc private func textMetricsChanged() {
        relayout()
        poke()
    }

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
        pixels.setScale(s)
        // A minimised window is an orb-sized square showing nothing but the portrait.
        room.isHidden = minimised
        orbNode.isHidden = !minimised
        titleText.isHidden = minimised

        badgeKey = ""
        refreshBadge()
        layoutBubble()
    }

    private var headerInset: CGFloat { ((Self.bar * scale / fp - CGFloat(PixelFont.cellH)) / 2).rounded(.down) * fp }

    /// Header text sits on the font-pixel grid, centred in the bar as nearly as that grid allows,
    /// and stops short of the unread badge, whose width depends on the count and the font pixel.
    private func layoutTitle(badgeWidth: CGFloat) {
        let cell = CGFloat(PixelFont.cellW) * fp
        let columns = Int((Self.badgeRight - badgeWidth - Self.titleX - 2) * scale / cell)
        let shown = label.count > columns ? String(label.prefix(max(columns - 1, 1))) + "…" : label
        let key = "\(shown)|\(fp)"
        if key != titleKey {
            titleKey = key
            setText(titleText, lines: [shown], color: .white)
        }
        titleText.position = CGPoint(x: Self.titleX * scale, y: (Self.H - Self.bar) * scale + headerInset)
    }

    private func refreshBadge() {
        if unread == 0 { layoutTitle(badgeWidth: 0) }
        badgeBox.isHidden = unread == 0
        badgeText.isHidden = unread == 0
        guard unread > 0 else { return }
        // The orb has room for one digit and a plus.
        let label = minimised ? (unread > 9 ? "9+" : String(unread)) : (unread > 99 ? "99+" : String(unread))
        let key = "\(label)|\(fp)|\(minimised)|\(badgeLift)"
        guard key != badgeKey else { return }
        badgeKey = key
        setText(badgeText, lines: [label], color: .white)
        // The box is whole art pixels; the text is centred in it on the font grid. In the header it
        // sits left of the buttons; on an orb it overlaps the top right of the ring.
        let width = (badgeText.size.width / scale).rounded(.up) + 2
        layoutTitle(badgeWidth: minimised ? 0 : width)
        let top = minimised ? Self.orb - 1 + badgeLift : Self.H - 1
        badgeBox.size = CGSize(width: width, height: Self.bar - 2)
        badgeBox.position = CGPoint(x: minimised ? Self.orb : Self.badgeRight, y: top - (Self.bar - 2))
        let left = (badgeBox.position.x - width) * scale
        let slack = ((width * scale - badgeText.size.width) / 2 / fp).rounded(.down) * fp
        badgeText.position = CGPoint(x: left + slack + fp, y: (top + 1 - Self.bar) * scale + headerInset)
    }

    /// Characters per line and lines per page. The bubble is at most 36 px of text tall so the
    /// tail can still reach the character's head.
    private var bubbleGrid: (columns: Int, rows: Int) {
        let width = PixelFont.bubbleWidth(atScale: scale, pixel: fp)
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
        let tip = actor.position.x + 8
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

        if still { revealed = Double(lines.reduce(0) { $0 + $1.count }) }
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

        let typing = minimised ? false : advanceBubble(dt)
        // Time-driven props (clock hand, hourglass, the sky) only need a look once a second.
        vitalsClock += dt
        if vitalsClock >= 1, !minimised {
            vitalsClock = 0
            refreshVitals()
        }
        defer {
            // Only draw as often as what is on screen needs: 8 fps typing and the typewriter get 15,
            // the 3 to 5 fps idle poses and ambient loops 10, sleep and the orb 4. A resting window
            // stops once its changes are drawn.
            let speed = art.theme.character.animations[animation]?.fps ?? 3
            let wanted = minimised ? 4 : (typing || speed > 6 ? 15 : (state == .sleeping ? 4 : 10))
            if wanted != fps {
                fps = wanted
                view?.preferredFramesPerSecond = wanted
            }
            if resting {
                if CACurrentMediaTime() > awakeUntil { view?.isPaused = true }
            }
        }

        guard !minimised else { return advanceOrb(dt) }
        chamber.advance(dt, still: still)

        if state == .idle {
            nextFlourish -= dt
            if flourish == nil, nextFlourish <= 0 {
                flourish = Self.flourishes.filter { art.theme.character.animations[$0] != nil }.randomElement()
                nextFlourish = Double.random(in: 6...14)
            }
        } else {
            flourish = nil
        }

        let wanted: String
        switch state {
        case .idle: wanted = flourish ?? "idle_breathe"
        case .thinking: wanted = "think"
        case .working: wanted = staged("type")
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
        guard let def = art.theme.character.animations[animation] else { return }

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
        let textures = art.frames(for: animation, avatar: avatar)
        if frameIndex < textures.count, actor.texture !== textures[frameIndex] {
            actor.texture = textures[frameIndex]
        }
    }

    private func advanceOrb(_ dt: Double) {
        orbNode.advance(dt, still: still)
        orbClock += dt
        let lift: CGFloat = unread > 0 && !still && Int(orbClock * 2) % 2 == 1 ? 1 : 0
        if lift != badgeLift {
            badgeLift = lift
            refreshBadge()
        }
    }
}
