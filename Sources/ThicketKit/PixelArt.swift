import ThicketCore

/// An RGBA8 image (premultiplied alpha, rows top to bottom).
public struct PixelImage: Equatable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// Turns the text sprites in `SpriteData` into pixels.
public enum PixelArt {
    public static func colorName(_ c: PieceColor) -> String {
        switch c {
        case .ember: return "ember"
        case .tide: return "tide"
        case .bloom: return "bloom"
        }
    }

    public static func spriteName(for piece: Piece) -> String {
        switch piece.kind {
        case .mite: return "mite_" + colorName(piece.color)
        case .seed: return "seed_" + colorName(piece.color)
        case .starseed: return "starseed"
        }
    }

    public static func overlayName(for mite: MiteKind) -> String? {
        switch mite {
        case .common: return nil
        case .slant: return "overlay_slant"
        case .shifter: return "overlay_shifter"
        case .flicker: return "overlay_flicker"
        }
    }

    public static func rasterize(_ rows: [String], pieceColor: PieceColor? = nil,
                                 tint: UInt32? = nil) -> PixelImage {
        let h = rows.count
        let w = rows.map(\.count).max() ?? 0
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let pieceKeys = pieceColor.flatMap { SpriteData.pieceColors[colorName($0)] } ?? [:]
        for (y, row) in rows.enumerated() {
            for (x, key) in row.enumerated() where key != "." {
                guard var c = pieceKeys[key] ?? SpriteData.palette[key] ?? defaultPiece[key] else { continue }
                if let t = tint, key != "K" && key != "P" { c = t }
                let i = (y * w + x) * 4
                out[i] = UInt8(c >> 24 & 0xFF)
                out[i + 1] = UInt8(c >> 16 & 0xFF)
                out[i + 2] = UInt8(c >> 8 & 0xFF)
                out[i + 3] = UInt8(c & 0xFF)
            }
        }
        return PixelImage(width: w, height: h, rgba: out)
    }

    /// Piece keys used when no piece color applies (neutral grey).
    static let defaultPiece: [Character: UInt32] = ["1": 0xB0B0B0FF, "2": 0x707070FF, "3": 0xE0E0E0FF]

    public static func sprite(_ name: String, color: PieceColor? = nil, tint: UInt32? = nil) -> PixelImage? {
        SpriteData.sprites[name].map { rasterize($0, pieceColor: color, tint: tint) }
    }

    /// Renders text with the 5x7 font (1px spacing), in the given color.
    public static func text(_ s: String, color: UInt32 = 0xFFFFFFFF) -> PixelImage {
        let chars = Array(s.uppercased())
        let w = max(1, chars.count * 6 - 1)
        var rows = [String](repeating: "", count: 7)
        for (i, ch) in chars.enumerated() {
            let glyph = SpriteData.font[ch] ?? SpriteData.font["?"]!
            for r in 0..<7 { rows[r] += glyph[r] + (i < chars.count - 1 ? "." : "") }
        }
        var img = rasterize(rows.map { $0.isEmpty ? "." : $0 }, tint: nil)
        // Recolor the glyph pixels.
        for i in stride(from: 0, to: img.rgba.count, by: 4) where img.rgba[i + 3] > 0 {
            img.rgba[i] = UInt8(color >> 24 & 0xFF)
            img.rgba[i + 1] = UInt8(color >> 16 & 0xFF)
            img.rgba[i + 2] = UInt8(color >> 8 & 0xFF)
            img.rgba[i + 3] = UInt8(color & 0xFF)
        }
        img.width = w
        return img
    }
}
