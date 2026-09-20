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

    /// A small sprite that shows one vital sign. Its sheet holds `states` frames side by side, left to right.
    struct Prop: Decodable {
        let name: String
        let sheet: String
        let frame: [Int]
        let states: Int
        /// Bottom-left of the prop in canvas pixels, from the canvas bottom-left.
        let position: [CGFloat]
        /// Draw order: the background is 0, the character 1, the foreground 2.
        let z: CGFloat
    }

    let character: Character
    let rooms: [Room]
    /// Optional: a manifest without props, or missing some of them, still gives a working room.
    let props: [Prop]?
}

/// Loaded once, shared by every window.
final class Art {
    let manifest: Manifest
    private let root: URL
    private var frames: [String: [SKTexture]] = [:]
    private var cache: [String: SKTexture] = [:]

    init() throws {
        // In Nook.app the SwiftPM resource bundle sits in Contents/Resources (scripts/bundle.sh);
        // SwiftPM's own `Bundle.module` only looks beside the executable's bundle root, where
        // code signing forbids it, and then at the absolute build path, which exists only here.
        let packaged = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Nook_Nook.bundle")) }
        guard let dir = (packaged ?? Bundle.module).url(forResource: "Assets", withExtension: nil) else {
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

    /// Where a bundled file lives (fonts and the like).
    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    /// One texture per state, or nil when the prop is not declared or its sheet will not load.
    func states(forProp name: String) -> (prop: Manifest.Prop, textures: [SKTexture])? {
        guard let prop = manifest.props?.first(where: { $0.name == name }), prop.states > 0, prop.frame.count == 2,
              prop.position.count == 2, let sheet = try? texture(prop.sheet) else { return nil }
        let w = 1.0 / CGFloat(prop.states)
        let textures = (0..<prop.states).map { i -> SKTexture in
            let t = SKTexture(rect: CGRect(x: CGFloat(i) * w, y: 0, width: w, height: 1), in: sheet)
            t.filteringMode = .nearest
            return t
        }
        return (prop, textures)
    }

    func frames(for animation: String) -> [SKTexture] {
        frames[animation] ?? frames["idle_breathe"] ?? []
    }
}
