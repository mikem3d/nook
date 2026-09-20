import XCTest
import SpriteKit
import Metal

/// Draws an SKScene into a Metal texture at Retina density and hands back a CGImage.
final class OffscreenRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    /// SKRenderer ignores times earlier than the one it was created at, so every scene gets its own clock.
    private var clock = CACurrentMediaTime() + 1

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw XCTSkip("no Metal device") }
        self.device = device
        self.queue = queue
    }

    /// Runs the scene for `seconds` at 15 fps, then draws it.
    func image(of scene: SKScene, seconds: Double) throws -> CGImage {
        let renderer = SKRenderer(device: device)
        renderer.scene = scene
        let (w, h) = (Int(scene.size.width * 2), Int(scene.size.height * 2))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        for _ in 0...Int(seconds * 15) {
            clock += 1.0 / 15
            renderer.update(atTime: clock)
        }
        // The first pass only uploads textures; the second one draws them.
        for _ in 0..<2 {
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            renderer.render(withViewport: CGRect(x: 0, y: 0, width: w, height: h), commandBuffer: buffer, renderPassDescriptor: pass)
            buffer.commit()
            buffer.waitUntilCompleted()
            XCTAssertNil(buffer.error)
        }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// Images butted together with no gap, the way docked windows sit, so seams can be judged.
    func stitch(_ images: [CGImage], vertical: Bool, gap: Int = 0) throws -> CGImage {
        let w = vertical ? images.map(\.width).max() ?? 0 : images.reduce(0) { $0 + $1.width } + gap * (images.count - 1)
        let h = vertical ? images.reduce(0) { $0 + $1.height } + gap * (images.count - 1) : images.map(\.height).max() ?? 0
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        var offset = 0
        for image in images {
            // CGContext's origin is bottom-left; a vertical stack lists its images top to bottom.
            let origin = vertical ? CGPoint(x: 0, y: h - offset - image.height) : CGPoint(x: offset, y: 0)
            context.draw(image, in: CGRect(origin: origin, size: CGSize(width: image.width, height: image.height)))
            offset += (vertical ? image.height : image.width) + gap
        }
        return try XCTUnwrap(context.makeImage())
    }

    func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// Alpha of one pixel, x and y from the top-left.
    static func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel[3]
    }
}
