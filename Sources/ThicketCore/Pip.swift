public enum Facing: Int, Codable, Hashable {
    case left = -1
    case right = 1

    public var opposite: Facing { self == .left ? .right : .left }
}

public enum PipMotion: Int, Codable, Hashable {
    case idle, walk, climb, fall, turn, lift, pull, place, kick
}

/// The hero. Occupies one cell; anything carried sits in the cells above it.
public struct Pip: Codable, Equatable {
    public var column: Int
    public var row: Int
    public var facing: Facing = .right
    /// Hanging on the side of the stack Pip is facing (after climbing up it).
    public var clinging = false
    /// Carried pieces, bottom to top.
    public var carried: [Piece] = []

    /// Current motion and ticks left in it. Pip's logical position is already the
    /// destination; the renderer interpolates from `fromColumn/fromRow`.
    public var motion: PipMotion = .idle
    public var busy = 0
    public var motionTicks = 0
    public var fromColumn: Int
    public var fromRow: Int

    /// Ticks the current walking direction has been held.
    public var holdTicks = 0
    public var falling = false

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
        self.fromColumn = column
        self.fromRow = row
    }

    public var isCarrying: Bool { !carried.isEmpty }
    public var cell: Cell { Cell(column, row) }
    /// Top edge (sub-units) of Pip plus whatever he carries.
    public var topY: Int { (row + 1 + carried.count) * Rules.sub }

    /// 0 → just started the motion, 1 → finished.
    public var motionProgress: Double {
        motionTicks > 0 ? 1 - Double(busy) / Double(motionTicks) : 1
    }

    mutating func begin(_ m: PipMotion, ticks: Int, from: Cell) {
        motion = m
        busy = ticks
        motionTicks = ticks
        fromColumn = from.col
        fromRow = from.row
    }
}
