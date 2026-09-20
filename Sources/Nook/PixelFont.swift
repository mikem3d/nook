import AppKit
import CoreText
import SpriteKit

/// Word wrapping and paging on a monospace cell grid. Pure, so it can be tested headless.
enum TextPager {
    /// Greedy word wrap. Runs of whitespace and blank lines collapse; a word longer than a line is split.
    static func wrap(_ text: String, columns: Int) -> [String] {
        let columns = max(columns, 1)
        var lines: [String] = []
        for paragraph in text.split(whereSeparator: \.isNewline) {
            var line = ""
            for word in paragraph.split(whereSeparator: \.isWhitespace) {
                var word = String(word)
                if !line.isEmpty, line.count + 1 + word.count <= columns {
                    line += " " + word
                    continue
                }
                if !line.isEmpty { lines.append(line) }
                while word.count > columns {
                    lines.append(String(word.prefix(columns)))
                    word = String(word.dropFirst(columns))
                }
                line = word
            }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    static func pages(_ text: String, columns: Int, rows: Int) -> [[String]] {
        let lines = wrap(text, columns: columns)
        let rows = max(rows, 1)
        return stride(from: 0, to: lines.count, by: rows).map { Array(lines[$0..<min($0 + rows, lines.count)]) }
    }
}

/// The bundled pixel typeface (Departure Mono, SIL OFL 1.1), drawn one font pixel to one image
/// pixel with no smoothing, then scaled with nearest filtering exactly like the art.
/// Falls back to Menlo on the same cell grid if the font file is missing.
final class PixelFont {
    /// The cell every glyph is drawn in, in font pixels. Departure Mono is 7 wide on an 11 px em,
    /// with 2 px of descender below the baseline.
    static let cellW = 7
    static let cellH = 11
    static let descent = 2

    private(set) static var shared = PixelFont(font: CTFontCreateWithName("Menlo-Bold" as CFString, 11, nil), pixelated: false)

    /// Registers the bundled font for this process only. Call once at launch.
    static func register(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        // CTFontCreateWithName silently substitutes another face, so check what came back.
        let font = CTFontCreateWithName("DepartureMono-Regular" as CFString, CGFloat(cellH), nil)
        if (CTFontCopyPostScriptName(font) as String) == "DepartureMono-Regular" {
            shared = PixelFont(font: font, pixelated: true)
        }
    }

    /// Size of one font pixel in points at an art scale. One art pixel at 1x and 1.5x (11 pt and
    /// 16.5 pt text), half an art pixel at 2x (11 pt), so glyph pixels always sit on the art grid
    /// and are a whole number of device pixels on a Retina display.
    static func pixel(atScale s: CGFloat) -> CGFloat { s >= 2 ? s / 2 : s }

    let pixelated: Bool
    private let font: CTFont
    /// Image pixels per font pixel: 1 for the pixel face, 4 for the smooth fallback.
    private let density: Int

    private init(font: CTFont, pixelated: Bool) {
        self.font = font
        self.pixelated = pixelated
        density = pixelated ? 1 : 4
    }

    /// Lines of text as one image. `size` is in font pixels.
    func image(lines: [String], color: NSColor) -> (image: CGImage, size: CGSize)? {
        let columns = lines.map(\.count).max() ?? 0
        guard columns > 0 else { return nil }
        let (w, h) = (columns * Self.cellW, lines.count * Self.cellH)
        guard let context = CGContext(data: nil, width: w * density, height: h * density, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(density), y: CGFloat(density))
        context.setShouldAntialias(!pixelated)
        context.setShouldSmoothFonts(false)
        context.setShouldSubpixelPositionFonts(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)

        var glyphs: [CGGlyph] = []
        var positions: [CGPoint] = []
        for (row, line) in lines.enumerated() {
            let baseline = CGFloat(h - (row + 1) * Self.cellH + Self.descent)
            for (column, character) in line.enumerated() {
                let units = Array(String(character).utf16.prefix(1))
                var glyph = CGGlyph(0)
                guard CTFontGetGlyphsForCharacters(font, units, &glyph, 1), glyph != 0 else { continue }
                glyphs.append(glyph)
                positions.append(CGPoint(x: CGFloat(column * Self.cellW), y: baseline))
            }
        }
        CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
        guard let image = context.makeImage() else { return nil }
        return (image, CGSize(width: w, height: h))
    }

    func texture(lines: [String], color: NSColor) -> (texture: SKTexture, size: CGSize)? {
        guard let (image, size) = image(lines: lines, color: color) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = pixelated ? .nearest : .linear
        return (texture, size)
    }
}
