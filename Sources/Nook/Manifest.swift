import AppKit
import SpriteKit

/// Mirrors Assets/manifest.json: which folder under Assets/themes to use.
struct Manifest: Decodable {
    let theme: String
}

/// The current theme's art. Loaded once, shared by every window.
final class Art {
    let theme: Theme
    private let assets: URL
    /// The current theme's folder; every theme path is relative to it.
    let root: URL
    private var cache: [String: SKTexture] = [:]
    private var sheets: [Int: SKTexture] = [:]
    private var frames: [Int: [String: [SKTexture]]] = [:]
    private var portraits: [Int: [SKTexture]] = [:]

    convenience init() throws {
        // In Nook.app the SwiftPM resource bundle sits in Contents/Resources (scripts/bundle.sh);
        // SwiftPM's own `Bundle.module` only looks beside the executable's bundle root, where
        // code signing forbids it, and then at the absolute build path, which exists only here.
        let packaged = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("Nook_Nook.bundle")) }
        guard let dir = (packaged ?? Bundle.module).url(forResource: "Assets", withExtension: nil) else {
            throw NSError(domain: "Nook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Assets folder missing from bundle"])
        }
        try self.init(assets: dir)
    }

    /// `assets` is a folder laid out like Sources/Nook/Assets. If the manifest is missing or names a
    /// theme that will not load, the first theme that does load is used.
    init(assets: URL) throws {
        self.assets = assets
        let themes = assets.appendingPathComponent("themes")
        let named = (try? Data(contentsOf: assets.appendingPathComponent("manifest.json")))
            .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }?.theme
        let others = ((try? FileManager.default.contentsOfDirectory(atPath: themes.path)) ?? []).sorted()
        let usable = ([named].compactMap { $0 } + others).lazy.compactMap { id -> (Theme, URL)? in
            let folder = themes.appendingPathComponent(id)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("theme.json")),
                  let theme = try? JSONDecoder().decode(Theme.self, from: data), !theme.scenes.isEmpty else { return nil }
            return (theme, folder)
        }.first
        guard let usable else {
            throw NSError(domain: "Nook", code: 3, userInfo: [NSLocalizedDescriptionKey: "No usable theme in \(themes.path)"])
        }
        (theme, root) = usable
    }

    // MARK: scenes and avatars

    /// Scenes the user can pick for a window, in menu order. Contract: ids are stable and persisted.
    var sceneChoices: [(id: String, name: String)] { theme.scenes.map { ($0.id, $0.name) } }

    func scene(_ id: String) -> Theme.Scene? { theme.scenes.first { $0.id == id } }

    /// New agents take scenes round-robin, so a fresh stack looks varied.
    func scene(at index: Int) -> Theme.Scene { theme.scenes[((index % theme.scenes.count) + theme.scenes.count) % theme.scenes.count] }

    var avatarCount: Int { max(theme.avatars?.count ?? 0, 1) }

    /// The same seed (the agent's folder path) gives the same dwarf on every launch. FNV-1a,
    /// because `String.hashValue` changes from run to run.
    func avatarIndex(for seed: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return Int(hash % UInt64(avatarCount))
    }

    // MARK: textures

    /// A file of the current theme.
    func texture(_ path: String) throws -> SKTexture {
        if let t = cache[path] { return t }
        guard let image = image(path) else {
            throw NSError(domain: "Nook", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(path)"])
        }
        let t = Self.pixelTexture(image)
        cache[path] = t
        return t
    }

    /// Where a bundled file outside the themes lives (fonts and the like).
    func url(_ path: String) -> URL { assets.appendingPathComponent(path) }

    /// `count` equal frames side by side, left to right.
    func strip(_ sheet: SKTexture, count: Int) -> [SKTexture] {
        let w = 1.0 / CGFloat(max(count, 1))
        return (0..<max(count, 0)).map { i in
            let t = SKTexture(rect: CGRect(x: CGFloat(i) * w, y: 0, width: w, height: 1), in: sheet)
            t.filteringMode = .nearest
            return t
        }
    }

    /// One texture per state, or nil when the prop is not declared or its sheet will not load.
    /// `sheet` overrides the theme's artwork with a scene's own dressing of the same prop.
    func states(forProp name: String, sheet override: String? = nil) -> (prop: Theme.Prop, textures: [SKTexture])? {
        guard let prop = theme.props?.first(where: { $0.name == name }), prop.states > 0, prop.frame.count == 2,
              prop.position.count == 2, let sheet = try? texture(override ?? prop.sheet) else { return nil }
        return (prop, strip(sheet, count: prop.states))
    }

    /// Frames of an animation for one avatar; an unknown name falls back to breathing.
    func frames(for animation: String, avatar: Int = 0) -> [SKTexture] {
        let all = frames[avatar] ?? cut(avatar)
        return all[animation] ?? all["idle_breathe"] ?? []
    }

    /// One head per portrait frame for the orb. Without a portrait sheet, the head of the first
    /// character frame stands in for every state.
    func portrait(state: AgentState, avatar: Int = 0) -> SKTexture? {
        let heads = portraits[avatar] ?? cutPortraits(avatar)
        guard !heads.isEmpty else { return nil }
        let index = theme.portrait?.states[state.rawValue] ?? 0
        return heads[min(max(index, 0), heads.count - 1)]
    }

    private func image(_ path: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(root.appendingPathComponent(path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func pixelTexture(_ image: CGImage) -> SKTexture {
        let t = SKTexture(cgImage: image)
        t.filteringMode = .nearest
        return t
    }

    /// The file as it is for avatar 0 or an unknown avatar, recoloured otherwise.
    private func recoloured(_ path: String, avatar: Int) -> SKTexture? {
        guard let image = image(path) else { return nil }
        let swap = theme.avatars.flatMap { $0.indices.contains(avatar) ? $0[avatar].swap : nil } ?? [:]
        return Self.pixelTexture(PaletteSwap.apply(image, table: PaletteSwap.table(swap)) ?? image)
    }

    private func cut(_ avatar: Int) -> [String: [SKTexture]] {
        var result: [String: [SKTexture]] = [:]
        let c = theme.character
        if let sheet = sheets[avatar] ?? recoloured(c.sheet, avatar: avatar), c.columns > 0, c.rows > 0 {
            sheets[avatar] = sheet
            let (w, h) = (1.0 / CGFloat(c.columns), 1.0 / CGFloat(c.rows))
            for (name, anim) in c.animations where anim.row < c.rows {
                result[name] = (0..<min(anim.frames, c.columns)).map { col in
                    // Texture rects are unit coordinates with a bottom-left origin; rows count from the top.
                    let t = SKTexture(rect: CGRect(x: CGFloat(col) * w, y: 1.0 - CGFloat(anim.row + 1) * h, width: w, height: h), in: sheet)
                    t.filteringMode = .nearest
                    return t
                }
            }
        }
        frames[avatar] = result
        return result
    }

    private func cutPortraits(_ avatar: Int) -> [SKTexture] {
        var heads: [SKTexture] = []
        if let p = theme.portrait, let sheet = recoloured(p.sheet, avatar: avatar) {
            heads = strip(sheet, count: max((p.states.values.max() ?? 0) + 1, 1))
        } else if let sheet = sheets[avatar] ?? recoloured(theme.character.sheet, avatar: avatar) {
            // Top of the first frame of row 0: the head, roughly.
            let c = theme.character
            let (w, h) = (1.0 / CGFloat(max(c.columns, 1)), 1.0 / CGFloat(max(c.rows, 1)))
            let head = SKTexture(rect: CGRect(x: w * 0.19, y: 1 - h * 0.69, width: w * 0.62, height: h * 0.62), in: sheet)
            head.filteringMode = .nearest
            heads = [head]
        }
        portraits[avatar] = heads
        return heads
    }
}
