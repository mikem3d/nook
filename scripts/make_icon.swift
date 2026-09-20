// Renders the placeholder app icon: a 16x16 pixel drawing of an agent window, scaled without
// smoothing to every size an .iconset needs.
//
//   swift scripts/make_icon.swift <out.iconset>     then: iconutil -c icns <out.iconset>
//
// Replace the grid (or the whole icon) when real art exists; nothing else depends on it.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let grid = [
    "................",
    ".kkkkkkkkkkkkkk.",
    ".kttttttttttgtk.",
    ".kkkkkkkkkkkkkk.",
    ".kbbbbbbbbbbbbk.",
    ".kbwwbbbbbbbbbk.",
    ".kbwwbbhhhhbbbk.",
    ".kbbbbhhhhhhbbk.",
    ".kbbbbhsssshbbk.",
    ".kbbbbskssksbbk.",
    ".kbbbbbssssbbbk.",
    ".kbbbbccccccbbk.",
    ".kbbbccccccccbk.",
    ".kffffffffffffk.",
    ".kkkkkkkkkkkkkk.",
    "................",
]

let palette: [Character: UInt32] = [
    "k": 0x1B1C2E, // outline
    "t": 0x4A4E8C, // title bar
    "g": 0x6FDC8C, // state dot
    "b": 0x2B2D52, // room
    "w": 0xFFD36B, // lit window
    "h": 0x6B3F2A, // hair
    "s": 0xF2C39B, // skin
    "c": 0xE0654F, // shirt
    "f": 0x3C3F6E, // floor
]

func render(_ size: Int, to url: URL) throws {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    ctx.setShouldAntialias(false)
    let cell = CGFloat(size) / CGFloat(grid.count)
    for (row, line) in grid.enumerated() {
        for (col, ch) in line.enumerated() {
            guard let rgb = palette[ch] else { continue }
            ctx.setFillColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                             blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
            // Core Graphics counts rows from the bottom.
            ctx.fill(CGRect(x: CGFloat(col) * cell, y: CGFloat(grid.count - 1 - row) * cell, width: cell, height: cell))
        }
    }
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make_icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(points, to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2, to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
