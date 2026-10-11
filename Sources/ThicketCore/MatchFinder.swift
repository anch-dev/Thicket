public enum LineDirection: Int, Codable, CaseIterable, Hashable {
    case horizontal
    case vertical
    /// Bottom-left to top-right.
    case diagonalUp
    /// Top-left to bottom-right.
    case diagonalDown

    public var step: (dc: Int, dr: Int) {
        switch self {
        case .horizontal: return (1, 0)
        case .vertical: return (0, 1)
        case .diagonalUp: return (1, 1)
        case .diagonalDown: return (1, -1)
        }
    }

    public var isDiagonal: Bool { self == .diagonalUp || self == .diagonalDown }
}

public struct MatchLine: Equatable, Hashable {
    /// Cells in order along the direction.
    public var cells: [Cell]
    public var color: PieceColor
    public var direction: LineDirection

    public var length: Int { cells.count }
}

/// Finds valid lines: 3+ same-colored pieces in a straight line (horizontal,
/// vertical or diagonal) that include at least one Seed or Starseed.
/// Each maximal run is reported once; overlapping lines are all reported.
public enum MatchFinder {
    /// Slant Mites only take part in diagonal lines; elsewhere they break a run.
    public static func canJoin(_ p: Piece, _ direction: LineDirection) -> Bool {
        !(p.kind == .mite && p.mite == .slant && !direction.isDiagonal)
    }

    public static func findLines(in board: Board) -> [MatchLine] {
        var lines: [MatchLine] = []
        for direction in LineDirection.allCases {
            let (dc, dr) = direction.step
            for start in board.allCells {
                guard let p = board.piece(at: start), canJoin(p, direction) else { continue }
                // Only start scanning at the first cell of a run.
                if let prev = board.piece(start.col - dc, start.row - dr),
                   canJoin(prev, direction), prev.color == p.color {
                    continue
                }
                var cells = [start]
                var hasSeed = p.isSeedLike
                var c = start.col + dc
                var r = start.row + dr
                while let q = board.piece(c, r), canJoin(q, direction), q.color == p.color {
                    cells.append(Cell(c, r))
                    hasSeed = hasSeed || q.isSeedLike
                    c += dc
                    r += dr
                }
                if cells.count >= Rules.minMatch && hasSeed {
                    lines.append(MatchLine(cells: cells, color: p.color, direction: direction))
                }
            }
        }
        return lines
    }
}
