import AppKit
import SpriteKit

/// Mirrors Assets/manifest.json. See docs/ART.md for the art contract.
struct Manifest: Decodable {
    struct Anim: Decodable {
        let row: Int
        let frames: Int
        let fps: Double
        let looping: Bool
    }

    struct Character: Decodable {
        let sheet: String
        let frame: [Int]
        let columns: Int
        let rows: Int
        /// Bottom-centre of the character in canvas pixels, from bottom-left.
        let feet: [CGFloat]
        let animations: [String: Anim]
    }

    struct Room: Decodable {
        let id: String
        let bg: String
        let fg: String
    }

    let character: Character
    let rooms: [Room]
}

/// Loaded once, shared by every window.
final class Art {
    let manifest: Manifest
    private let root: URL
    private var frames: [String: [SKTexture]] = [:]
    private var cache: [String: SKTexture] = [:]

    init() throws {
        guard let dir = Bundle.module.url(forResource: "Assets", withExtension: nil) else {
            throw NSError(domain: "Nook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Assets folder missing from bundle"])
        }
        root = dir
        manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("manifest.json")))

        let c = manifest.character
        let sheet = try texture(c.sheet)
        let (w, h) = (1.0 / CGFloat(c.columns), 1.0 / CGFloat(c.rows))
        for (name, anim) in c.animations {
            frames[name] = (0..<anim.frames).map { col in
                // Texture rects are unit coordinates with a bottom-left origin; rows count from the top.
                let rect = CGRect(x: CGFloat(col) * w, y: 1.0 - CGFloat(anim.row + 1) * h, width: w, height: h)
                let t = SKTexture(rect: rect, in: sheet)
                t.filteringMode = .nearest
                return t
            }
        }
    }

    func texture(_ path: String) throws -> SKTexture {
        if let t = cache[path] { return t }
        let url = root.appendingPathComponent(path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "Nook", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(path)"])
        }
        let t = SKTexture(cgImage: image)
        t.filteringMode = .nearest
        cache[path] = t
        return t
    }

    func frames(for animation: String) -> [SKTexture] {
        frames[animation] ?? frames["idle_breathe"] ?? []
    }
}
