import ThicketCore
import XCTest

/// A frozen sandbox: no Wren/Gloom drops, no automatic win.
func sandbox(_ rows: [String], pip column: Int = 6, facing: Facing = .right,
             carrying: [Piece] = [], ceiling: Int? = nil, winOnClear: Bool = false,
             file: StaticString = #filePath, line: UInt = #line) -> GameState {
    var config = RoundConfig.lesson()
    config.endless = !winOnClear
    let board: Board
    do {
        board = try Board.parse(rows)
    } catch {
        XCTFail("bad board \(rows): \(error)", file: file, line: line)
        return GameState(config: config, seed: 1)
    }
    var pip = Pip(column: column, row: board.height(column))
    pip.facing = facing
    pip.carried = carrying
    var s = GameState(config: config, board: board, pip: pip)
    if let c = ceiling { s.board.ceiling = c }
    return s
}

extension GameState {
    /// Runs `ticks` ticks holding `input` (pressed only on the first tick).
    @discardableResult
    mutating func run(_ ticks: Int, holding held: Buttons = []) -> [GameEvent] {
        var all: [GameEvent] = []
        for _ in 0..<ticks { all += step(InputFrame(held: held)) }
        return all
    }

    /// Presses buttons for one tick, then idles until Pip and the board are calm.
    @discardableResult
    mutating func tap(_ b: Buttons, held: Buttons = []) -> [GameEvent] {
        var all = step(InputFrame(held: b.union(held), pressed: b))
        all += settle()
        return all
    }

    /// Idles until nothing is falling and Pip is idle (bounded).
    @discardableResult
    mutating func settle(max: Int = 900) -> [GameEvent] {
        var all: [GameEvent] = []
        var n = 0
        repeat {
            all += step(.none)
            n += 1
        } while n < max && status == .playing && (!fallers.isEmpty || pip.busy > 0 || !pipSupported || pip.falling)
        // a couple of extra ticks to let resolution finish
        all += step(.none)
        all += step(.none)
        return all
    }
}

extension Array where Element == GameEvent {
    var chainLevels: [Int] {
        compactMap { if case let .chain(l) = $0 { return l } else { return nil } }
    }

    var clears: [(cells: [Cell], chain: Int, score: Int)] {
        compactMap {
            if case let .cleared(cells, _, chain, score) = $0 { return (cells, chain, score) } else { return nil }
        }
    }

    func has(_ predicate: (GameEvent) -> Bool) -> Bool { contains(where: predicate) }
}

func notation(_ s: GameState) -> [String] { s.board.notation }
