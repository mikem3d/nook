import XCTest
import SpriteKit
@testable import Nook

final class ThemeTests: XCTestCase {
    private static let edges = ["top", "bottom", "left", "right"]

    // MARK: the bundled theme

    func testBundledThemeLoadsWithEveryPieceItDeclares() throws {
        let art = try Art()
        let theme = art.theme
        XCTAssertGreaterThanOrEqual(theme.scenes.count, 8)
        XCTAssertEqual(Set(art.sceneChoices.map(\.id)).count, theme.scenes.count, "scene ids are unique")
        for id in ["workshop", "forge", "bakery", "distillery", "lab", "treasury", "mushrooms", "quarters"] {
            XCTAssertNotNil(art.scene(id), id)
        }
        for scene in theme.scenes {
            XCTAssertNoThrow(try art.texture(scene.bg), scene.id)
            XCTAssertNoThrow(try art.texture(scene.fg), scene.id)
            XCTAssertEqual(try art.texture(scene.bg).size(), CGSize(width: RoomScene.W, height: RoomScene.H))
            for ambient in scene.ambient ?? [] {
                let sheet = try art.texture(ambient.sheet)
                XCTAssertEqual(sheet.size(), CGSize(width: ambient.frame[0] * ambient.frames, height: ambient.frame[1]), "\(scene.id)/\(ambient.name)")
                XCTAssertLessThanOrEqual(ambient.fps, 6, "ambient loops must not raise the frame rate")
            }
            for (_, replacement) in scene.animations ?? [:] {
                XCTAssertNotNil(theme.character.animations[replacement], "\(scene.id) asks for \(replacement)")
            }
        }
        for name in ["idle_breathe", "idle_sip", "idle_stretch", "idle_read", "idle_look", "think", "type", "talk", "alert", "celebrate", "sleep"] {
            let anim = try XCTUnwrap(theme.character.animations[name], name)
            XCTAssertEqual(art.frames(for: name).count, anim.frames)
        }
        let portrait = try XCTUnwrap(theme.portrait)
        for state in [AgentState.idle, .thinking, .working, .talking, .alert, .done, .sleeping] {
            XCTAssertNotNil(portrait.states[state.rawValue], state.rawValue)
            XCTAssertEqual(art.portrait(state: state)?.size(), CGSize(width: 20, height: 20))
        }
        let connectors = try XCTUnwrap(theme.frame?.connectors)
        for edge in Self.edges {
            XCTAssertNoThrow(try art.texture(try XCTUnwrap(connectors[edge]?.open).sprite), edge)
            XCTAssertNoThrow(try art.texture(try XCTUnwrap(connectors[edge]?.sealed).sprite), edge)
        }
        XCTAssertEqual(try art.texture(try XCTUnwrap(theme.orb?.ring)).size(), CGSize(width: RoomScene.orb, height: RoomScene.orb))
    }

    func testNewAgentsTakeScenesRoundRobin() throws {
        let art = try Art()
        let count = art.sceneChoices.count
        XCTAssertEqual((0..<count).map { art.scene(at: $0).id }, art.sceneChoices.map(\.id))
        XCTAssertEqual(art.scene(at: count).id, art.scene(at: 0).id)
        XCTAssertEqual(RoomScene(art: art, roomIndex: 1, title: "x").sceneID, art.sceneChoices[1].id)
    }

    // MARK: connectors line up across a seam

    /// Windows in a stack abut with no gap and any scene can sit next to any other, so what crosses
    /// the seam is fixed by the theme: the last row of the lower edge's piece must match the first
    /// row of the upper edge's piece at the same canvas x, and likewise for the side columns.
    func testConnectorsAlignAcrossSeams() throws {
        let art = try Art()
        let (theme, root) = (art.theme, art.root)
        let connectors = try XCTUnwrap(theme.frame?.connectors)
        func load(_ piece: Theme.Piece?) throws -> Bitmap { try Bitmap(url: root.appendingPathComponent(try XCTUnwrap(piece).sprite)) }

        let (top, bottom) = (try XCTUnwrap(connectors["top"]?.open), try XCTUnwrap(connectors["bottom"]?.open))
        let (up, down) = (try load(top), try load(bottom))
        XCTAssertEqual(top.position[0], bottom.position[0], "ladder shaft x")
        XCTAssertEqual(up.width, down.width, "ladder shaft width")
        XCTAssertEqual(top.position[1] + CGFloat(up.height), RoomScene.H, "the ladder reaches the top edge")
        XCTAssertEqual(bottom.position[1], 0, "the ladder reaches the bottom edge")
        XCTAssertEqual(up.row(0), down.row(down.height - 1), "pixels either side of a horizontal seam")
        XCTAssertTrue(up.row(0).allSatisfy { $0 >> 24 == 255 }, "the shaft is solid where it crosses the seam")

        let (left, right) = (try XCTUnwrap(connectors["left"]?.open), try XCTUnwrap(connectors["right"]?.open))
        let (west, east) = (try load(left), try load(right))
        XCTAssertEqual(left.position[0], 0)
        XCTAssertEqual(right.position[0] + CGFloat(east.width), RoomScene.W)
        XCTAssertEqual(left.position[1], right.position[1], "tunnel mouth y")
        XCTAssertEqual(west.height, east.height, "tunnel mouth height")
        XCTAssertEqual(west.column(0), east.column(east.width - 1), "pixels either side of a vertical seam")

        // Sealed pieces sit on the same footprint sideways, so a wall never jumps when a neighbour arrives.
        for edge in ["left", "right"] {
            let (open, sealed) = (try XCTUnwrap(connectors[edge]?.open), try XCTUnwrap(connectors[edge]?.sealed))
            XCTAssertEqual(open.position, sealed.position, edge)
        }
    }

    func testNeighboursOpenAndSealTheRightPieces() throws {
        let art = try Art()
        let scene = RoomScene(art: art, roomIndex: 0, title: "a")
        let connectors = try XCTUnwrap(art.theme.frame?.connectors)
        func shown(_ piece: Theme.Piece?) throws -> Bool {
            let texture = try art.texture(try XCTUnwrap(piece).sprite)
            let sprite = try XCTUnwrap(Self.sprites(in: scene).first { $0.texture === texture })
            return !sprite.isHidden
        }
        for edge in Self.edges {
            XCTAssertFalse(try shown(connectors[edge]?.open), "\(edge) starts sealed")
            XCTAssertTrue(try shown(connectors[edge]?.sealed))
        }
        scene.setNeighbours([.top, .right])
        XCTAssertTrue(try shown(connectors["top"]?.open))
        XCTAssertFalse(try shown(connectors["top"]?.sealed))
        XCTAssertTrue(try shown(connectors["right"]?.open))
        XCTAssertFalse(try shown(connectors["bottom"]?.open))
        scene.setNeighbours([])
        XCTAssertFalse(try shown(connectors["top"]?.open))
    }

    // MARK: scenes

    func testSceneSwitching() throws {
        let art = try Art()
        let scene = RoomScene(art: art, roomIndex: 0, title: "a")
        scene.showVitals(contextFraction: 0.5, cost: 1, changedFiles: 2, turnStarted: nil)
        XCTAssertEqual(scene.sceneID, "workshop")
        scene.setScene("no-such-scene")
        XCTAssertEqual(scene.sceneID, "workshop", "an unknown id is ignored")

        scene.setScene("forge")
        XCTAssertEqual(scene.sceneID, "forge")
        let chambers = Self.nodes(in: scene).compactMap { $0 as? ChamberNode }
        XCTAssertEqual(chambers.count, 2, "the old chamber stays for the crossfade")
        let forge = try XCTUnwrap(chambers.first { $0.spec.id == "forge" })
        XCTAssertFalse(forge.set("papers", 2), "the new chamber already shows the current vitals")
        XCTAssertEqual(art.scene("forge")?.animations?["type"], "hammer")

        // An orb has nothing to fade: the chamber is simply replaced.
        scene.configure(scale: 2, minimised: true)
        scene.setScene("lab")
        XCTAssertEqual(Self.nodes(in: scene).compactMap { $0 as? ChamberNode }.filter { $0.spec.id == "lab" }.count, 1)
        XCTAssertEqual(Self.nodes(in: scene).compactMap { $0 as? ChamberNode }.filter { $0.spec.id == "forge" }.count, 0)
    }

    // MARK: avatars

    func testAvatarAssignmentIsDeterministicAndVaried() throws {
        let art = try Art()
        XCTAssertGreaterThanOrEqual(art.avatarCount, 4)
        let folders = (0..<40).map { "/Users/someone/work/project-\($0)" }
        let picks = folders.map(art.avatarIndex(for:))
        XCTAssertEqual(picks, folders.map(art.avatarIndex(for:)), "the same folder always gets the same dwarf")
        XCTAssertEqual(art.avatarIndex(for: "/Users/zheriam/work/zipdemand"), try Art().avatarIndex(for: "/Users/zheriam/work/zipdemand"))
        XCTAssertTrue(picks.allSatisfy { (0..<art.avatarCount).contains($0) })
        XCTAssertEqual(Set(picks).count, art.avatarCount, "forty folders reach every variant")
        // FNV-1a of "a", so a change of hash function (which would reshuffle everyone's dwarf) is caught.
        XCTAssertEqual(art.avatarIndex(for: "a"), Int(UInt64(0xaf63dc4c8601ec8c) % UInt64(art.avatarCount)))
    }

    func testPaletteSwapRecoloursOnlyTheKeyColours() throws {
        let art = try Art()
        let theme = art.theme
        let sheet = try Bitmap(url: art.root.appendingPathComponent(theme.character.sheet))
        let avatars = try XCTUnwrap(theme.avatars)
        XCTAssertTrue(avatars[0].swap.isEmpty, "the first avatar is the sheet as drawn")
        for avatar in avatars.dropFirst() {
            let table = PaletteSwap.table(avatar.swap)
            XCTAssertEqual(table.count, avatar.swap.count, "\(avatar.id): every entry parses")
            let swapped = Bitmap(image: try XCTUnwrap(PaletteSwap.apply(sheet.image, table: table)))
            var changed = 0
            for (before, after) in zip(sheet.pixels, swapped.pixels) {
                let expected = before >> 24 == 255 ? (table[before & 0xFFFFFF].map { $0 | 0xFF00_0000 } ?? before) : before
                XCTAssertEqual(after, expected)
                if after != before { changed += 1 }
            }
            XCTAssertGreaterThan(changed, 500, "\(avatar.id) visibly differs")
            let palette = Set((theme.palette ?? []).compactMap(PaletteSwap.key))
            XCTAssertTrue(table.values.allSatisfy(palette.contains), "\(avatar.id) stays inside the shared palette")
        }
    }

    // MARK: missing assets

    func testMissingAssetsDegradeGracefully() throws {
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent("nook-theme-\(UUID().uuidString)")
        let folder = assets.appendingPathComponent("themes/bare")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: assets) }
        XCTAssertThrowsError(try Art(assets: assets), "no theme at all")

        // A theme with nothing but a character entry and one scene, and not a single PNG on disk.
        let json = """
        {"id": "bare", "name": "Bare",
         "character": {"sheet": "c.png", "frame": [32, 32], "columns": 8, "rows": 1, "feet": [84, 26], "animations": {}},
         "scenes": [{"id": "only", "name": "Only", "bg": "bg.png", "fg": "fg.png", "animations": {"type": "nope"},
                     "props": [{"name": "clock", "position": [1, 2]}]}]}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("theme.json"))
        // The root manifest names a theme that is not there: the first usable one is taken.
        try Data(#"{"theme": "gone"}"#.utf8).write(to: assets.appendingPathComponent("manifest.json"))
        let art = try Art(assets: assets)
        XCTAssertEqual(art.theme.id, "bare")
        XCTAssertEqual(art.avatarCount, 1)
        XCTAssertEqual(art.avatarIndex(for: "anything"), 0)
        XCTAssertTrue(art.frames(for: "type").isEmpty)
        XCTAssertNil(art.portrait(state: .alert))
        XCTAssertNil(art.states(forProp: "clock"))

        let scene = RoomScene(art: art, roomIndex: 5, title: "bare")
        XCTAssertEqual(scene.sceneID, "only")
        scene.setNeighbours([.top, .bottom, .left, .right])
        scene.show(state: .working, bubble: "still talks", unread: 3)
        scene.showVitals(contextFraction: 0.9, cost: 3, changedFiles: 4, turnStarted: Date())
        scene.configure(scale: 1.5, minimised: true)
        scene.setDimmed(true)
        for frame in 0..<20 { scene.update(Double(frame) / 10) }
        scene.configure(scale: 1.5, minimised: false)
        for frame in 20..<40 { scene.update(Double(frame) / 10) }
        let background = try XCTUnwrap(Self.nodes(in: scene).compactMap { $0 as? ChamberNode }.first?.children.first as? SKSpriteNode)
        XCTAssertNil(background.texture)
        XCTAssertEqual(background.size, CGSize(width: RoomScene.W, height: RoomScene.H), "a flat fill stands in for the missing background")
    }

    func testOrbShowsOnlyThePortraitAndKeepsMovingWhileItMatters() throws {
        let art = try Art()
        let scene = RoomScene(art: art, roomIndex: 0, title: "a")
        scene.configure(scale: 2, minimised: true)
        let orb = try XCTUnwrap(Self.nodes(in: scene).compactMap { $0 as? OrbNode }.first)
        XCTAssertFalse(orb.isHidden)
        XCTAssertTrue(try XCTUnwrap(Self.nodes(in: scene).compactMap { $0 as? ChamberNode }.first?.parent).isHidden, "the chamber is not drawn")
        scene.show(state: .idle, bubble: "", unread: 0)
        XCTAssertFalse(orb.animates)
        scene.show(state: .alert, bubble: "", unread: 0)
        XCTAssertTrue(orb.animates)
        scene.show(state: .working, bubble: "", unread: 0)
        XCTAssertTrue(orb.animates)
        scene.configure(scale: 2, minimised: false)
        XCTAssertTrue(orb.isHidden)
    }

    func testHeaderHitAreasMatchTheContract() {
        XCTAssertEqual(RoomScene.closeHit, 12)
        XCTAssertEqual(RoomScene.minimiseHit, 24)
        XCTAssertEqual(RoomScene.orb, 28)
    }

    // MARK: helpers

    private static func nodes(in node: SKNode) -> [SKNode] { node.children.flatMap { [$0] + nodes(in: $0) } }
    private static func sprites(in node: SKNode) -> [SKSpriteNode] { nodes(in: node).compactMap { $0 as? SKSpriteNode } }
}

/// An image as 0xAARRGGBB pixels, rows top to bottom.
struct Bitmap {
    let image: CGImage
    let width: Int
    let height: Int
    let pixels: [UInt32]

    init(url: URL) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), url.path)
        self.init(image: try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
    }

    init(image: CGImage) {
        self.image = image
        (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = stride(from: 0, to: bytes.count, by: 4).map { i -> UInt32 in
            let (a, r, g, b) = (UInt32(bytes[i + 3]), UInt32(bytes[i]), UInt32(bytes[i + 1]), UInt32(bytes[i + 2]))
            return a << 24 | r << 16 | g << 8 | b
        }
    }

    func row(_ y: Int) -> [UInt32] { Array(pixels[y * width..<(y + 1) * width]) }
    func column(_ x: Int) -> [UInt32] { (0..<height).map { pixels[$0 * width + x] } }
}
