import ThicketCore
import XCTest

final class ResolveTests: XCTestCase {
    func resolve(_ board: inout Board) -> ResolveResult {
        var id = 10_000
        return board.resolve(lines: MatchFinder.findLines(in: board), nextID: &id)
    }

    func testSimpleClearAndScore() throws {
        var b = try Board.parse(["E E e T"])
        let r = resolve(&b)
        XCTAssertEqual(r.removed, [Cell(0, 0), Cell(1, 0), Cell(2, 0)])
        XCTAssertEqual(r.chainLevel, 1)
        XCTAssertEqual(r.score, 2 * Rules.miteScore + Rules.seedScore)
        XCTAssertEqual(b.notation, [". . . T"])
    }

    func testOverlappingLinesResolveTogether() throws {
        var b = try Board.parse([
            "E e E",
            "T E B",
            "B E T",
        ])
        let r = resolve(&b)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.removed.count, 5, "shared seed removed once")
        XCTAssertEqual(r.score, 4 * Rules.miteScore + Rules.seedScore)
        // Column 0 and 2 keep their bottom two pieces, column 1 is emptied.
        XCTAssertEqual(b.height(0), 2)
        XCTAssertEqual(b.height(1), 0)
        XCTAssertEqual(b.height(2), 2)
        XCTAssertTrue(r.newFallers.isEmpty)
    }

    func testSimultaneousSeparateMatches() throws {
        var b = try Board.parse(["E E e B t T T"])
        let r = resolve(&b)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(b.notation, [". . . B"])
    }

    func testLongLineCreatesStarseed() throws {
        var b = try Board.parse(["E E e E E"])
        let r = resolve(&b)
        XCTAssertEqual(r.starseedsCreated, [Cell(2, 0)])
        XCTAssertEqual(b.notation, [". . e*"])
        XCTAssertEqual(r.score, (4 * Rules.miteScore + Rules.seedScore + 2 * Rules.longLineBonusPerPiece))
    }

    func testFourDoesNotCreateStarseed() throws {
        var b = try Board.parse(["E E e E"])
        let r = resolve(&b)
        XCTAssertTrue(r.starseedsCreated.isEmpty)
        XCTAssertEqual(b.pieceCount, 0)
    }

    func testStarseedClearsEveryMiteOfItsColor() throws {
        var b = try Board.parse([
            ". . . . Ex . .",
            "E E e* . T E B",
        ])
        let r = resolve(&b)
        XCTAssertEqual(r.burstColors, [.ember])
        XCTAssertEqual(b.miteCount, 2)
        XCTAssertEqual(b.notation, [". . . . T . B"])
        XCTAssertEqual(r.removedMites, 4)
    }

    func testSlantClearedOnlyDiagonally() throws {
        var flat = try Board.parse(["Es E e"])
        XCTAssertTrue(resolve(&flat).removed.isEmpty)
        var diag = try Board.parse([
            ". . e",
            ". E T",
            "Es T B",
        ])
        let r = resolve(&diag)
        XCTAssertEqual(r.removedMites, 2)
        XCTAssertEqual(diag.miteCount, 3)
    }

    func testShifterNeedsSecondMatchInNewColor() throws {
        var b = try Board.parse(["Ex E e"])
        let r1 = resolve(&b)
        XCTAssertEqual(r1.hits, [Cell(0, 0)])
        let shifter = try XCTUnwrap(b.piece(0, 0))
        XCTAssertTrue(shifter.shifted)
        XCTAssertEqual(shifter.color, .tide, "ember → tide")
        XCTAssertEqual(b.pieceCount, 1)

        // A second ember line no longer reaches it…
        b.push(.mite(.ember, id: 50), column: 1)
        b.push(.seed(.ember, id: 51), column: 2)
        XCTAssertTrue(MatchFinder.findLines(in: b).isEmpty)
        // …but a tide line clears it.
        b.removeFrom(column: 1, row: 0)
        b.removeFrom(column: 2, row: 0)
        b.push(.mite(.tide, id: 52), column: 1)
        b.push(.seed(.tide, id: 53), column: 2)
        let r2 = resolve(&b)
        XCTAssertTrue(r2.removed.contains(Cell(0, 0)))
        XCTAssertEqual(b.pieceCount, 0)
    }

    func testFlickerMustBeHitWhileFlashing() throws {
        var b = try Board.parse(["Ef E e"])
        let r1 = resolve(&b)
        XCTAssertEqual(r1.hits, [Cell(0, 0)])
        XCTAssertEqual(b.piece(0, 0)?.flashTicks, Rules.flickerFlashTicks)
        b.push(.mite(.ember, id: 60), column: 1)
        b.push(.seed(.ember, id: 61), column: 2)
        let r2 = resolve(&b)
        XCTAssertTrue(r2.removed.contains(Cell(0, 0)))
        XCTAssertEqual(b.pieceCount, 0)
    }

    func testFlickerFlashExpires() {
        var s = sandbox(["Ef E e"])
        s.run(1)
        XCTAssertTrue(s.board.piece(0, 0)?.isFlashing == true)
        s.run(Rules.flickerFlashTicks)
        XCTAssertEqual(s.board.piece(0, 0)?.isFlashing, false)
        // Hitting it again now only starts a new flash.
        s.board.push(.mite(.ember, id: 70), column: 1)
        s.board.push(.seed(.ember, id: 71), column: 2)
        let ev = s.run(1)
        XCTAssertTrue(ev.has { $0 == .hit(cell: Cell(0, 0)) })
        XCTAssertEqual(s.board.miteCount, 1)
    }

    func testPiecesAboveAClearFall() throws {
        var b = try Board.parse([
            "B . .",
            "T . .",
            "E E e",
        ])
        let r = resolve(&b)
        XCTAssertEqual(r.newFallers.count, 2)
        XCTAssertTrue(r.newFallers.allSatisfy { $0.piece.chainTag == 1 && $0.hang == Rules.clearHangTicks })
        XCTAssertEqual(b.pieceCount, 0, "dislodged pieces leave the settled board")
    }

    func testGravitySettlesInOrder() {
        var s = sandbox([
            "B . .",
            "T . .",
            "E E e",
        ])
        s.settle()
        XCTAssertEqual(s.board.notation, ["B", "T"], "T then B, now at rows 0-1")
        XCTAssertTrue(s.fallers.isEmpty)
    }
}
