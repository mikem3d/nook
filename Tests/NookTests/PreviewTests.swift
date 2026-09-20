import XCTest
import SpriteKit
import Metal
@testable import Nook

/// Renders the real RoomScene offscreen so the room can be checked without launching the app:
///   NOOK_PREVIEW=/some/folder swift test --filter PreviewTests
final class PreviewTests: XCTestCase {
    func testRenderRooms() throws {
        guard let folder = ProcessInfo.processInfo.environment["NOOK_PREVIEW"] else { throw XCTSkip("set NOOK_PREVIEW to a folder") }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw XCTSkip("no Metal device") }
        let art = try Art()
        PixelFont.register(art.url("fonts/DepartureMono-Regular.otf"))
        XCTAssertTrue(PixelFont.shared.pixelated, "the bundled font registered")

        let long = "The configurator pricing table is out of date. Want me to refresh it? I can also regenerate the PDF, update the changelog and open a pull request once the tests are green."
        let cases: [(String, CGFloat, String, Double, Double, Int, Date?, Int)] = [
            ("2x-talking", 2, long, 0.62, 1.8, 3, Date().addingTimeInterval(-42), 2),
            ("2x-full", 2, "Allow Bash? rm -rf build/", 0.93, 25, 9, Date().addingTimeInterval(-400), 120),
            ("1.5x-talking", 1.5, long, 0.3, 0.2, 1, nil, 0),
            ("1x-idle", 1, "", 0, 0, 0, nil, 7),
        ]
        for (index, (name, s, text, context, cost, files, started, unread)) in cases.enumerated() {
            let scene = RoomScene(art: art, roomIndex: index, title: index == 1 ? "a-very-long-project-folder-name-indeed" : "zipdemand")
            scene.scaleMode = .fill // resizeFill needs a view; offscreen it collapses the scene to nothing
            scene.size = CGSize(width: RoomScene.W * s, height: RoomScene.H * s)
            scene.configure(scale: s, minimised: false)
            scene.show(state: text.isEmpty ? .idle : .talking, bubble: text, unread: unread)
            scene.showVitals(contextFraction: context, cost: cost, changedFiles: files, turnStarted: started)

            let renderer = SKRenderer(device: device)
            renderer.scene = scene
            let (w, h) = (Int(scene.size.width * 2), Int(scene.size.height * 2)) // Retina pixels
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            // Two seconds of frames: long enough for the typewriter to finish the first page.
            let start = CACurrentMediaTime() + 1 // SKRenderer ignores times earlier than the one it was created at
            for frame in 0...(name == "1.5x-talking" ? 100 : 30) { renderer.update(atTime: start + Double(frame) / 15) }
            // The first pass only uploads textures; the second one draws them.
            var buffer = try XCTUnwrap(queue.makeCommandBuffer())
            for _ in 0..<2 {
                buffer = try XCTUnwrap(queue.makeCommandBuffer())
                renderer.render(withViewport: CGRect(x: 0, y: 0, width: w, height: h), commandBuffer: buffer, renderPassDescriptor: pass)
                buffer.commit()
                buffer.waitUntilCompleted()
            }

            XCTAssertNil(buffer.error)
            if ProcessInfo.processInfo.environment["NOOK_DUMP"] != nil {
                for node in scene.children.last?.children ?? [] {
                    print(name, node.frame, node.isHidden, node.zPosition, (node as? SKSpriteNode)?.anchorPoint as Any, (node as? SKSpriteNode)?.texture?.size() as Any)
                }
            }
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            XCTAssertTrue(bytes.contains { $0 != 0 && $0 != 255 }, "something was drawn")
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let image = try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
        }
    }
}
