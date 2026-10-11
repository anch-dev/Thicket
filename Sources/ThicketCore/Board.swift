public struct Cell: Hashable, Codable, Comparable, CustomStringConvertible {
    public var col: Int
    public var row: Int

    public init(_ col: Int, _ row: Int) {
        self.col = col
        self.row = row
    }

    public static func < (a: Cell, b: Cell) -> Bool {
        a.col != b.col ? a.col < b.col : a.row < b.row
    }

    public var description: String { "(\(col),\(row))" }
}

/// The settled part of the playfield. Each column is stored bottom-to-top and is
/// always contiguous: gravity is enforced structurally, anything that loses its
/// support is taken out of the board and becomes a `Faller` until it lands.
public struct Board: Codable, Equatable {
    public let width: Int
    /// Full height of the field in rows.
    public let rows: Int
    /// Pieces may occupy rows `0..<ceiling`. The Canopy slamming down lowers it.
    public var ceiling: Int
    public internal(set) var columns: [[Piece]]

    public init(width: Int = Rules.soloColumns, rows: Int = Rules.soloRows) {
        self.width = width
        self.rows = rows
        self.ceiling = rows
        self.columns = Array(repeating: [], count: width)
    }

    public func contains(column c: Int) -> Bool { c >= 0 && c < width }

    public func height(_ c: Int) -> Int { contains(column: c) ? columns[c].count : 0 }

    public func piece(_ c: Int, _ r: Int) -> Piece? {
        guard contains(column: c), r >= 0, r < columns[c].count else { return nil }
        return columns[c][r]
    }

    public func piece(at cell: Cell) -> Piece? { piece(cell.col, cell.row) }

    public mutating func push(_ p: Piece, column c: Int) {
        columns[c].append(p)
    }

    /// Removes the piece at `row` and everything above it, bottom first.
    @discardableResult
    public mutating func removeFrom(column c: Int, row r: Int) -> [Piece] {
        guard r < columns[c].count else { return [] }
        let removed = Array(columns[c][r...])
        columns[c].removeSubrange(r...)
        return removed
    }

    public mutating func update(_ cell: Cell, _ transform: (inout Piece) -> Void) {
        transform(&columns[cell.col][cell.row])
    }

    public mutating func setColumn(_ c: Int, _ pieces: [Piece]) {
        columns[c] = pieces
    }

    public var allCells: [Cell] {
        var out: [Cell] = []
        for c in 0..<width {
            for r in 0..<columns[c].count { out.append(Cell(c, r)) }
        }
        return out
    }

    public var pieceCount: Int { columns.reduce(0) { $0 + $1.count } }
    public var miteCount: Int { columns.reduce(0) { $0 + $1.filter(\.isMite).count } }

    /// True when some column touches the Canopy.
    public var isOverflowing: Bool { columns.contains { $0.count >= ceiling } }

    public mutating func forEachPiece(_ body: (inout Piece) -> Void) {
        for c in 0..<width {
            for r in 0..<columns[c].count { body(&columns[c][r]) }
        }
    }
}

// MARK: - Text notation

/// Compact notation used by tests, lessons and debugging.
///
/// Rows are listed top to bottom, cells separated by spaces. `.` is empty.
/// Uppercase `E T B` = Ember/Tide/Bloom Mite, lowercase = Seed.
/// Suffixes: `*` Starseed (on a lowercase letter), `s` Slant, `x` Shifter, `f` Flicker.
/// Example: `["e . .", "E T Bs"]`.
public enum BoardNotationError: Error, Equatable {
    case badToken(String)
    case floatingPiece(Cell)
    case tooWide
}

extension Board {
    public static func parse(_ lines: [String], width: Int = Rules.soloColumns,
                             rows: Int = Rules.soloRows) throws -> Board {
        var board = Board(width: width, rows: rows)
        var nextID = 1
        // grid[row][col], row 0 = bottom
        var grid: [[Piece?]] = []
        for line in lines.reversed() {
            let tokens = line.split(separator: " ").map(String.init)
            if tokens.count > width { throw BoardNotationError.tooWide }
            var rowPieces: [Piece?] = []
            for t in tokens {
                rowPieces.append(try parseToken(t, id: &nextID))
            }
            while rowPieces.count < width { rowPieces.append(nil) }
            grid.append(rowPieces)
        }
        for c in 0..<width {
            var sawGap = false
            for r in 0..<grid.count {
                if let p = grid[r][c] {
                    if sawGap { throw BoardNotationError.floatingPiece(Cell(c, r)) }
                    board.push(p, column: c)
                } else {
                    sawGap = true
                }
            }
        }
        return board
    }

    static func parseToken(_ token: String, id: inout Int) throws -> Piece? {
        if token == "." { return nil }
        let chars = Array(token)
        let colors: [Character: PieceColor] = ["e": .ember, "t": .tide, "b": .bloom]
        guard let first = chars.first, let color = colors[Character(first.lowercased())] else {
            throw BoardNotationError.badToken(token)
        }
        let isMite = first.isUppercase
        defer { id += 1 }
        if chars.count == 1 {
            return isMite ? Piece.mite(color, id: id) : Piece.seed(color, id: id)
        }
        guard chars.count == 2 else { throw BoardNotationError.badToken(token) }
        switch (isMite, chars[1]) {
        case (false, "*"): return Piece.starseed(color, id: id)
        case (true, "s"): return Piece.mite(color, .slant, id: id)
        case (true, "x"): return Piece.mite(color, .shifter, id: id)
        case (true, "f"): return Piece.mite(color, .flicker, id: id)
        default: throw BoardNotationError.badToken(token)
        }
    }

    public static func token(for p: Piece) -> String {
        let letter: String
        switch p.color {
        case .ember: letter = "e"
        case .tide: letter = "t"
        case .bloom: letter = "b"
        }
        switch p.kind {
        case .seed: return letter
        case .starseed: return letter + "*"
        case .mite:
            let up = letter.uppercased()
            switch p.mite {
            case .common: return up
            case .slant: return up + "s"
            case .shifter: return up + "x"
            case .flicker: return up + "f"
            }
        }
    }

    /// Rows top to bottom in the same notation (empty rows above the tallest column
    /// and trailing empty cells are omitted).
    public var notation: [String] {
        let top = columns.map(\.count).max() ?? 0
        var lines: [String] = []
        for r in stride(from: top - 1, through: 0, by: -1) {
            var tokens = (0..<width).map { c in piece(c, r).map(Board.token(for:)) ?? "." }
            while tokens.last == "." { tokens.removeLast() }
            lines.append(tokens.joined(separator: " "))
        }
        return lines
    }
}
