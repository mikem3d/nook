import AppKit

/// Draws the speech bubble as pixel art, one image pixel per art pixel: a box with clipped
/// corners and a stepped tail that leans left toward the character.
enum BubbleArt {
    /// Rows of tail under the box.
    static let tail = 4

    /// `width` x `height` is the box; the image is `tail` rows taller. `tailX` is where the tail
    /// leaves the box, from the left. `more` adds a small arrow: another page follows.
    static func image(width w: Int, height h: Int, tailX: Int, more: Bool, ink: NSColor, paper: NSColor) -> CGImage? {
        guard w >= 8, h >= 4,
              let context = CGContext(data: nil, width: w, height: h + tail, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setShouldAntialias(false)
        func fill(_ color: NSColor?, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            let rect = CGRect(x: x, y: y, width: w, height: h)
            guard let color else { return context.clear(rect) }
            context.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)
            context.fill(rect)
        }
        let base = tail // the box's bottom row
        fill(ink, 0, base, w, h)
        fill(paper, 1, base + 1, w - 2, h - 2)
        for (x, y) in [(0, base), (w - 1, base), (0, base + h - 1), (w - 1, base + h - 1)] { fill(nil, x, y, 1, 1) }
        for (x, y) in [(1, base + 1), (w - 2, base + 1), (1, base + h - 2), (w - 2, base + h - 2)] { fill(ink, x, y, 1, 1) }

        // Tail: each row steps one pixel left and loses one pixel of width; the box opens onto it.
        fill(paper, tailX + 1, base, 3, 1)
        for row in 0..<tail {
            let (x, y, width) = (tailX - row, base - 1 - row, 5 - row)
            fill(ink, x, y, width, 1)
            if row < tail - 1 { fill(paper, x + 1, y, width - 2, 1) }
        }
        if more {
            fill(ink, w - 6, base + 3, 3, 1)
            fill(ink, w - 5, base + 2, 1, 1)
        }
        return context.makeImage()
    }
}
