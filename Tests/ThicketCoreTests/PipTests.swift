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
        XCTAssertEqual(s.pip.cell, Cell(3, 1), "walking into a 2-high wall climbs its side")
        XCTAssertTrue(s.pip.clinging)
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
        // Climbing while carrying works when the load fits under the Canopy…
        var b = sandbox([". . . . E", ". . . . T"], pip: 3, carrying: [.seed(.tide, id: 99)])
        XCTAssertTrue(b.perform(.climb))
        // …but not when the load would hit it.
        var b2 = sandbox([". . . . E", ". . . . T"], pip: 3,
                         carrying: [.seed(.tide, id: 98), .seed(.bloom, id: 99)], ceiling: 3)
        XCTAssertFalse(b2.perform(.climb))
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
        XCTAssertTrue(s.tap(.a).has { $0 == .placed(count: 3) })
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
        let ev = s.tap(.a)
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
        XCTAssertTrue(t.perform(.walkRight), "steps up with the load")
        XCTAssertEqual(t.pip.cell, Cell(4, 1))
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

    // MARK: Placing below, climbing by walking, rejection reasons

    func testDownPutsLoadUnderPip() {
        var s = sandbox([". . . . T", ". . . . E"], pip: 3, facing: .right)
        s.tap(.a) // lift 2
        XCTAssertEqual(s.pip.carried.count, 2)
        let ev = s.tap(.down)
        XCTAssertTrue(ev.has { $0 == .placedBelow(count: 2) })
        XCTAssertTrue(s.pip.carried.isEmpty)
        XCTAssertEqual(s.pip.cell, Cell(3, 2), "Pip stands on top of what he put down")
        XCTAssertEqual(s.board.notation, [". . . T", ". . . E"])
    }

    func testDownPutsLoadUnderPipOnTopOfAStack() {
        var s = sandbox([". . . B"], pip: 3, carrying: [.mite(.ember, id: 90)])
        XCTAssertEqual(s.pip.row, 1)
        s.tap(.down)
        XCTAssertEqual(s.board.notation, [". . . E", ". . . B"])
        XCTAssertEqual(s.pip.row, 2)
    }

    func testPlaceBelowCanMakeAMatch() {
        var s = sandbox(["E E"], pip: 2, carrying: [.seed(.ember, id: 90)])
        let ev = s.tap(.down)
        XCTAssertEqual(ev.clears.count, 1)
        XCTAssertEqual(s.board.pieceCount, 0)
        XCTAssertEqual(s.pip.row, 0, "Pip drops back down after the clear")
    }

    func testHoldingTowardAStackClimbsAllTheWayUp() {
        var s = sandbox([". . . . E", ". . . . T", ". . . . B"], pip: 3, facing: .right)
        var n = 0
        while s.pip.cell != Cell(4, 3) && n < 120 {
            s.step(InputFrame(held: .right))
            n += 1
        }
        XCTAssertEqual(s.pip.cell, Cell(4, 3), "climbed the side and stepped onto the top")
        XCTAssertFalse(s.pip.clinging)
    }

    func testCanClimbOutOfAPitWhileCarrying() {
        var s = sandbox([". . T", "E . B"], pip: 1, facing: .right, carrying: [.seed(.tide, id: 90)])
        var n = 0
        while s.pip.cell != Cell(2, 2) && n < 120 {
            s.step(InputFrame(held: .right))
            n += 1
        }
        XCTAssertEqual(s.pip.cell, Cell(2, 2))
        XCTAssertEqual(s.pip.carried.count, 1)
    }

    func testRejectedActionsExplainWhy() {
        var s = sandbox([], pip: 3)
        let ev = s.tap(.a)
        XCTAssertTrue(ev.has {
            if case let .actionRejected(action, reason) = $0 { return action == .liftStack && !reason.isEmpty }
            return false
        })
        var t = sandbox([". . . . E"], pip: 3, facing: .right, carrying: [.mite(.tide, id: 90)])
        let ev2 = t.tap(.a)
        XCTAssertTrue(ev2.has {
            if case let .actionRejected(action, reason) = $0 { return action == .place && reason.contains("Down") }
            return false
        })
    }

    // MARK: Classic button mapping while carrying

    func testUpAndABAlsoDropTheLoadUnderPip() {
        for press in [Buttons.up, [.a, .b]] {
            var s = sandbox([], pip: 3, carrying: [.mite(.ember, id: 90), .mite(.tide, id: 91)])
            XCTAssertTrue(s.tap(press).has { $0 == .placedBelow(count: 2) })
            XCTAssertEqual(s.pip.cell, Cell(3, 2))
            XCTAssertEqual(s.board.height(3), 2)
        }
    }

    func testBPutsDownOnlyTheBottomPiece() {
        var s = sandbox([], pip: 3, facing: .right,
                        carrying: [.mite(.ember, id: 90), .mite(.tide, id: 91), .mite(.bloom, id: 92)])
        s.tap(.b)
        XCTAssertEqual(s.board.notation, [". . . . E"])
        XCTAssertEqual(s.pip.carried.map(\.id), [91, 92])
    }

    func testDownPlusBKicksToo() {
        var s = sandbox([". T"], pip: 0, facing: .right)
        XCTAssertTrue(s.tap(.b, held: .down).has { if case .kicked = $0 { return true } else { return false } })
    }
}
