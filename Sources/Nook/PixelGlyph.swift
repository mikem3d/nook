import AppKit
import SpriteKit

/// Tiny engine-drawn marks (the header's close glyph), one image pixel per art pixel.
enum PixelGlyph {
    static let close = ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"]

    /// Rows read top to bottom; "X" is a lit pixel.
    static func sprite(_ rows: [String], color: NSColor = .white) -> SKSpriteNode {
        let (w, h) = (rows.map(\.count).max() ?? 0, rows.count)
        guard w > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return SKSpriteNode() }
        context.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)
        for (y, row) in rows.enumerated() {
            for (x, mark) in row.enumerated() where mark == "X" {
                context.fill(CGRect(x: x, y: h - 1 - y, width: 1, height: 1))
            }
        }
        guard let image = context.makeImage() else { return SKSpriteNode() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return SKSpriteNode(texture: texture, size: CGSize(width: w, height: h))
    }
}
