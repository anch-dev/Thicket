/// A piece that is not part of the settled board: dropped by Wren or the Gloom,
/// dislodged by a clear, placed by Pip, or kicked.
public struct Faller: Codable, Equatable {
    public enum Origin: Int, Codable {
        case spawn
        case gravity
        case placed
        case kicked
    }

    public var piece: Piece
    public var column: Int
    /// Bottom edge, in sub-units (`row * Rules.sub`).
    public var y: Int
    /// Sub-units per tick.
    public var speed: Int
    /// Ticks to wait before starting to fall.
    public var hang: Int
    public var origin: Origin
    /// For kicked pieces: the column the slide started from (renderer only).
    public var slideFrom: Int?

    public init(piece: Piece, column: Int, row: Int, speed: Int, hang: Int = 0,
                origin: Origin, slideFrom: Int? = nil) {
        self.piece = piece
        self.column = column
        self.y = row * Rules.sub
        self.speed = speed
        self.hang = hang
        self.origin = origin
        self.slideFrom = slideFrom
    }

    /// True if this faller overlaps the given cell.
    public func overlaps(_ c: Int, _ r: Int) -> Bool {
        column == c && y < (r + 1) * Rules.sub && y + Rules.sub > r * Rules.sub
    }
}
