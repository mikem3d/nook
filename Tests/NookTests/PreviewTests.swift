import XCTest
import SpriteKit
import Metal
@testable import Nook

/// Renders the real RoomScene offscreen so the theme can be judged without launching the app:
///   NOOK_PREVIEW=/some/folder swift test --filter PreviewTests
/// Writes every scene, stacked and side-by-side pairs with their connectors open, a sealed chamber,
/// a dimmed one, and the orb in every state, at 1x, 1.5x and 2x.
final class PreviewTests: XCTestCase {
    private static let long = "The configurator pricing table is out of date. Want me to refresh it? I can also regenerate the PDF, update the changelog and open a pull request once the tests are green."

    func testRenderTheme() throws {
        guard let folder = ProcessInfo.processInfo.environment["NOOK_PREVIEW"] else { throw XCTSkip("set NOOK_PREVIEW to a folder") }
        let out = URL(fileURLWithPath: folder)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let renderer = try OffscreenRenderer()
        let art = try Art()
        PixelFont.register(art.url("fonts/DepartureMono-Regular.otf"))
        XCTAssertTrue(PixelFont.shared.pixelated, "the bundled font registered")

        func chamber(_ index: Int, _ scale: CGFloat, edges: Set<RoomScene.Edge> = [], state: AgentState = .working, bubble: String = "",
                     unread: Int = 0, folder: String? = nil, context: Double = 0.4, started: Date? = Date().addingTimeInterval(-3)) -> RoomScene {
            let scene = RoomScene(art: art, roomIndex: index, title: folder ?? art.scene(at: index).id, avatarSeed: folder)
            scene.scaleMode = .fill // resizeFill needs a view; offscreen it collapses the scene to nothing
            scene.size = CGSize(width: RoomScene.W * scale, height: RoomScene.H * scale)
            scene.configure(scale: scale, minimised: false)
            scene.setNeighbours(edges)
            scene.show(state: state, bubble: bubble, unread: unread)
            scene.showVitals(contextFraction: context, cost: 1.8, changedFiles: 3, turnStarted: started)
            return scene
        }

        // Every scene on its own, sealed, with a different dwarf in each.
        for (index, choice) in art.sceneChoices.enumerated() {
            let scene = chamber(index, 2, folder: "/Users/someone/work/project-\(index)")
            try renderer.write(renderer.image(of: scene, seconds: 1.4), to: out.appendingPathComponent("scene-\(choice.id)-2x.png"))
        }

        for scale in [1, 1.5, 2] as [CGFloat] {
            let tag = "\(scale)x".replacingOccurrences(of: ".0x", with: "x")
            // A stack of three: ladders line up through the seams.
            let column = [chamber(0, scale, edges: [.bottom], state: .talking, bubble: Self.long, unread: 2, folder: "/a"),
                          chamber(1, scale, edges: [.top, .bottom], folder: "/b"),
                          chamber(4, scale, edges: [.top], state: .thinking, folder: "/c")]
            try renderer.write(renderer.stitch(column.map { try renderer.image(of: $0, seconds: 2) }, vertical: true),
                               to: out.appendingPathComponent("stack-vertical-\(tag).png"))
            // A row of two: the tunnel lines up.
            let row = [chamber(3, scale, edges: [.right], state: .idle, folder: "/d"),
                       chamber(5, scale, edges: [.left], state: .alert, bubble: "Allow Bash? rm -rf build/", unread: 120, folder: "/e", context: 0.93,
                               started: Date().addingTimeInterval(-400))]
            try renderer.write(renderer.stitch(row.map { try renderer.image(of: $0, seconds: 2) }, vertical: false),
                               to: out.appendingPathComponent("stack-horizontal-\(tag).png"))

            let sealed = chamber(6, scale, state: .sleeping, folder: "a-very-long-project-folder-name-indeed", started: nil)
            sealed.setDimmed(true)
            try renderer.write(renderer.image(of: sealed, seconds: 1), to: out.appendingPathComponent("sealed-dimmed-\(tag).png"))

            // The orb in every state, side by side; the last two carry an unread badge.
            let states: [AgentState] = [.idle, .thinking, .working, .talking, .alert, .done, .sleeping]
            let orbs = try states.enumerated().map { index, state -> CGImage in
                let scene = RoomScene(art: art, roomIndex: index, title: "orb", avatarSeed: "/agents/\(index)")
                scene.scaleMode = .fill
                scene.size = CGSize(width: RoomScene.orb * scale, height: RoomScene.orb * scale)
                scene.configure(scale: scale, minimised: true)
                scene.show(state: state, bubble: "hidden in an orb", unread: index == 4 ? 3 : (index == 6 ? 12 : 0))
                let image = try renderer.image(of: scene, seconds: 0.2)
                if index == 0 {
                    XCTAssertEqual(OffscreenRenderer.alpha(of: image, x: 0, y: 0), 0, "outside the circle is transparent")
                    XCTAssertEqual(OffscreenRenderer.alpha(of: image, x: image.width / 2, y: image.height / 2), 255)
                }
                return image
            }
            try renderer.write(renderer.stitch(orbs, vertical: false, gap: 8), to: out.appendingPathComponent("orbs-\(tag).png"))
        }

        // Hotspots: idle and empty, hovered, and full with news, the auto marker and the widest bubble over them.
        for (index, choice) in art.sceneChoices.enumerated() {
            let idle = chamber(index, 2, state: .idle, folder: "/h/\(index)", started: nil)
            idle.showHotspot("calendar", HotspotState(number: 7))
            let hover = chamber(index, 2, state: .idle, folder: "/h/\(index)", started: nil)
            hover.showHotspot("tasks", HotspotState(level: 2))
            hover.showHotspot("calendar", HotspotState(number: 21))
            hover.setHover(index % 2 == 0 ? "tasks" : "calendar")
            let news = chamber(index, 2, edges: [.top, .left, .right], state: .talking, bubble: Self.long, folder: "/h/\(index)")
            news.showHotspot("tasks", HotspotState(level: 9, news: true))
            news.showHotspot("calendar", HotspotState(news: true, number: 30))
            news.setAutomation(true)
            try renderer.write(renderer.stitch([idle, hover, news].map { try renderer.image(of: $0, seconds: 2) }, vertical: false, gap: 8),
                               to: out.appendingPathComponent("hotspots-\(choice.id)-2x.png"))
        }
        for scale in [1, 1.5] as [CGFloat] {
            let small = chamber(0, scale, state: .idle, folder: "/h/0", started: nil)
            small.showHotspot("tasks", HotspotState(level: 3, news: true))
            small.showHotspot("calendar", HotspotState(news: true, number: 21))
            small.setHover("calendar")
            small.setAutomation(true)
            try renderer.write(renderer.image(of: small, seconds: 1), to: out.appendingPathComponent("hotspots-workshop-\(scale)x.png"))
        }

        // Halfway through a scene change.
        let switching = chamber(0, 2, folder: "/a")
        _ = try renderer.image(of: switching, seconds: 0.5)
        switching.setScene("treasury")
        XCTAssertEqual(switching.sceneID, "treasury")
        try renderer.write(renderer.image(of: switching, seconds: 0.12), to: out.appendingPathComponent("scene-switch-midway-2x.png"))
    }
}
