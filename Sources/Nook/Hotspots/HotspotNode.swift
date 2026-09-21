import SpriteKit

/// One clickable prop in a chamber: a level, a hover highlight, a news marker and an optional number.
final class HotspotNode: SKNode {
    let area: HotspotArea
    private let sprite: SKSpriteNode
    private let idle: [SKTexture]
    private let hover: [SKTexture]
    private var news: SKSpriteNode?
    private var digits: [SKSpriteNode] = []
    private var glyphs: [SKTexture] = []
    private var state = HotspotState()
    private var digitOrigin = CGPoint.zero
    private var digitWidth: CGFloat = 0

    /// nil when the sheet will not load or the declaration makes no sense.
    init?(art: Art, spec: Theme.Hotspot, position: [CGFloat], z: CGFloat) {
        guard spec.frame.count == 2, position.count == 2, spec.levels > 0, let sheet = try? art.texture(spec.sheet) else { return nil }
        let size = CGSize(width: spec.frame[0], height: spec.frame[1])
        let w = 1 / CGFloat(spec.levels)
        // Texture rects have a bottom-left origin: the idle row is the upper half of the sheet.
        func row(_ y: CGFloat) -> [SKTexture] {
            (0..<spec.levels).map { level in
                let t = SKTexture(rect: CGRect(x: CGFloat(level) * w, y: y, width: w, height: 0.5), in: sheet)
                t.filteringMode = .nearest
                return t
            }
        }
        (idle, hover) = (row(0.5), row(0))
        sprite = SKSpriteNode(texture: idle[0], size: size)
        sprite.anchorPoint = .zero
        let hit = spec.hit.flatMap { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil } ?? CGRect(origin: .zero, size: size)
        area = HotspotArea(id: spec.id, name: spec.name, rect: hit.offsetBy(dx: position[0], dy: position[1]))
        super.init()
        self.position = CGPoint(x: position[0], y: position[1])
        zPosition = z
        addChild(sprite)

        if let piece = spec.news, piece.position.count == 2, let texture = try? art.texture(piece.sprite) {
            let mark = SKSpriteNode(texture: texture, size: texture.size())
            mark.anchorPoint = .zero
            mark.position = CGPoint(x: piece.position[0], y: piece.position[1])
            mark.zPosition = 0.02
            mark.isHidden = true
            addChild(mark)
            news = mark
        }
        if let d = spec.digits, d.frame.count == 2, d.position.count == 2, let texture = try? art.texture(d.sheet) {
            glyphs = art.strip(texture, count: 10)
            digitOrigin = CGPoint(x: d.position[0], y: d.position[1])
            digitWidth = CGFloat(d.frame[0])
            digits = (0..<2).map { _ in
                let digit = SKSpriteNode(texture: nil, size: CGSize(width: d.frame[0], height: d.frame[1]))
                digit.anchorPoint = .zero
                digit.zPosition = 0.01
                digit.isHidden = true
                addChild(digit)
                return digit
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var hovered = false {
        didSet { if hovered != oldValue { refreshTexture() } }
    }

    /// Returns true if that changed what is drawn.
    @discardableResult
    func show(_ new: HotspotState) -> Bool {
        guard new != state else { return false }
        state = new
        refreshTexture()
        news?.isHidden = !new.news
        // One or two digits, centred in the two-digit box with a pixel between them.
        let text = new.number.map { Array(String(min(max($0, 0), 99))).compactMap(\.wholeNumberValue) } ?? []
        let inset = text.count == 1 ? ((digitWidth + 1) / 2).rounded(.down) : 0
        for (i, digit) in digits.enumerated() {
            digit.isHidden = i >= text.count
            guard i < text.count else { continue }
            digit.texture = glyphs[text[i]]
            digit.position = CGPoint(x: digitOrigin.x + inset + CGFloat(i) * (digitWidth + 1), y: digitOrigin.y)
        }
        return true
    }

    private func refreshTexture() {
        let level = min(max(state.level, 0), idle.count - 1)
        sprite.texture = (hovered ? hover : idle)[level]
    }
}
