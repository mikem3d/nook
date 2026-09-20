import CoreGraphics

/// Recolours pixel art by exact colour match, so one character sheet serves every avatar variant.
enum PaletteSwap {
    /// "rrggbb" (a leading # is fine) as 0xRRGGBB.
    static func key(_ hex: String) -> UInt32? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        return digits.count == 6 ? UInt32(digits, radix: 16) : nil
    }

    static func table(_ swap: [String: String]) -> [UInt32: UInt32] {
        var table: [UInt32: UInt32] = [:]
        for (from, to) in swap {
            if let from = key(from), let to = key(to) { table[from] = to }
        }
        return table
    }

    /// Every opaque pixel is looked up in the ORIGINAL image, so swaps never chain (a to b, b to c).
    static func apply(_ image: CGImage, table: [UInt32: UInt32]) -> CGImage? {
        let (w, h) = (image.width, image.height)
        guard !table.isEmpty,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) where pixels[i + 3] == 255 {
            let colour = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            guard let to = table[colour] else { continue }
            pixels[i] = UInt8(to >> 16 & 0xFF)
            pixels[i + 1] = UInt8(to >> 8 & 0xFF)
            pixels[i + 2] = UInt8(to & 0xFF)
        }
        return context.makeImage()
    }
}
