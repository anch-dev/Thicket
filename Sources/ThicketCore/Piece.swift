/// The three piece colors. Each also has a distinct shape in the renderer so the
/// game is playable without relying on color.
public enum PieceColor: Int, Codable, CaseIterable, Hashable, Comparable {
    /// Orange, round.
    case ember = 0
    /// Blue, pointed.
    case tide = 1
    /// Pink, square.
    case bloom = 2

    /// The color a Shifter Mite turns into after its first hit.
    public var next: PieceColor { PieceColor(rawValue: (rawValue + 1) % PieceColor.allCases.count)! }

    public static func < (a: PieceColor, b: PieceColor) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .ember: return "Ember"
        case .tide: return "Tide"
        case .bloom: return "Bloom"
        }
    }
}

public enum PieceKind: Int, Codable, Hashable {
    case mite
    case seed
    case starseed
}

public enum MiteKind: Int, Codable, CaseIterable, Hashable {
    /// Cleared by any valid line.
    case common
    /// Only diagonal lines clear it (it does not take part in horizontal/vertical lines).
    case slant
    /// First hit changes its color; needs a second match in the new color.
    case shifter
    /// First hit makes it flash; must be hit again while flashing.
    case flicker
}

public struct Piece: Codable, Equatable, Hashable {
    /// Unique per game; lets the renderer track a piece across moves.
    public var id: Int
    public var kind: PieceKind
    public var color: PieceColor
    /// Only meaningful for mites.
    public var mite: MiteKind
    /// Shifter Mite has already been hit once.
    public var shifted: Bool
    /// Remaining flash time of a struck Flicker Mite (0 = not flashing).
    public var flashTicks: Int
    /// Chain level that dislodged this piece (0 = not part of a chain).
    public var chainTag: Int

    public init(id: Int, kind: PieceKind, color: PieceColor, mite: MiteKind = .common,
                shifted: Bool = false, flashTicks: Int = 0, chainTag: Int = 0) {
        self.id = id
        self.kind = kind
        self.color = color
        self.mite = mite
        self.shifted = shifted
        self.flashTicks = flashTicks
        self.chainTag = chainTag
    }

    public static func mite(_ color: PieceColor, _ kind: MiteKind = .common, id: Int = 0) -> Piece {
        Piece(id: id, kind: .mite, color: color, mite: kind)
    }

    public static func seed(_ color: PieceColor, id: Int = 0) -> Piece {
        Piece(id: id, kind: .seed, color: color)
    }

    public static func starseed(_ color: PieceColor, id: Int = 0) -> Piece {
        Piece(id: id, kind: .starseed, color: color)
    }

    public var isMite: Bool { kind == .mite }
    /// Seeds and Starseeds both satisfy the "line must contain a Seed" rule.
    public var isSeedLike: Bool { kind != .mite }
    public var isFlashing: Bool { kind == .mite && mite == .flicker && flashTicks > 0 }
}
