import ThicketCore
import XCTest

final class PipTests: XCTestCase {
    // MARK: Walking

    func testTapOppositeDirectionTurnsBeforeWalking() {
        var s = sandbox([], pip: 3, facing: .right)
        s.tap(.left)
        XCTAssertEqual(s.pip.facing, .left)
        XCTAssertEqual(s.pip.column, 3, "first tap only turns")
        s.tap(.left)
        XCTAssertEqual(s.pip.column, 2)
    }

    func testHoldingWalksContinuouslyAndStopsAtWall() {
        var s = sandbox([], pip: 0, facing: .right)
        s.run(200, holding: .right)
        XCTAssertEqual(s.pip.column, 6)
    }

    func testStepUpOneButNotTwo() {
        var s = sandbox([". . . . T", ". . E . B"], pip: 1, facing: .right)
        s.tap(.right)
        XCTAssertEqual(s.pip.cell, Cell(2, 1), "stepped up onto a 1-high stack")
        s.tap(.right)
        XCTAssertEqual(s.pip.cell, Cell(3, 0), "walked off the edge and stepped down")
        s.tap(.right)
        XCTAssertEqual(s.pip.cell, Cell(3, 0), "a 2-high wall blocks walking")
    }

    // MARK: Climbing

    func testClimbSideOfStackOneCellAtATime() {
        var s = sandbox([". . . . E", ". . . . T", ". . . . B"], pip: 3, facing: .right)
        s.tap(.up)
        XCTAssertEqual(s.pip.cell, Cell(3, 1))
        XCTAssertTrue(s.pip.clinging)
        s.run(30)
        XCTAssertEqual(s.pip.cell, Cell(3, 1), "clinging holds Pip in place")
        s.tap(.up)
        XCTAssertEqual(s.pip.cell, Cell(3, 2))
        s.tap(.up)
        XCTAssertEqual(s.pip.cell, Cell(4, 3), "clambered onto the top")
        XCTAssertFalse(s.pip.clinging)
    }

    func testClimbDownAndLetGo() {
        var s = sandbox([". . . . E", ". . . . T", ". . . . B"], pip: 3, facing: .right)
        s.tap(.up)
        s.tap(.up)
        XCTAssertEqual(s.pip.row, 2)
        s.tap(.down)
        XCTAssertEqual(s.pip.row, 1)
        XCTAssertTrue(s.pip.clinging)
        s.tap(.left) // let go
        s.settle()
        XCTAssertEqual(s.pip.cell, Cell(3, 0))
        XCTAssertFalse(s.pip.clinging)
    }

    func testClimbingLimits() {
        // Cannot climb with nothing in front.
        var a = sandbox([], pip: 3)
        XCTAssertFalse(a.perform(.climb))
        // Cannot climb while carrying.
        var b = sandbox([". . . . E", ". . . . T"], pip: 3, carrying: [.seed(.tide, id: 99)])
        XCTAssertFalse(b.perform(.climb))
        // Cannot climb into an occupied cell (a piece is falling right above Pip).
        var c = sandbox([". . . . E", ". . . . T"], pip: 3)
        c.fallers.append(Faller(piece: .seed(.tide, id: 98), column: 3, row: 1, speed: 2, hang: 100, origin: .spawn))
        XCTAssertFalse(c.perform(.climb))
        // On top of the highest stack under the Canopy there is nothing left to climb.
        var d = sandbox([". . . E T", ". . . T E"], pip: 3, ceiling: 3)
        XCTAssertEqual(d.pip.row, 2)
        XCTAssertFalse(d.perform(.climb))
    }

    // MARK: Lifting and placing

    func testLiftWholeStack() {
        var s = sandbox([". . . . B", ". . . . T", ". . . . E"], pip: 3, facing: .right)
        let ev = s.tap(.a)
        XCTAssertTrue(ev.has { $0 == .lifted(count: 3) })
        XCTAssertEqual(s.pip.carried.map(\.color), [.ember, .tide, .bloom])
        XCTAssertEqual(s.board.height(4), 0)
    }

    func testLiftFromMiddleOfStackWhileClinging() {
        var s = sandbox([". . . . B", ". . . . T", ". . . . E"], pip: 3, facing: .right)
        s.tap(.up) // cling at row 1
        s.tap(.a)
        XCTAssertEqual(s.pip.carried.map(\.color), [.tide, .bloom])
        XCTAssertEqual(s.board.height(4), 1)
    }

    func testPullSinglePieceLetsTheRestDrop() {
        var s = sandbox([". . . . B", ". . . . T", ". . . . E"], pip: 3, facing: .right)
        let ev = s.tap(.b)
        XCTAssertTrue(ev.has { $0 == .pulled })
        XCTAssertEqual(s.pip.carried.map(\.color), [.ember])
        XCTAssertEqual(s.board.notation, [". . . . B", ". . . . T"])
    }

    func testPlaceWholeStackInAdjacentColumn() {
        var s = sandbox([". . . . B", ". . . . T", ". . . . E"], pip: 3, facing: .right)
        s.tap(.a)
        s.tap(.left) // turn
        XCTAssertTrue(s.tap(.up).has { $0 == .placed(count: 3) })
        XCTAssertTrue(s.pip.carried.isEmpty)
        XCTAssertEqual(s.board.notation, [". . B", ". . T", ". . E"])
    }

    func testABAndAAlsoPlace() {
        var s = sandbox([], pip: 3, carrying: [.mite(.ember, id: 90)])
        XCTAssertTrue(s.tap([.a, .b]).has { $0 == .placed(count: 1) })
        var t = sandbox([], pip: 3, carrying: [.mite(.ember, id: 90)])
        XCTAssertTrue(t.tap(.a).has { $0 == .placed(count: 1) })
    }

    func testPlaceBlockedWhenFrontOccupied() {
        var s = sandbox([". . . . E"], pip: 3, facing: .right, carrying: [.mite(.tide, id: 90)])
        let ev = s.tap(.up)
        XCTAssertTrue(ev.has { $0 == .bump })
        XCTAssertEqual(s.pip.carried.count, 1)
    }

    func testCannotReachPiecesNotInFront() {
        // The stack is two columns away.
        var s = sandbox([". . . . . E"], pip: 3, facing: .right)
        XCTAssertFalse(s.perform(.liftStack))
        XCTAssertFalse(s.perform(.kick))
        // A piece diagonally below is not "in front" either.
        var t = sandbox([". . . E", ". . . T B"], pip: 3, facing: .right)
        XCTAssertEqual(t.pip.row, 2)
        XCTAssertFalse(t.perform(.liftStack))
    }

    func testCarryingBlocksWalkingUnderLowCeiling() {
        var s = sandbox([], pip: 3, facing: .right,
                        carrying: [.mite(.ember, id: 90), .mite(.tide, id: 91)], ceiling: 3)
        XCTAssertTrue(s.perform(.walkRight))
        var t = sandbox([". . . . E"], pip: 3, facing: .right, carrying: [.mite(.ember, id: 90)])
        XCTAssertFalse(t.perform(.walkRight), "no stepping up while carrying")
    }

    // MARK: Kicking

    func testKickSlidesUntilItHitsAPiece() {
        var s = sandbox([". T . . . . B"], pip: 0, facing: .right)
        let ev = s.tap(.a, held: .down)
        XCTAssertTrue(ev.has { $0 == .kicked(from: Cell(1, 0), to: Cell(5, 0)) })
        XCTAssertEqual(s.board.notation, [". . . . . T B"])
    }

    func testKickSlidesToTheWall() {
        var s = sandbox([". . . T"], pip: 4, facing: .left)
        s.tap(.a, held: .down)
        XCTAssertEqual(s.board.notation, ["T"])
    }

    func testKickBlockedByAdjacentPiece() {
        var s = sandbox([". T B"], pip: 0, facing: .right)
        XCTAssertTrue(s.tap(.a, held: .down).has { $0 == .bump })
        XCTAssertEqual(s.board.notation, [". T B"])
    }

    func testKickedPieceFallsAfterSliding() {
        var s = sandbox([". T", "E B"], pip: 0, facing: .right)
        XCTAssertEqual(s.pip.row, 1)
        s.tap(.a, held: .down)
        XCTAssertEqual(s.board.notation, ["E B . . . . T"])
    }

    func testKickTakesPieceFromUnderAStack() {
        var s = sandbox([". E", ". T"], pip: 0, facing: .right)
        s.tap(.a, held: .down)
        XCTAssertEqual(s.board.notation, [". E . . . . T"])
    }

    // MARK: Input buffering

    func testPressDuringWalkIsBuffered() {
        var s = sandbox([". . . . . E"], pip: 3, facing: .right)
        s.step(.tap(.right)) // starts walking to column 4
        XCTAssertEqual(s.pip.busy, Rules.pipWalkTicks)
        s.run(Rules.pipWalkTicks - 2)
        s.step(.tap(.a)) // one frame early
        XCTAssertFalse(s.pip.isCarrying)
        s.run(3)
        XCTAssertTrue(s.pip.isCarrying, "early press still registered")
    }

    func testBufferExpires() {
        var s = sandbox([". . . . E"], pip: 3, facing: .right)
        s.pip.busy = 30
        s.step(.tap(.a))
        s.run(40)
        XCTAssertFalse(s.pip.isCarrying)
    }
}
